import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// Same Gemini routing strategy as the other functions.
const GEMINI_BASE_URL =
  Deno.env.get("GOOGLE_GEMINI_BASE_URL") ?? "https://api.cubence.com";
const GEMINI_FALLBACK_BASE_URLS = parseList(
  Deno.env.get("GOOGLE_GEMINI_FALLBACK_BASE_URLS") ??
    "https://api-dmit.cubence.com,https://api-bwg.cubence.com,https://api-cf.cubence.com",
);
// Advice is short + latency-sensitive, so default to the fast model first.
const GEMINI_MODEL = Deno.env.get("GEMINI_ADVICE_MODEL") ??
  Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
const GEMINI_FALLBACK_MODELS = parseList(
  Deno.env.get("GEMINI_ADVICE_FALLBACK_MODELS") ?? "gemini-3-flash-preview",
);

type Advice = {
  verdict: "ok" | "caution" | "avoid";
  summary: string;
  notes: string[];
};

console.log("dish_advice_api started: per-dish preference check");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  try {
    if (req.method !== "POST") {
      return respond(req, 405, { error: "Method not allowed" });
    }

    const body = await readJson(req);
    const dish = typeof body?.dish === "string" ? body.dish.trim() : "";
    const description = typeof body?.description === "string" ? body.description.trim() : "";
    const allergies = stringList(body?.allergies);
    const diets = stringList(body?.diets ?? body?.dietary_preferences);
    const preferenceNote = typeof body?.preference_note === "string"
      ? body.preference_note.trim()
      : "";
    const target = typeof body?.target === "string" && body.target.trim()
      ? body.target.trim()
      : "English";

    if (!dish) {
      return respond(req, 400, { error: "dish is required" });
    }

    // Nothing to check against: respond ok without spending a model call.
    if (allergies.length === 0 && diets.length === 0 && !preferenceNote) {
      return respond(req, 200, { verdict: "ok", summary: "", notes: [] });
    }

    const advice = await generateAdvice({
      dish,
      description,
      allergies,
      diets,
      preferenceNote,
      target,
    });

    return respond(req, 200, advice);
  } catch (err) {
    console.error("dish_advice_api error:", err);
    return respond(req, 500, {
      error: err instanceof Error ? err.message : String(err),
    });
  }
});

async function generateAdvice(input: {
  dish: string;
  description: string;
  allergies: string[];
  diets: string[];
  preferenceNote: string;
  target: string;
}): Promise<Advice> {
  const apiKey = getRequiredEnv("GEMINI_API_KEY");
  const prompt = buildPrompt(input);

  const data = await callGemini(apiKey, {
    contents: [{ role: "user", parts: [{ text: prompt }] }],
    generationConfig: { temperature: 0.2, maxOutputTokens: 512 },
  });

  const text = extractCandidateText(data?.candidates?.[0]);
  return parseAdvice(text);
}

function buildPrompt(input: {
  dish: string;
  description: string;
  allergies: string[];
  diets: string[];
  preferenceNote: string;
  target: string;
}): string {
  return [
    "You are a careful dining assistant. Decide whether a specific dish is a good fit for ONE user, based on their restrictions and tastes.",
    "",
    `Dish: ${input.dish}`,
    input.description ? `Dish description: ${input.description}` : "",
    `User allergies: ${input.allergies.length ? input.allergies.join(", ") : "none"}`,
    `User dietary restrictions: ${input.diets.length ? input.diets.join(", ") : "none"}`,
    `User free-form preferences: ${input.preferenceNote || "none"}`,
    "",
    "Decide a verdict:",
    "- \"avoid\": the dish clearly conflicts with an allergy or a hard dietary restriction (e.g. contains the allergen, or is meat for a vegetarian).",
    "- \"caution\": it MIGHT conflict depending on preparation/ingredients, or it goes against a stated taste preference (too spicy, contains cilantro they dislike, etc.).",
    "- \"ok\": no concerns worth flagging.",
    "",
    "Write 0-3 short, specific notes telling the user what to watch out for, each one short sentence.",
    "If a concern is about a likely-but-unconfirmed ingredient, say to confirm with the restaurant.",
    `All human-readable text (summary, notes) MUST be written in ${input.target}.`,
    "",
    "Return ONLY one valid JSON object, no markdown, no code fences:",
    '{"verdict":"ok|caution|avoid","summary":"one short sentence","notes":["...","..."]}',
    "If verdict is ok, notes may be empty and summary should be a brief reassurance.",
  ].filter(Boolean).join("\n");
}

function parseAdvice(text: string): Advice {
  const cleaned = cleanupGeneratedText(text);
  const candidates = [cleaned, extractLastJSONObjectText(cleaned) ?? ""];

  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const parsed = JSON.parse(candidate);
      const verdict = parsed?.verdict === "avoid" || parsed?.verdict === "caution"
        ? parsed.verdict
        : "ok";
      const notes = Array.isArray(parsed?.notes)
        ? parsed.notes
          .filter((n: unknown): n is string => typeof n === "string" && n.trim().length > 0)
          .map((n: string) => n.trim())
          .slice(0, 4)
        : [];
      return {
        verdict,
        summary: typeof parsed?.summary === "string" ? parsed.summary.trim() : "",
        notes,
      };
    } catch {
      // try next candidate
    }
  }

  return { verdict: "ok", summary: "", notes: [] };
}

