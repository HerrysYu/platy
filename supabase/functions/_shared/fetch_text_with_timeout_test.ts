import {
  fetchTextWithTimeout,
  UpstreamTimeoutError,
} from "./fetch_text_with_timeout.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function rejectWhenAborted(
  signal: AbortSignal | null | undefined,
): Promise<never> {
  return new Promise((_, reject) => {
    if (!signal) return;
    if (signal.aborted) {
      reject(signal.reason);
      return;
    }
    signal.addEventListener("abort", () => reject(signal.reason), {
      once: true,
    });
  });
}

Deno.test("marks only its own request timer as an upstream timeout", async () => {
  const fetchImpl: typeof fetch = (_input, init) =>
    rejectWhenAborted(init?.signal);

  let thrown: unknown;
  try {
    await fetchTextWithTimeout("https://example.com", {}, 10, fetchImpl);
  } catch (error) {
    thrown = error;
  }

  assert(thrown instanceof UpstreamTimeoutError, "Expected timeout wrapper");
  assert(thrown.code === "UPSTREAM_TIMEOUT", "Expected stable timeout code");
});

Deno.test("keeps an upstream AbortError distinct from its own timeout", async () => {
  const upstreamAbort = new DOMException("upstream cancelled", "AbortError");
  const fetchImpl: typeof fetch = () => Promise.reject(upstreamAbort);

  let thrown: unknown;
  try {
    await fetchTextWithTimeout("https://example.com", {}, 100, fetchImpl);
  } catch (error) {
    thrown = error;
  }

  assert(thrown === upstreamAbort, "Expected the original upstream error");
});

Deno.test("timeout also covers a stalled response body", async () => {
  const fetchImpl: typeof fetch = (_input, init) => {
    const signal = init?.signal;
    const body = new ReadableStream<Uint8Array>({
      start(controller) {
        signal?.addEventListener(
          "abort",
          () => controller.error(signal.reason),
          { once: true },
        );
      },
    });
    return Promise.resolve(new Response(body, { status: 200 }));
  };

  let thrown: unknown;
  try {
    await fetchTextWithTimeout("https://example.com", {}, 10, fetchImpl);
  } catch (error) {
    thrown = error;
  }

  assert(
    thrown instanceof UpstreamTimeoutError,
    "Expected the stalled body to time out",
  );
});

Deno.test("successful requests are performed once and return their body", async () => {
  let calls = 0;
  const fetchImpl: typeof fetch = () => {
    calls += 1;
    return Promise.resolve(new Response("ok", { status: 200 }));
  };

  const result = await fetchTextWithTimeout(
    "https://example.com",
    {},
    100,
    fetchImpl,
  );

  assert(calls === 1, "The upstream request must not be retried");
  assert(result.response.status === 200, "Expected the upstream response");
  assert(result.body === "ok", "Expected the consumed response body");
});
