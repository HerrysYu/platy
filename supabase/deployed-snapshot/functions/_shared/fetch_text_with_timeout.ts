type FetchLike = typeof fetch;

export class UpstreamTimeoutError extends Error {
  readonly code = "UPSTREAM_TIMEOUT";

  constructor(message = "Upstream request timed out") {
    super(message);
    this.name = "UpstreamTimeoutError";
  }
}

/**
 * Applies one timeout to both receiving the response and consuming its body.
 * The explicit flag distinguishes our timer from an unrelated AbortError.
 */
export async function fetchTextWithTimeout(
  input: RequestInfo | URL,
  init: RequestInit,
  timeoutMs: number,
  fetchImpl: FetchLike = fetch,
): Promise<{ response: Response; body: string }> {
  const controller = new AbortController();
  let didTimeout = false;
  const boundedTimeoutMs = Number.isFinite(timeoutMs)
    ? Math.max(1, Math.floor(timeoutMs))
    : 1;
  const timer = setTimeout(() => {
    didTimeout = true;
    controller.abort();
  }, boundedTimeoutMs);

  try {
    const response = await fetchImpl(input, {
      ...init,
      signal: controller.signal,
    });
    const body = await response.text();
    return { response, body };
  } catch (error) {
    if (didTimeout) throw new UpstreamTimeoutError();
    throw error;
  } finally {
    clearTimeout(timer);
  }
}