// --- shared helpers (Gemini transport) ---

async function callGemini(apiKey: string, payload: unknown): Promise<any> {
  const baseUrls = uniqueList(
    [GEMINI_BASE_URL, ...GEMINI_FALLBACK_BASE_URLS].map((u) => u.replace(/\/+$/, "")),
  );
  const models = uniqueList([GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS]);
  const failures: string[] = [];

  for (const model of models) {
    for (const baseUrl of baseUrls) {
      const endpoint =
        `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:generateContent?alt=sse`;
      try {
        const res = await fetchWithTimeout(endpoint, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "User-Agent": "ProjectMayaIOS-Supabase-Edge/1.0",
            "x-goog-api-key": apiKey,
          },
          body: JSON.stringify(payload),
        }, 20000);

        if (res.ok) return await parseGeminiResponse(res);

        const errorBody = await res.text();
        failures.push(`${model} @ ${baseUrl}: HTTP ${res.status} ${errorBody.slice(0, 200)}`);
        if (!shouldTryNextGeminiEndpoint(res.status, errorBody)) break;
      } catch (err) {
        failures.push(`${model} @ ${baseUrl}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  }

  throw new Error(`Gemini API failed. ${failures.join(" | ")}`);
}

async function parseGeminiResponse(res: Response): Promise<any> {
  const contentType = res.headers.get("content-type") ?? "";
  const text = await res.text();
  if (!contentType.includes("text/event-stream")) return JSON.parse(text);

  const chunks: any[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) continue;
    const payload = trimmed.slice("data:".length).trim();
    if (!payload || payload === "[DONE]") continue;
    try {
      chunks.push(JSON.parse(payload));
    } catch {
      // skip
    }
  }
  if (chunks.length === 0) throw new Error("Gemini SSE response had no JSON chunks");

  const merged: any = { candidates: [{ content: { parts: [{ text: "" }] } }] };
  let combined = "";
  for (const chunk of chunks) {
    if (chunk?.error) throw new Error(`Gemini SSE error: ${JSON.stringify(chunk.error)}`);
    const parts = chunk?.candidates?.[0]?.content?.parts ?? [];
    for (const part of parts) {
      if (part?.thought === true) continue;
      if (typeof part?.text === "string") combined += part.text;
    }
  }
  merged.candidates[0].content.parts[0].text = combined;
  return merged;
}

function extractCandidateText(candidate: any): string {
  const parts = candidate?.content?.parts;
  if (!Array.isArray(parts)) return "";
  return parts
    .map((p: any) => (p?.thought === true ? "" : typeof p?.text === "string" ? p.text : ""))
    .join("")
    .trim();
}

function cleanupGeneratedText(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function extractLastJSONObjectText(text: string): string | null {
  let last: string | null = null;
  for (let start = 0; start < text.length; start += 1) {
    if (text[start] !== "{") continue;
    let depth = 0, inString = false, escaping = false;
    for (let i = start; i < text.length; i += 1) {
      const c = text[i];
      if (escaping) { escaping = false; continue; }
      if (c === "\\") { escaping = true; continue; }
      if (c === '"') { inString = !inString; continue; }
      if (inString) continue;
      if (c === "{") depth += 1;
      else if (c === "}") { depth -= 1; if (depth === 0) { last = text.slice(start, i + 1); break; } }
    }
  }
  return last;
}

function shouldTryNextGeminiEndpoint(status: number, body: string): boolean {
  if (status === 429 || status >= 500) return true;
  return (status === 400 && body.includes("not supported")) ||
    (status === 403 && body.includes("1010"));
}

function respond(req: Request, status: number, obj: unknown) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", ...corsHeaders(req) },
  });
}

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get("origin") ?? "*";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, accept",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

async function readJson(req: Request): Promise<any> {
  try {
    return await req.json();
  } catch {
    throw new Error("Invalid JSON request body");
  }
}

async function fetchWithTimeout(
  input: RequestInfo | URL,
  init: RequestInit = {},
  timeoutMs = 20000,
): Promise<Response> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort("Request timeout"), timeoutMs);
  try {
    return await fetch(input, { ...init, signal: controller.signal });
  } finally {
    clearTimeout(timer);
  }
}

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value) return value;
  throw new Error(`Missing required env var: ${name}`);
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseList(value: string): string[] {
  return value.split(",").map((s) => s.trim()).filter(Boolean);
}

function uniqueList(values: string[]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const v of values) {
    if (!v || seen.has(v)) continue;
    seen.add(v);
    out.push(v);
  }
  return out;
}
