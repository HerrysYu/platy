import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

// Gemini routing mirrors dish_detail_api_gemini: proxy base url + fallbacks.
const GEMINI_BASE_URL =
  Deno.env.get("GOOGLE_GEMINI_BASE_URL") ?? "https://api.cubence.com";
const GEMINI_FALLBACK_BASE_URLS = parseList(
  Deno.env.get("GOOGLE_GEMINI_FALLBACK_BASE_URLS") ??
    "https://api-dmit.cubence.com,https://api-bwg.cubence.com,https://api-cf.cubence.com",
);
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3-flash-preview";
const GEMINI_FALLBACK_MODELS = parseList(
  Deno.env.get("GEMINI_FALLBACK_MODELS") ?? "gemini-2.5-flash",
);
const MAX_MENU_ITEMS = 160;

type MenuItem = {
  name: string;
  translated?: string;
};

type Preferences = {
  allergies: string[];
  diets: string[];
  country: string;
  preferenceNote: string;
  language: string;
};

type ComboItem = {
  name: string;
  original_name: string;
  role: string;
  reason: string;
};

type ComboRecommendation = {
  theme: string;
  summary: string;
  items: ComboItem[];
  tips: string | null;
};

type StreamSender = (event: string, data: unknown) => void;

console.log("combo_recommend_api started: Gemini agent combo recommendation");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  try {
    if (req.method !== "POST") {
      return respond(req, 405, { error: "Method not allowed" });
    }

    const body = await readJson(req);
    const menuItems = parseMenuItems(body?.menu_items);
    const preferences = parsePreferences(body?.preferences);
    const target =
      typeof body?.target === "string" && body.target.trim()
        ? body.target.trim()
        : "English";
    const stream = body?.stream === true;

    if (menuItems.length === 0) {
      return respond(req, 400, { error: "menu_items is required" });
    }

    if (stream) {
      return streamComboRecommendation(req, menuItems, preferences, target);
    }

    const combo = await runComboAgent(menuItems, preferences, target, () => {});
    return respond(req, 200, combo);
  } catch (err) {
    console.error("combo_recommend_api error:", err);
    return respond(req, 500, {
      error: err instanceof Error ? err.message : String(err),
    });
  }
});

