import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import {
  buildDishImageDeepSearchQuery,
  buildDishImageProbeQuery,
  sanitizeDishImageQualifier,
} from "../_shared/dish_image_query.ts";
import {
  type DishImageVisualReview,
  filterCandidatesToApprovedThumbnails,
  normalizeTrustedThumbnailUrl,
  reviewDishImageCandidates,
} from "../_shared/dish_image_review.ts";
import { deriveDishImageProbeOutcome } from "../_shared/dish_image_review_outcome.ts";
import { cleanMenuName } from "../_shared/menu_name.ts";

const SERPAPI_ENDPOINT = "https://serpapi.com/search.json";
const MAX_ORIGINAL_NAME_LENGTH = 200;
const MAX_CONTEXT_LENGTH = 160;
const SERPAPI_TIMEOUT_MS = 5000;
const NON_FOOD_RESULT_PATTERNS = [
  /甲沟炎|灰指甲|趾甲|皮肤病|皮肤科|医疗|医院|疾病|手术|治疗|感染|患者|病例|病症/iu,
  /\b(?:ingrown\s+toenail|toenail|podiatr(?:y|ic|ist)?|dermatolog(?:y|ist)?|medical|clinic|hospital|surgery|infection|disease|patient|treatment)\b/iu,
];

type SerpApiImageResult = {
  position?: number;
  title?: string;
  source?: string;
  link?: string;
  thumbnail?: string;
  original?: string;
  original_width?: number;
  original_height?: number;
};

type SerpApiResponse = {
  error?: unknown;
  images_results?: unknown;
};

type DishImageResult = {
  title: string;
  pageUrl: string;
  fullUrl: string;
  thumbUrl?: string;
  width?: number;
  height?: number;
  source?: string;
  position?: number;
};

function json(data: unknown, status = 200, extraHeaders: HeadersInit = {}) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "cache-control": "public, max-age=300",
      ...extraHeaders,
    },
  });
}

function corsHeaders(origin: string | null): HeadersInit {
  return {
    "access-control-allow-origin": origin ?? "*",
    "access-control-allow-headers":
      "authorization, x-client-info, apikey, content-type",
    "access-control-allow-methods": "GET, OPTIONS",
  };
}

function clamp(n: number, min: number, max: number) {
  return Math.max(min, Math.min(max, n));
}

function isHttpUrl(value: unknown): value is string {
  return typeof value === "string" && /^https?:\/\//i.test(value);
}

function cleanString(value: unknown): string | undefined {
  if (typeof value !== "string") return undefined;
  const clean = value.trim();
  return clean ? clean : undefined;
}

function cleanSearchTerm(
  value: unknown,
  maxLength: number,
): string | undefined {
  const normalized = cleanString(value)?.replace(/\s+/g, " ");
  const clean = normalized ? cleanMenuName(normalized) : undefined;
  return clean?.slice(0, maxLength);
}

function isLikelyNonFoodResult(item: SerpApiImageResult): boolean {
  const searchable = [item.title, item.source, item.link, item.original]
    .filter((value): value is string => typeof value === "string")
    .join(" ")
    .normalize("NFKC");

  return NON_FOOD_RESULT_PATTERNS.some((pattern) => pattern.test(searchable));
}

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value?.trim()) return value.trim();
  throw new Error(`Missing required env var: ${name}`);
}

