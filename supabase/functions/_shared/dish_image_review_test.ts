import {
  filterCandidatesToApprovedThumbnails,
  normalizeTrustedThumbnailUrl,
  parseGeminiImageReview,
  reviewDishImageCandidates,
  selectTrustedThumbnailUrls,
} from "./dish_image_review.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function geminiResponse(text: string, withThought = false): unknown {
  return {
    candidates: [{
      content: {
        parts: [
          ...(withThought ? [{ thought: true, text: "hidden reasoning" }] : []),
          { text },
        ],
      },
    }],
  };
}

function jpegResponse(
  bytes = new Uint8Array([0xff, 0xd8, 0xff, 0xdb]),
): Response {
  return new Response(bytes, {
    status: 200,
    headers: { "content-type": "image/jpeg" },
  });
}

Deno.test("accepts only HTTPS trusted thumbnail hosts without userinfo or custom ports", () => {
  assert(
    normalizeTrustedThumbnailUrl("https://encrypted-tbn0.gstatic.com/a.jpg") !==
      undefined,
    "Expected a Google thumbnail",
  );
  assert(
    normalizeTrustedThumbnailUrl("https://serpapi.com/a.jpg") !== undefined,
    "Expected a SerpAPI thumbnail",
  );
  assert(
    normalizeTrustedThumbnailUrl("https://lh3.googleusercontent.com/a.jpg") !==
      undefined,
    "Expected a Googleusercontent thumbnail",
  );

  for (
    const invalid of [
      "http://encrypted-tbn0.gstatic.com/a.jpg",
      "https://user:pass@serpapi.com/a.jpg",
      "https://serpapi.com:444/a.jpg",
      "https://serpapi.com.evil.example/a.jpg",
      "https://127.0.0.1/a.jpg",
    ]
  ) {
    assert(
      normalizeTrustedThumbnailUrl(invalid) === undefined,
      `Expected URL to be rejected: ${invalid}`,
    );
  }
});

Deno.test("selects at most six unique trusted thumbnails before metadata filtering", () => {
  const selected = selectTrustedThumbnailUrls([
    {
      thumbnail: "https://encrypted-tbn0.gstatic.com/medical.jpg",
      title: "甲沟炎病例",
    },
    { thumbnail: "https://serpapi.com/two.jpg" },
    { thumbnail: "https://lh3.googleusercontent.com/three.jpg" },
    { thumbnail: "https://encrypted-tbn1.gstatic.com/four.jpg" },
    { thumbnail: "https://encrypted-tbn2.gstatic.com/five.jpg" },
    { thumbnail: "https://encrypted-tbn3.gstatic.com/six.jpg" },
    { thumbnail: "https://encrypted-tbn4.gstatic.com/seven.jpg" },
    { thumbnail: "https://serpapi.com/two.jpg" },
  ]);

  assert(
    selected.length === 6,
    `Expected 6 thumbnails, got ${selected.length}`,
  );
  assert(
    selected[0].includes("medical.jpg"),
    "Metadata filtering must not run before visual review",
  );
});

Deno.test("publishes only thumbnails explicitly approved by Gemini", () => {
  const candidates = [
    { thumbnail: "https://encrypted-tbn0.gstatic.com/reviewed.jpg" },
    { thumbnail: "https://serpapi.com/not-reviewed.jpg" },
    { thumbnail: "https://untrusted.example/not-reviewed.jpg" },
  ];
  const filtered = filterCandidatesToApprovedThumbnails(candidates, [
    "https://encrypted-tbn0.gstatic.com/reviewed.jpg",
  ]);
  assert(filtered.length === 1, `Expected 1 candidate, got ${filtered.length}`);
  assert(
    filtered[0].thumbnail?.includes("reviewed.jpg"),
    "Expected only the reviewed candidate",
  );
});

Deno.test("parses fenced camelCase per-image decisions with extra fields and ignores thoughts", () => {
  const decision = parseGeminiImageReview(
    geminiResponse(
      '```json\n{"approvedIndices":[2,0,2,8],"qualifier":"鲜切牛肉","needsDeepSearch":true,"extra":"ignored"}\n```',
      true,
    ),
    4,
  );

  assert(decision !== undefined, "Expected a per-image decision");
  assert(
    JSON.stringify(decision.approvedIndices) === JSON.stringify([0, 2]),
    "Expected unique, bounded indices in image order",
  );
  assert(decision.qualifier === "鲜切牛肉", "Expected clean qualifier");
});