function streamComboRecommendation(
  req: Request,
  menuItems: MenuItem[],
  preferences: Preferences,
  target: string,
): Response {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send: StreamSender = (event, data) => {
        controller.enqueue(
          encoder.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`),
        );
      };

      // Heartbeat keeps the connection alive while the agent thinks.
      const heartbeat = setInterval(() => {
        try {
          controller.enqueue(encoder.encode(": keep-alive\n\n"));
        } catch {
          clearInterval(heartbeat);
        }
      }, 10000);

      try {
        const combo = await runComboAgent(menuItems, preferences, target, send);
        send("combo_done", combo);
      } catch (err) {
        console.error("combo_recommend_api stream error:", err);
        send("combo_error", {
          message: err instanceof Error ? err.message : String(err),
        });
      } finally {
        clearInterval(heartbeat);
        controller.close();
      }
    },
  });

  return new Response(stream, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache, no-transform",
      "Connection": "keep-alive",
      "X-Accel-Buffering": "no",
      ...corsHeaders(req),
    },
  });
}

// ---------------------------------------------------------------------------
// Agent loop: Gemini with function calling. Tools read the menu, read the
// user preferences, and search the web (implemented via a nested Gemini call
// with google_search grounding, since functionDeclarations and google_search
// cannot be combined in one request).
// ---------------------------------------------------------------------------

// Single-shot recommendation: the menu and preferences are small enough to
// inline into one prompt, so we skip the multi-round tool-calling agent (which
// cost 4-6 sequential model calls) and do ONE generateContent, with at most one
// retry if the model picks an item that isn't on the scanned menu.
async function runComboAgent(
  menuItems: MenuItem[],
  preferences: Preferences,
  target: string,
  send: StreamSender,
): Promise<ComboRecommendation> {
  const apiKey = getRequiredEnv("GEMINI_API_KEY");

  send("combo_status", { stage: "reading_menu", message: statusText("reading_menu", target) });

  const contents: any[] = [
    { role: "user", parts: [{ text: buildComboPrompt(menuItems, preferences, target) }] },
  ];

  send("combo_status", { stage: "thinking", message: statusText("thinking", target) });

  for (let attempt = 0; attempt < 2; attempt += 1) {
    const data = await callGemini(apiKey, {
      contents,
      generationConfig: { temperature: 0.6, maxOutputTokens: 1536 },
    });
    const text = extractCandidateText(data?.candidates?.[0]);
    const combo = parseComboRecommendation(text);

    if (combo) {
      const { combo: verified, rejected } = enforceMenuMatch(combo, menuItems);
      if (verified) {
        send("combo_status", { stage: "done", message: statusText("done", target) });
        return verified;
      }

      // One corrective retry, otherwise fall back to keeping valid items only.
      if (attempt === 0) {
        contents.push({ role: "model", parts: [{ text }] });
        contents.push({
          role: "user",
          parts: [{
            text:
              `These items are NOT on the menu: ${rejected.join(", ")}. ` +
              "Use ONLY items from the menu list and copy original_name exactly. Output the JSON object only.",
          }],
        });
        continue;
      }

      const salvaged = filterToMenuItems(combo, menuItems);
      if (salvaged) {
        send("combo_status", { stage: "done", message: statusText("done", target) });
        return salvaged;
      }
    }

    if (attempt === 0) {
      contents.push({ role: "model", parts: [{ text }] });
      contents.push({
        role: "user",
        parts: [{ text: "Output ONLY the final recommendation as one valid JSON object in the schema given. No markdown." }],
      });
    }
  }

  throw new Error("Failed to produce a valid combo recommendation");
}

function menuListText(menuItems: MenuItem[]): string {
  return menuItems
    .slice(0, MAX_MENU_ITEMS)
    .map((item) =>
      item.translated && item.translated !== item.name
        ? `- ${item.name} (${item.translated})`
        : `- ${item.name}`
    )
    .join("\n");
}

function buildComboPrompt(
  menuItems: MenuItem[],
  preferences: Preferences,
  target: string,
): string {
  const prefLines = [
    `Allergies: ${preferences.allergies.length ? preferences.allergies.join(", ") : "none"}`,
    `Dietary restrictions: ${preferences.diets.length ? preferences.diets.join(", ") : "none"}`,
    preferences.country ? `Background: ${preferences.country}` : "",
    preferences.preferenceNote ? `Stated tastes: ${preferences.preferenceNote}` : "",
  ].filter(Boolean).join("\n");

  return [
    "You are a friendly restaurant ordering assistant.",
    "Recommend ONE great combo (2-4 items that go well together) from the scanned menu for this user.",
    "",
    "Scanned menu items (use these EXACT names for original_name):",
    menuListText(menuItems),
    "",
    "User profile:",
    prefLines,
    "",
    "Hard rules:",
    "1. Only recommend items from the menu list above; copy original_name exactly.",
    "2. NEVER include anything that conflicts with the user's allergies or dietary restrictions.",
    "3. Respect the user's stated tastes when possible.",
    "4. Keep the combo coherent (a drink+dessert combo is fine for a drink shop).",
    "5. AT MOST ONE staple/carb item. Noodles, rice, fried rice, porridge/congee, dumplings, buns, bread, pancakes ALL count as staples — never pair two. If the main dish is itself carb-based, it fills the staple slot; pair it with a non-staple side, drink, or dessert.",
    "",
    `Output ONLY one valid JSON object (no markdown, no code fences), with all human-readable text in ${target}:`,
    '{"theme":"short catchy name","summary":"1-2 sentences on why it fits this user","items":[{"name":"display name","original_name":"exact name from the menu list","role":"main|staple|side|drink|dessert","reason":"one short sentence"}],"tips":"optional one-line tip or null"}',
  ].join("\n");
}

// ---------------------------------------------------------------------------
// Menu-match enforcement: combo items must exist in this session's scans.
// ---------------------------------------------------------------------------

function normalizeForMatch(value: string): string {
  return value
    .toLowerCase()
    .replace(/[\s\p{P}\p{S}\d]+/gu, "");
}

/// Find the scanned menu item backing a recommended item, tolerating OCR
/// noise (prices, punctuation) via normalized exact/containment matching.
function matchMenuItem(candidate: ComboItem, menuItems: MenuItem[]): MenuItem | null {
  const keys = uniqueList(
    [candidate.original_name, candidate.name].map(normalizeForMatch),
  ).filter((key) => key.length >= 2);
  if (keys.length === 0) return null;

  let best: MenuItem | null = null;
  let bestScore = Infinity;

  for (const item of menuItems) {
    const names = [item.name, item.translated ?? ""]
      .map(normalizeForMatch)
      .filter(Boolean);

    for (const menuKey of names) {
      for (const key of keys) {
        if (menuKey === key) return item;

        // OCR lines often bundle a price/description with the dish name.
        if (menuKey.includes(key) || key.includes(menuKey)) {
          const score = Math.abs(menuKey.length - key.length);
          if (score < bestScore) {
            bestScore = score;
            best = item;
          }
        }
      }
    }
  }

  return best;
}

/// Strict pass used inside the agent loop: reject the combo (with the bad
/// names) so the agent can re-pick when anything is off-menu.
function enforceMenuMatch(
  combo: ComboRecommendation,
  menuItems: MenuItem[],
): { combo: ComboRecommendation | null; rejected: string[] } {
  const rejected: string[] = [];
  const items: ComboItem[] = [];

  for (const item of combo.items) {
    const matched = matchMenuItem(item, menuItems);
    if (!matched) {
      rejected.push(item.original_name || item.name);
      continue;
    }
    items.push({ ...item, original_name: matched.name });
  }

  if (rejected.length > 0 || items.length === 0) {
    return { combo: null, rejected };
  }

  return { combo: { ...combo, items }, rejected: [] };
}

/// Lenient pass for the final fallback: silently drop off-menu items.
function filterToMenuItems(
  combo: ComboRecommendation,
  menuItems: MenuItem[],
): ComboRecommendation | null {
  const items: ComboItem[] = [];

  for (const item of combo.items) {
    const matched = matchMenuItem(item, menuItems);
    if (matched) {
      items.push({ ...item, original_name: matched.name });
    }
  }

  if (items.length === 0) return null;
  return { ...combo, items };
}


function statusText(stage: string, target: string, extra = ""): string {
  const zh = /中文|chinese|zh|cn/i.test(target);
  switch (stage) {
    case "start":
      return zh ? "正在唤醒 AI 美食顾问…" : "Waking up your AI food guide…";
    case "reading_menu":
      return zh ? "正在通读整份菜单…" : "Reading through the menu…";
    case "reading_preferences":
      return zh ? "正在结合你的口味偏好…" : "Checking your taste profile…";
    case "searching":
      return zh ? `正在联网了解「${extra}」…` : `Searching the web: ${extra}…`;
    case "thinking":
      return zh ? "正在搭配最合适的组合…" : "Pairing the perfect combo…";
    case "done":
      return zh ? "搭配完成!" : "Combo ready!";
    default:
      return zh ? "思考中…" : "Thinking…";
  }
}

// ---------------------------------------------------------------------------
// Parsing helpers
// ---------------------------------------------------------------------------

function parseMenuItems(value: unknown): MenuItem[] {
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  const items: MenuItem[] = [];

  for (const raw of value) {
    let name = "";
    let translated: string | undefined;

    if (typeof raw === "string") {
      name = raw.trim();
    } else if (raw && typeof raw === "object") {
      name = typeof (raw as any).name === "string" ? (raw as any).name.trim() : "";
      const t = (raw as any).translated;
      translated = typeof t === "string" && t.trim() ? t.trim() : undefined;
    }

    if (!name || seen.has(name)) continue;
    seen.add(name);
    items.push(translated ? { name, translated } : { name });
    if (items.length >= MAX_MENU_ITEMS) break;
  }

  return items;
}

function parsePreferences(value: unknown): Preferences {
  const obj = value && typeof value === "object" ? value as any : {};
  return {
    allergies: stringList(obj.allergies),
    diets: stringList(obj.diets ?? obj.dietary_preferences),
    country: typeof obj.country === "string" ? obj.country.trim() : "",
    preferenceNote: typeof obj.preference_note === "string"
      ? obj.preference_note.trim()
      : "",
    language: typeof obj.language === "string" ? obj.language.trim() : "",
  };
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string => typeof item === "string")
    .map((item) => item.trim())
    .filter(Boolean);
}

function parseComboRecommendation(text: string): ComboRecommendation | null {
  const cleaned = cleanupGeneratedText(text);
  const candidates = [cleaned, extractLastJSONObjectText(cleaned) ?? ""];

  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const parsed = JSON.parse(candidate);
      const items = Array.isArray(parsed?.items)
        ? parsed.items
          .map((item: any): ComboItem | null => {
            const name = typeof item?.name === "string" ? item.name.trim() : "";
            if (!name) return null;
            return {
              name,
              original_name:
                typeof item?.original_name === "string" && item.original_name.trim()
                  ? item.original_name.trim()
                  : name,
              role: typeof item?.role === "string" ? item.role.trim() : "main",
              reason: typeof item?.reason === "string" ? item.reason.trim() : "",
            };
          })
          .filter((item: ComboItem | null): item is ComboItem => item !== null)
        : [];

      if (items.length === 0) continue;

      return {
        theme: typeof parsed?.theme === "string" && parsed.theme.trim()
          ? parsed.theme.trim()
          : "AI Combo",
        summary: typeof parsed?.summary === "string" ? parsed.summary.trim() : "",
        items,
        tips: typeof parsed?.tips === "string" && parsed.tips.trim()
          ? parsed.tips.trim()
          : null,
      };
    } catch {
      // Try the next candidate.
    }
  }

  return null;
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

    let depth = 0;
    let inString = false;
    let escaping = false;

    for (let index = start; index < text.length; index += 1) {
      const char = text[index];

      if (escaping) {
        escaping = false;
        continue;
      }
      if (char === "\\") {
        escaping = true;
        continue;
      }
      if (char === "\"") {
        inString = !inString;
        continue;
      }
      if (inString) continue;

      if (char === "{") {
        depth += 1;
      } else if (char === "}") {
        depth -= 1;
        if (depth === 0) {
          last = text.slice(start, index + 1);
          break;
        }
      }
    }
  }

  return last;
}

function extractCandidateText(candidate: any): string {
  const parts = candidate?.content?.parts;
  if (!Array.isArray(parts)) return "";

  return parts
    .map((part: any) =>
      part?.thought === true
        ? ""
        : typeof part?.text === "string"
        ? part.text
        : ""
    )
    .join("")
    .trim();
}

// ---------------------------------------------------------------------------
// Gemini transport (same routing/fallback strategy as dish_detail_api_gemini)
// ---------------------------------------------------------------------------

async function callGemini(apiKey: string, payload: unknown): Promise<any> {
  const baseUrls = uniqueList(
    [GEMINI_BASE_URL, ...GEMINI_FALLBACK_BASE_URLS].map((url) =>
      url.replace(/\/+$/, "")
    ),
  );
  const models = uniqueList([GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS]);
  const failures: string[] = [];

  for (const model of models) {
    for (const baseUrl of baseUrls) {
      const endpoint =
        `${baseUrl}/v1beta/models/${encodeURIComponent(model)}:generateContent?alt=sse`;

      try {
        const res = await fetchWithTimeout(
          endpoint,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "User-Agent": "ProjectMayaIOS-Supabase-Edge/1.0",
              "x-goog-api-key": apiKey,
            },
            body: JSON.stringify(payload),
          },
          45000,
        );

        if (res.ok) {
          return await parseGeminiResponse(res);
        }

        const body = await res.text();
        failures.push(
          `${model} @ ${baseUrl}: HTTP ${res.status} ${body.slice(0, 300)}`,
        );
        if (!shouldTryNextGeminiEndpoint(res.status, body)) {
          break;
        }
      } catch (err) {
        failures.push(
          `${model} @ ${baseUrl}: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
    }
  }

  throw new Error(`Gemini API failed. ${failures.join(" | ")}`);
}

