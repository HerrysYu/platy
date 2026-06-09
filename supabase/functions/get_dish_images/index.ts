import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const SERPAPI_ENDPOINT = "https://serpapi.com/search.json";

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
  const timer = setTimeout(() => controller.abort("Request timeout"), timeoutMs);

  try {
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

async function serpApiImageSearch(
  q: string,
  limit: number,
  hl: string,
  gl: string,
): Promise<DishImageResult[]> {
  const params = new URLSearchParams({
    engine: "google_images",
    q,
    api_key: getRequiredEnv("SERPAPI_API_KEY"),
    hl,
    gl,
    safe: "active",
    ijn: "0",
  });

  const res = await fetchWithTimeout(`${SERPAPI_ENDPOINT}?${params.toString()}`);
  const body = await res.text();

  if (!res.ok) {
    throw new Error(`SerpApi image search failed: HTTP ${res.status} ${body.slice(0, 300)}`);
  }

  let data: any;
  try {
    data = JSON.parse(body);
  } catch {
    throw new Error(`SerpApi returned non-JSON response: ${body.slice(0, 300)}`);
  }

  if (typeof data?.error === "string" && data.error.trim()) {
    throw new Error(`SerpApi image search failed: ${data.error.trim()}`);
  }

  const rawResults = Array.isArray(data?.images_results)
    ? data.images_results as SerpApiImageResult[]
    : [];
  const seen = new Set<string>();
  const results: DishImageResult[] = [];

  for (const item of rawResults) {
    const fullUrl = isHttpUrl(item.original)
      ? item.original
      : isHttpUrl(item.thumbnail)
      ? item.thumbnail
      : undefined;

    if (!fullUrl || seen.has(fullUrl)) continue;
    seen.add(fullUrl);

    const thumbUrl = isHttpUrl(item.thumbnail) ? item.thumbnail : undefined;
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
    const qRaw = (url.searchParams.get("q") ?? "").trim();
    const limitRaw = Number(url.searchParams.get("limit") ?? "12");
    const hl = (url.searchParams.get("hl") ?? "zh-cn").trim() || "zh-cn";
    const gl = (url.searchParams.get("gl") ?? "cn").trim() || "cn";

    const q = qRaw.slice(0, 200);
    const limit = clamp(Number.isFinite(limitRaw) ? limitRaw : 12, 1, 25);

    if (!q) {
      return json(
        { error: "Missing query param `q`." },
        400,
        cors,
      );
    }

    const results = await serpApiImageSearch(q, limit, hl, gl);

    return json(
      {
        query: q,
        provider: "serpapi",
        engine: "google_images",
        count: results.length,
        results,
      },
      200,
      cors,
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