Deno.test("fails closed on legacy accept and supports legacy refine", () => {
  const accept = parseGeminiImageReview(
    geminiResponse('{"verdict":"accept","qualifier":"","extra":true}'),
    3,
  );
  const refine = parseGeminiImageReview(
    geminiResponse('{"verdict":"refine","qualifier":"鲜切牛肉"}'),
    3,
  );

  assert(
    accept === undefined,
    "Legacy accept must not publish unreviewed images",
  );
  assert(refine?.approvedIndices.length === 0, "Legacy refine approves none");
  assert(refine.qualifier === "鲜切牛肉", "Expected legacy qualifier");
});

Deno.test("rejects malformed Gemini review output", () => {
  const invalid = [
    '{"verdict":"maybe","qualifier":""}',
    '{"approved_indices":"0,1","qualifier":""}',
    '{"qualifier":"牛肉"}',
    "not json",
  ];
  for (const text of invalid) {
    assert(
      parseGeminiImageReview(geminiResponse(text), 3) === undefined,
      `Expected malformed response to be rejected: ${text}`,
    );
  }
});

Deno.test("removes search operators from a Gemini qualifier", () => {
  const refine = parseGeminiImageReview(
    geminiResponse(
      '{"approved_indices":[],"qualifier":"site:evil.example 鲜切牛肉 -甲沟炎"}',
    ),
    3,
  );
  assert(refine?.approvedIndices.length === 0, "Expected no approved images");
  assert(refine.qualifier === "鲜切牛肉", "Expected a plain-text qualifier");
});