async function parseGeminiResponse(res: Response): Promise<any> {
  const contentType = res.headers.get("content-type") ?? "";
  const text = await res.text();

  if (!contentType.includes("text/event-stream")) {
    return JSON.parse(text);
  }

  const chunks: any[] = [];
  for (const line of text.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (!trimmed.startsWith("data:")) continue;

    const payload = trimmed.slice("data:".length).trim();
    if (!payload || payload === "[DONE]") continue;

    try {
      chunks.push(JSON.parse(payload));
    } catch {
      console.warn("Skipping invalid Gemini SSE payload:", payload.slice(0, 120));
    }
  }

  if (chunks.length === 0) {
    throw new Error("Gemini SSE response did not contain JSON chunks");
  }

  const errorChunk = chunks.find((chunk) => chunk?.error);
  if (errorChunk?.error) {
    throw new Error(`Gemini SSE error: ${JSON.stringify(errorChunk.error)}`);
  }

  return mergeGeminiStreamChunks(chunks);
}

/// Merge SSE chunks, preserving text, functionCall parts, and grounding.
function mergeGeminiStreamChunks(chunks: any[]): any {
  const merged: any = { candidates: [] };

  for (const chunk of chunks) {
    const candidates = Array.isArray(chunk?.candidates) ? chunk.candidates : [];
    for (const candidate of candidates) {
      const index = typeof candidate?.index === "number" ? candidate.index : 0;
      const target = merged.candidates[index] ?? {
        index,
        content: { role: "model", parts: [] },
        _text: "",
      };

      const parts = Array.isArray(candidate?.content?.parts)
        ? candidate.content.parts
        : [];
      for (const part of parts) {
        if (part?.thought === true) continue;
        if (part?.functionCall) {
          target.content.parts.push({ functionCall: part.functionCall });
        } else if (typeof part?.text === "string") {
          target._text = appendStreamText(target._text, part.text);
        }
      }

      if (candidate?.groundingMetadata) {
        target.groundingMetadata = candidate.groundingMetadata;
      }
      if (candidate?.finishReason) {
        target.finishReason = candidate.finishReason;
      }

      merged.candidates[index] = target;
    }
  }

  merged.candidates = merged.candidates.filter(Boolean);
  for (const candidate of merged.candidates) {
    if (candidate._text) {
      candidate.content.parts.push({ text: candidate._text });
    }
    delete candidate._text;
  }

  return merged;
}