async function fetchWithTimeout(
  input: RequestInfo | URL,
  init: RequestInit = {},
  timeoutMs = 20000,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(
    () => controller.abort("Request timeout"),
    timeoutMs,
  );

  try {
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

async function fetchSerpApiImageCandidates(
  q: string,
  hl: string,
  gl: string,
): Promise<SerpApiImageResult[]> {
  const params = new URLSearchParams({
    engine: "google_images",
    q,
    api_key: getRequiredEnv("SERPAPI_API_KEY"),
    hl,
    gl,
    safe: "active",
    ijn: "0",
  });

  const res = await fetchWithTimeout(
    `${SERPAPI_ENDPOINT}?${params.toString()}`,
    {},
    SERPAPI_TIMEOUT_MS,
  );
  const body = await res.text();

  if (!res.ok) {
    throw new Error(
      `SerpApi image search failed: HTTP ${res.status} ${body.slice(0, 300)}`,
    );
  }

  let data: SerpApiResponse;
  try {
    data = JSON.parse(body) as SerpApiResponse;
  } catch {
    throw new Error(
      `SerpApi returned non-JSON response: ${body.slice(0, 300)}`,
    );
  }

  if (typeof data.error === "string" && data.error.trim()) {
    throw new Error(`SerpApi image search failed: ${data.error.trim()}`);
  }

  return Array.isArray(data.images_results)
    ? data.images_results.filter((item): item is SerpApiImageResult =>
      Boolean(item) && typeof item === "object"
    )
    : [];
}

function mapClientResults(
  rawResults: SerpApiImageResult[],
  q: string,
  limit: number,
): DishImageResult[] {
  const seen = new Set<string>();
  const results: DishImageResult[] = [];

  for (const item of rawResults) {
    if (isLikelyNonFoodResult(item)) continue;

    // The app renders thumbUrl first. Requiring a trusted Google/SerpAPI CDN
    // URL avoids handing AsyncImage a loopback/LAN or arbitrary HTTP target.
    const thumbUrl = normalizeTrustedThumbnailUrl(item.thumbnail);
    if (!thumbUrl) continue;

    const fullUrl = isHttpUrl(item.original) ? item.original : thumbUrl;

    if (seen.has(fullUrl)) continue;
    seen.add(fullUrl);

    const pageUrl = isHttpUrl(item.link) ? item.link : fullUrl;
    const title = cleanString(item.title) ?? cleanString(item.source) ?? q;

    results.push({
      title,
      pageUrl,
      fullUrl,
      thumbUrl,
      width: typeof item.original_width === "number"
        ? item.original_width
        : undefined,
      height: typeof item.original_height === "number"
        ? item.original_height
        : undefined,
      source: cleanString(item.source),
      position: typeof item.position === "number" ? item.position : undefined,
    });

    if (results.length >= limit) break;
  }

  return results;
}

type SkippedVisualReview = {
  status: "skipped";
  reason: "deep_search";
  reviewedImages: 0;
};

function skippedVisualReview(): SkippedVisualReview {
  return { status: "skipped", reason: "deep_search", reviewedImages: 0 };
}

function serializeVisualReview(
  review: DishImageVisualReview | SkippedVisualReview,
) {
  return {
    status: review.status,
    verdict: review.status === "completed" ? review.verdict : null,
    qualifier: review.status === "completed" ? review.qualifier || null : null,
    reviewed_images: review.reviewedImages,
    approved_images: review.status === "completed"
      ? review.approvedThumbnailUrls.length
      : 0,
    approved_indices: review.status === "completed"
      ? review.approvedIndices
      : [],
    ...(review.status === "completed" ? {} : { reason: review.reason }),
  };
}

serve(async (req) => {
  const origin = req.headers.get("origin");
  const cors = corsHeaders(origin);

  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: cors });
  }

  try {
    if (req.method !== "GET") {
      return json(
        { error: "Method not allowed. Use GET." },
        405,
        cors,
      );
    }

    const url = new URL(req.url);
    const originalName = cleanSearchTerm(
      url.searchParams.get("original_name"),
      MAX_ORIGINAL_NAME_LENGTH,
    ) ??
      cleanSearchTerm(
        url.searchParams.get("q"),
        MAX_ORIGINAL_NAME_LENGTH,
      );
    const category = cleanSearchTerm(
      url.searchParams.get("category"),
      MAX_CONTEXT_LENGTH,
    );
    const menuContext = cleanSearchTerm(
      url.searchParams.get("menu_context"),
      MAX_CONTEXT_LENGTH,
    );
    const deepSearch = url.searchParams.get("deep_search") === "true";
    const deepSearchTerm = sanitizeDishImageQualifier(
      cleanSearchTerm(
        url.searchParams.get("deep_search_term"),
        MAX_CONTEXT_LENGTH,
      ),
    );
    const limitRaw = Number(url.searchParams.get("limit") ?? "12");
    const hl = (url.searchParams.get("hl") ?? "zh-cn").trim() || "zh-cn";
    const gl = (url.searchParams.get("gl") ?? "cn").trim() || "cn";

    const limit = clamp(Number.isFinite(limitRaw) ? limitRaw : 12, 1, 25);

    if (!originalName) {
      return json(
        { error: "Missing query param `original_name`." },
        400,
        cors,
      );
    }

    if (deepSearch && !deepSearchTerm) {
      return json(
        { error: "Missing query param `deep_search_term`." },
        400,
        cors,
      );
    }

    const query = deepSearch
      ? buildDishImageDeepSearchQuery(originalName, deepSearchTerm ?? "")
      : buildDishImageProbeQuery(originalName);
    const rawCandidates = await fetchSerpApiImageCandidates(query, hl, gl);

    let visualReview: DishImageVisualReview | SkippedVisualReview;
    if (deepSearch) {
      // The client only echoes a qualifier produced by the probe review. A
      // deep search is terminal and must never make a second Gemini request.
      visualReview = skippedVisualReview();
    } else {
      visualReview = await reviewDishImageCandidates({
        originalName,
        category,
        menuContext,
        maxImages: limit,
        // Keep candidates untouched here. Medical metadata filtering is only
        // for the client-facing results after Gemini has seen the thumbnails.
        candidates: rawCandidates,
      }).catch((error): DishImageVisualReview => {
        console.warn(
          "Dish image visual review failed safely:",
          error instanceof Error ? error.message : String(error),
        );
        return {
          status: "unavailable",
          reason: "request_failed",
          reviewedImages: 0,
          reviewedThumbnailUrls: [],
        };
      });
    }

    const probeOutcome = deepSearch
      ? {
        needsDeepSearch: false,
        deepSearchTerm: undefined,
        minimumApprovedImages: 0,
      }
      : deriveDishImageProbeOutcome(
        visualReview.status === "completed"
          ? {
            status: "completed",
            reviewedImages: visualReview.reviewedImages,
            approvedImages: visualReview.approvedThumbnailUrls.length,
            qualifier: visualReview.qualifier,
          }
          : {
            status: "unavailable",
            reviewedImages: visualReview.reviewedImages,
          },
        originalName,
        category,
        menuContext,
      );
    const generatedDeepSearchTerm = probeOutcome.deepSearchTerm;
    const needsDeepSearch = !deepSearch && probeOutcome.needsDeepSearch;
    const reviewedCandidates = visualReview.status === "completed" &&
        !needsDeepSearch
      ? filterCandidatesToApprovedThumbnails(
        rawCandidates,
        visualReview.approvedThumbnailUrls,
      )
      : undefined;
    const results = deepSearch
      ? mapClientResults(rawCandidates, query, limit)
      : visualReview.status !== "completed" || needsDeepSearch ||
          !reviewedCandidates
      ? []
      : mapClientResults(reviewedCandidates, query, limit);
    const ambiguitySource = deepSearch
      ? "deep_search"
      : visualReview.status === "completed"
      ? "visual_review"
      : "visual_review_unavailable";

    return json(
      {
        query,
        provider: "serpapi",
        engine: "google_images",
        ambiguity: {
          needs_context: needsDeepSearch,
          source: ambiguitySource,
        },
        needs_deep_search: needsDeepSearch,
        deep_search_term: generatedDeepSearchTerm ?? null,
        minimum_approved_images: probeOutcome.minimumApprovedImages,
        visual_review: serializeVisualReview(visualReview),
        count: results.length,
        results,
      },
      200,
      visualReview.status === "unavailable"
        ? { ...cors, "cache-control": "no-store" }
        : cors,
    );
  } catch (err) {
    return json(
      {
        error: "Internal error",
        message: err instanceof Error ? err.message : String(err),
      },
      500,
      cors,
    );
  }
});