Deno.test("downloads trusted thumbnails in parallel and sends one raw REST Gemini request", async () => {
  const thumbnailUrls = [
    "https://encrypted-tbn0.gstatic.com/one.jpg",
    "https://serpapi.com/two.jpg",
    "https://lh3.googleusercontent.com/three.jpg",
    "https://encrypted-tbn1.gstatic.com/four.jpg",
    "https://encrypted-tbn2.gstatic.com/five.jpg",
    "https://encrypted-tbn3.gstatic.com/six.jpg",
    "https://encrypted-tbn4.gstatic.com/seven.jpg",
  ];
  let geminiCalls = 0;
  const downloaded: string[] = [];
  let requestBody: Record<string, unknown> | undefined;

  const fetchImpl: typeof fetch = (input, init) => {
    const url = String(input);
    if (url.includes(":generateContent")) {
      geminiCalls += 1;
      requestBody = JSON.parse(String(init?.body)) as Record<string, unknown>;
      return Promise.resolve(
        new Response(
          JSON.stringify(
            geminiResponse(
              '{"approved_indices":[0,2,4],"qualifier":""}',
            ),
          ),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }

    assert(init?.redirect === "error", "Thumbnail redirects must be rejected");
    downloaded.push(url);
    return Promise.resolve(jpegResponse());
  };

  const result = await reviewDishImageCandidates(
    {
      originalName: "脚趾肉",
      category: "鲜切牛肉",
      menuContext: "潮汕牛肉火锅",
      candidates: thumbnailUrls.map((thumbnail) => ({ thumbnail })),
    },
    {
      fetchImpl,
      apiKey: "test-key",
      baseUrl: "https://gemini.example",
      model: "gemini-3.6-flash",
    },
  );

  assert(result.status === "completed", "Expected a completed review");
  assert(result.verdict === "accept", "Three of six images should be enough");
  assert(result.qualifier === "", "No qualifier was requested");
  assert(result.reviewedImages === 6, "Expected six reviewed images");
  assert(
    JSON.stringify(result.approvedIndices) === JSON.stringify([0, 2, 4]),
    "Expected the Gemini-approved indices",
  );
  assert(
    JSON.stringify(result.approvedThumbnailUrls) ===
      JSON.stringify([thumbnailUrls[0], thumbnailUrls[2], thumbnailUrls[4]]),
    "Only approved thumbnails may be published",
  );
  assert(
    downloaded.length === 6,
    "Only the top six thumbnails may be downloaded",
  );
  assert(geminiCalls === 1, "Gemini must be called exactly once");

  const contents = requestBody?.contents as Array<
    { parts: Array<Record<string, unknown>> }
  >;
  const imageParts = contents[0].parts.filter((part) => "inline_data" in part);
  assert(imageParts.length === 6, "Expected six inline image parts");
  for (const part of imageParts) {
    assert("inline_data" in part, "Expected raw REST inline_data");
    assert(!("inlineData" in part), "Must not use SDK-style inlineData");
    const inline = part.inline_data as Record<string, unknown>;
    assert(inline.mime_type === "image/jpeg", "Expected raw REST mime_type");
    assert(typeof inline.data === "string", "Expected base64 image data");
    assert(
      !inline.data.includes(","),
      "Base64 must not contain a data URL prefix",
    );
  }
  const labels = contents[0].parts.flatMap((part) =>
    typeof part.text === "string" && part.text.startsWith("Thumbnail index ")
      ? [part.text]
      : []
  );
  assert(labels.length === 6, "Expected one explicit label per image");
  assert(labels[0].includes("index 0"), "Expected zero-based image labels");
});

Deno.test("rejects an oversized streaming thumbnail without calling Gemini", async () => {
  let geminiCalls = 0;
  const oversized = new Uint8Array(384 * 1024 + 1);
  oversized.set([0xff, 0xd8, 0xff], 0);

  const fetchImpl: typeof fetch = (input) => {
    if (String(input).includes(":generateContent")) {
      geminiCalls += 1;
      return Promise.resolve(new Response("{}", { status: 200 }));
    }
    return Promise.resolve(jpegResponse(oversized));
  };

  const result = await reviewDishImageCandidates(
    {
      originalName: "脚趾肉",
      candidates: [{
        thumbnail: "https://encrypted-tbn0.gstatic.com/oversized.jpg",
      }],
    },
    {
      fetchImpl,
      apiKey: "test-key",
      baseUrl: "https://gemini.example",
      model: "gemini-3.6-flash",
    },
  );

  assert(result.status === "unavailable", "Expected graceful unavailability");
  assert(
    result.status === "unavailable" &&
      result.reason === "image_download_failed",
    "Expected the oversized image to be rejected",
  );
  assert(geminiCalls === 0, "Gemini must not receive an oversized image");
});

Deno.test("Gemini failures return unavailable without retries", async () => {
  let geminiCalls = 0;
  const fetchImpl: typeof fetch = (input) => {
    if (String(input).includes(":generateContent")) {
      geminiCalls += 1;
      return Promise.resolve(new Response("upstream error", { status: 503 }));
    }
    return Promise.resolve(jpegResponse());
  };

  const result = await reviewDishImageCandidates(
    {
      originalName: "脚趾肉",
      candidates: [{ thumbnail: "https://serpapi.com/one.jpg" }],
    },
    {
      fetchImpl,
      apiKey: "test-key",
      baseUrl: "https://gemini.example",
      model: "gemini-3.6-flash",
    },
  );

  assert(result.status === "unavailable", "Failure must degrade gracefully");
  assert(geminiCalls === 1, "Gemini requests must not be retried");
});

Deno.test("clears a qualifier that only repeats the original name", async () => {
  const fetchImpl: typeof fetch = (input) => {
    if (String(input).includes(":generateContent")) {
      return Promise.resolve(
        new Response(
          JSON.stringify(
            geminiResponse(
              '{"approved_indices":[],"qualifier":"脚趾肉"}',
            ),
          ),
          { status: 200, headers: { "content-type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(jpegResponse());
  };

  const result = await reviewDishImageCandidates(
    {
      originalName: "脚趾肉",
      candidates: [{ thumbnail: "https://serpapi.com/one.jpg" }],
    },
    {
      fetchImpl,
      apiKey: "test-key",
      baseUrl: "https://gemini.example",
      model: "gemini-3.6-flash",
    },
  );

  assert(result.status === "completed", "The per-image review remains useful");
  assert(result.qualifier === "", "The repeated qualifier must be cleared");
  assert(result.approvedThumbnailUrls.length === 0, "Expected no approvals");
});