function appendStreamText(current: string, incoming: string): string {
  if (!incoming) return current;
  if (!current) return incoming;
  if (incoming.startsWith(current)) return incoming;
  if (current.startsWith(incoming) || current.endsWith(incoming)) return current;

  const maxOverlap = Math.min(current.length, incoming.length);
  for (let length = maxOverlap; length > 0; length -= 1) {
    if (current.endsWith(incoming.slice(0, length))) {
      return current + incoming.slice(length);
    }
  }

  return current + incoming;
}

function shouldTryNextGeminiEndpoint(status: number, body: string): boolean {
  if (status === 429 || status >= 500) return true;
  return (status === 400 && body.includes("not supported")) ||
    (status === 403 && body.includes("1010"));
}

// ---------------------------------------------------------------------------
// Generic helpers
// ---------------------------------------------------------------------------

function respond(req: Request, status: number, obj: unknown) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      ...corsHeaders(req),
    },
  });
}

function corsHeaders(req: Request): HeadersInit {
  const origin = req.headers.get("origin") ?? "*";
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type, accept",
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
    return await fetch(input, {
      ...init,
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timer);
  }
}

function getRequiredEnv(name: string): string {
  const value = Deno.env.get(name);
  if (value) return value;
  throw new Error(`Missing required env var: ${name}`);
}

function parseList(value: string): string[] {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function uniqueList(values: string[]): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];

  for (const value of values) {
    if (!value || seen.has(value)) continue;
    seen.add(value);
    unique.push(value);
  }

  return unique;
}
