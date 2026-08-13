export type DishImageSearchUnavailableReason = "timeout" | "request_failed";

/** Backward-compatible, fail-closed response for an unavailable image search. */
export function dishImageSearchUnavailablePayload(
  query: string,
  reason: DishImageSearchUnavailableReason,
) {
  return {
    query,
    provider: "serpapi",
    engine: "google_images",
    search: {
      status: "unavailable",
      reason,
    },
    ambiguity: {
      needs_context: false,
      source: "search_unavailable",
    },
    needs_deep_search: false,
    deep_search_term: null,
    minimum_approved_images: 0,
    visual_review: {
      status: "skipped",
      verdict: null,
      qualifier: null,
      reviewed_images: 0,
      approved_images: 0,
      approved_indices: [],
      reason: "search_unavailable",
    },
    count: 0,
    results: [],
  };
}
