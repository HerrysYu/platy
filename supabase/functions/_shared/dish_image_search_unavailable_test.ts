import { dishImageSearchUnavailablePayload } from "./dish_image_search_unavailable.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("unavailable search never publishes images or requests deep search", () => {
  for (const reason of ["timeout", "request_failed"] as const) {
    const payload = dishImageSearchUnavailablePayload("金针菇", reason);
    assert(payload.query === "金针菇", "Expected the attempted query");
    assert(payload.search.reason === reason, "Expected the failure reason");
    assert(!payload.needs_deep_search, "Failure must not trigger deep search");
    assert(payload.deep_search_term === null, "Failure has no deep term");
    assert(payload.count === 0, "Failure must not report images");
    assert(payload.results.length === 0, "Failure must not publish images");
    assert(
      payload.visual_review.reason === "search_unavailable",
      "Visual review must be marked skipped",
    );
  }
});
