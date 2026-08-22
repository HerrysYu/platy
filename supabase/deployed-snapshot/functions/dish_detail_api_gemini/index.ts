import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const GEMINI_BASE_URL =
  Deno.env.get("GOOGLE_GEMINI_BASE_URL") ?? "https://api.cubence.com";
const GEMINI_FALLBACK_BASE_URLS = parseBaseUrls(
  Deno.env.get("GOOGLE_GEMINI_FALLBACK_BASE_URLS") ??
    "https://api-dmit.cubence.com,https://api-bwg.cubence.com,https://api-cf.cubence.com",
);
const GEMINI_MODEL = Deno.env.get("GEMINI_MODEL") ?? "gemini-3-flash-preview";
const GEMINI_FALLBACK_MODELS = parseList(
  Deno.env.get("GEMINI_FALLBACK_MODELS") ?? "gemini-2.5-flash",
);

type DishAnswer = {
  title: string | null;
  description: string | null;
};

type GroundingSource = {
  title: string;
  uri: string;
};

type DishStreamResult = {
  answer: DishAnswer;
  sources: GroundingSource[];
  searchQueries: string[];
};

type StreamSender = (event: string, data: unknown) => void;

console.log("dish_detail_api_gemini started: Gemini Google Search grounding");

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(req) });
  }

  try {
    if (req.method !== "POST") {
      return respond(req, 405, empty());
    }

    const body = await readJson(req);
    const dish = typeof body?.dish === "string" ? body.dish.trim() : "";
    const target =
      typeof body?.target === "string" && body.target.trim()
        ? body.target.trim()
        : "English";
    const stream = body?.stream === true;

    if (!dish) {
      return respond(req, 400, empty());
    }

    if (stream) {
      return streamDishDetailWithSearch(req, dish, target);
    }

    const gemini = await generateDishDetailWithSearch(dish, target);

    return respond(req, 200, {
      title: gemini.answer.title ?? dish,
      description: gemini.answer.description ?? null,
      thumbil: [],
      source: gemini.sources.map((source) => source.uri),
      web_sources: gemini.sources,
      search_queries: gemini.searchQueries,
    });
  } catch (err) {
    console.error("dish_detail_api_gemini error:", err);
    return respond(req, 500, empty());
  }
});

function empty() {
  return {
    title: null,
    description: null,
    thumbil: [],
    source: [],
  };
}

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

async function generateDishDetailWithSearch(
  dish: string,
  target: string,
): Promise<DishStreamResult> {
  const apiKey = getRequiredEnv("GEMINI_API_KEY");
  const prompt = buildPrompt(dish, target);
  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: prompt }],
      },
    ],
    tools: [
      {
        google_search: {},
      },
    ],
    generationConfig: {
      temperature: 0.25,
      maxOutputTokens: 1600,
    },
  };

  const data = await callGemini(apiKey, payload);
  const candidate = data?.candidates?.[0];
  const text = extractCandidateText(candidate);
  const grounding = candidate?.groundingMetadata ?? {};

  return {
    answer: parseDishAnswer(text, dish),
    sources: extractGroundingSources(grounding),
    searchQueries: Array.isArray(grounding?.webSearchQueries)
      ? grounding.webSearchQueries.filter((item: unknown) =>
        typeof item === "string" && item.trim()
      )
      : [],
  };
}

function streamDishDetailWithSearch(
  req: Request,
  dish: string,
  target: string,
): Response {
  const encoder = new TextEncoder();

  const stream = new ReadableStream<Uint8Array>({
    async start(controller) {
      const send: StreamSender = (event, data) => {
        controller.enqueue(encoder.encode(sseMessage(event, data)));
      };

      try {
        const gemini = await generateStreamingDishDetailWithSearch(
          dish,
          target,
          send,
        );

        send("dish_detail_done", {
          title: gemini.answer.title ?? dish,
          description: gemini.answer.description ?? null,
          thumbil: [],
          source: gemini.sources.map((source) => source.uri),
          web_sources: gemini.sources,
          search_queries: gemini.searchQueries,
        });
      } catch (err) {
        console.error("dish_detail_api_gemini stream error:", err);
        send("dish_detail_error", {
          message: err instanceof Error ? err.message : String(err),
        });
      } finally {
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

async function generateStreamingDishDetailWithSearch(
  dish: string,
  target: string,
  send: StreamSender,
): Promise<DishStreamResult> {
  const apiKey = getRequiredEnv("GEMINI_API_KEY");
  const prompt = buildStreamingPrompt(dish, target);
  const payload = {
    contents: [
      {
        role: "user",
        parts: [{ text: prompt }],
      },
    ],
    tools: [
      {
        google_search: {},
      },
    ],
    generationConfig: {
      temperature: 0.25,
      maxOutputTokens: 1800,
    },
  };

  let generatedText = "";
  let latestDescription = "";
  send("dish_detail_title", { title: dish });

  const data = await callGeminiStream(apiKey, payload, async (chunk) => {
    const chunkText = extractVisibleTextFromGeminiChunk(chunk);
    if (!chunkText) return;

    const nextGeneratedText = appendStreamText(generatedText, chunkText);
    if (nextGeneratedText === generatedText) return;

    generatedText = nextGeneratedText;
    const description = sanitizeGeneratedDescription(generatedText) ?? "";
    if (!description || description === latestDescription) {
      return;
    }

    if (description.startsWith(latestDescription)) {
      const descriptionDelta = description.slice(latestDescription.length);
      latestDescription = description;
      send("dish_detail_delta", { delta: descriptionDelta });
      return;
    }

    latestDescription = description;
    send("dish_detail_snapshot", { description });
  });

  const candidate = data?.candidates?.[0];
  const text = sanitizeGeneratedDescription(extractCandidateText(candidate)) ||
    sanitizeGeneratedDescription(generatedText) ||
    generatedText.trim();
  const grounding = candidate?.groundingMetadata ?? {};
  let answer: DishAnswer = {
    title: dish,
    description: sanitizeGeneratedDescription(text),
  };

  if (isProbablyIncompleteDescription(answer.description)) {
    try {
      const fallback = await generateDishDetailWithSearch(dish, target);
      if (
        fallback.answer.description &&
        !isProbablyIncompleteDescription(fallback.answer.description)
      ) {
        answer = fallback.answer;
      }
    } catch (err) {
      console.warn(
        "Full non-streaming fallback failed:",
        err instanceof Error ? err.message : String(err),
      );
    }
  }

  answer = {
    title: answer.title ?? dish,
    description: completeDescription(answer.description, target),
  };

  if (answer.description && answer.description !== latestDescription) {
    if (answer.description.startsWith(latestDescription)) {
      send("dish_detail_delta", {
        delta: answer.description.slice(latestDescription.length),
      });
    } else {
      send("dish_detail_snapshot", { description: answer.description });
    }
  }

  return {
    answer,
    sources: extractGroundingSources(grounding),
    searchQueries: Array.isArray(grounding?.webSearchQueries)
      ? grounding.webSearchQueries.filter((item: unknown) =>
        typeof item === "string" && item.trim()
      )
      : [],
  };
}

async function callGemini(apiKey: string, payload: unknown): Promise<any> {
  const baseUrls = uniqueBaseUrls([GEMINI_BASE_URL, ...GEMINI_FALLBACK_BASE_URLS]);
  const models = uniqueList([GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS]);
  const failures: string[] = [];

  for (const model of models) {
    for (const baseUrl of baseUrls) {
      const endpoint = geminiGenerateContentEndpoint(baseUrl, model);

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
          35000,
        );

        if (res.ok) {
          return await parseGeminiResponse(res);
        }

        const body = await res.text();
        failures.push(`${model} @ ${baseUrl}: HTTP ${res.status} ${body.slice(0, 300)}`);
        if (!shouldTryNextGeminiEndpoint(res.status, body)) {
          break;
        }
      } catch (err) {
        failures.push(`${model} @ ${baseUrl}: ${err instanceof Error ? err.message : String(err)}`);
      }
    }
  }

  throw new Error(`Gemini API failed. ${failures.join(" | ")}`);
}

async function callGeminiStream(
  apiKey: string,
  payload: unknown,
  onChunk: (chunk: any) => Promise<void>,
): Promise<any> {
  const baseUrls = uniqueBaseUrls([GEMINI_BASE_URL, ...GEMINI_FALLBACK_BASE_URLS]);
  const models = uniqueList([GEMINI_MODEL, ...GEMINI_FALLBACK_MODELS]);
  const failures: string[] = [];

  for (const model of models) {
    for (const baseUrl of baseUrls) {
      const endpoint = geminiGenerateContentEndpoint(baseUrl, model);

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
          35000,
        );

        if (res.ok) {
          return await parseGeminiStreamingResponse(res, onChunk);
        }

        const body = await res.text();
        failures.push(`${model} @ ${baseUrl}: HTTP ${res.status} ${body.slice(0, 300)}`);
        if (!shouldTryNextGeminiEndpoint(res.status, body)) {
          break;
        }
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

async function parseGeminiStreamingResponse(
  res: Response,
  onChunk: (chunk: any) => Promise<void>,
): Promise<any> {
  const contentType = res.headers.get("content-type") ?? "";

  if (!contentType.includes("text/event-stream")) {
    const data = await res.json();
    await onChunk(data);
    return data;
  }

  if (!res.body) {
    throw new Error("Gemini streaming response did not include a body");
  }

  const chunks: any[] = [];
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = "";
  let dataLines: string[] = [];

  const processPayload = async (payload: string) => {
    if (!payload || payload === "[DONE]") return;

    let chunk: any;
    try {
      chunk = JSON.parse(payload);
    } catch {
      console.warn("Skipping invalid Gemini SSE payload:", payload.slice(0, 120));
      return;
    }

    if (chunk?.error) {
      throw new Error(`Gemini SSE error: ${JSON.stringify(chunk.error)}`);
    }

    chunks.push(chunk);
    await onChunk(chunk);
  };

  const processLine = async (rawLine: string) => {
    const line = rawLine.endsWith("\r") ? rawLine.slice(0, -1) : rawLine;

    if (line === "") {
      if (dataLines.length > 0) {
        await processPayload(dataLines.join("\n"));
        dataLines = [];
      }
      return;
    }

    if (line.startsWith("data:")) {
      dataLines.push(line.slice("data:".length).trimStart());
    }
  };

  while (true) {
    const { value, done } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });

    let lineEnd = buffer.indexOf("\n");
    while (lineEnd !== -1) {
      const line = buffer.slice(0, lineEnd);
      buffer = buffer.slice(lineEnd + 1);
      await processLine(line);
      lineEnd = buffer.indexOf("\n");
    }
  }

  buffer += decoder.decode();
  if (buffer) {
    await processLine(buffer);
  }
  await processLine("");

  if (chunks.length === 0) {
    throw new Error("Gemini SSE response did not contain JSON chunks");
  }

  return mergeGeminiStreamChunks(chunks);
}

function mergeGeminiStreamChunks(chunks: any[]): any {
  const merged: any = { candidates: [] };

  for (const chunk of chunks) {
    const candidates = Array.isArray(chunk?.candidates) ? chunk.candidates : [];
    for (const candidate of candidates) {
      const index = typeof candidate?.index === "number" ? candidate.index : 0;
      const target = merged.candidates[index] ?? {
        index,
        content: { role: "model", parts: [] },
      };

      const parts = Array.isArray(candidate?.content?.parts)
        ? candidate.content.parts
        : [];
      for (const part of parts) {
        if (part?.thought === true) continue;
        if (typeof part?.text === "string") {
          const currentText = target.content.parts
            .map((item: any) => typeof item?.text === "string" ? item.text : "")
            .join("");
          const nextText = appendStreamText(currentText, part.text);
          target.content.parts = nextText ? [{ text: nextText }] : [];
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

    if (chunk?.usageMetadata) {
      merged.usageMetadata = chunk.usageMetadata;
    }
  }

  merged.candidates = merged.candidates.filter(Boolean);
  return merged;
}

function buildPrompt(dish: string, target: string): string {
  return [
    `Dish query: ${dish}`,
    `Target language: ${target}`,
    "",
    "Use Google Search grounding to look up current public web information about this dish.",
    "Return only valid JSON. Do not use Markdown or code fences.",
    "The JSON object must be exactly:",
    "{\"title\":\"...\",\"description\":\"...\"}",
    "",
    "Rules:",
    "1. title should be the dish name in the target language; preserve the original name when it is the common name.",
    "2. description should be one natural, concise paragraph in the target language.",
    "3. Mention typical flavor, appearance/color, common ingredients, and serving style when available.",
    "4. Do not mention Google Search, web search, sources, grounding, or that you looked anything up.",
    "5. If the query is ambiguous, describe the most common food interpretation and avoid unsupported claims.",
  ].join("\n");
}

function buildStreamingPrompt(dish: string, target: string): string {
  return [
    `Dish query: ${dish}`,
    `Target language: ${target}`,
    "",
    "Use Google Search grounding to look up current public web information about this dish.",
    "Write only the final dish description paragraph in the target language.",
    "Do not output JSON, Markdown, bullets, labels, title lines, source notes, or code fences.",
    "The paragraph must be complete and end with normal sentence punctuation.",
    "",
    "Content requirements:",
    "1. Mention typical flavor, appearance/color, common ingredients, and serving style when available.",
    "2. Keep it useful for someone deciding what to order at a restaurant.",
    "3. Do not mention Google Search, web search, sources, grounding, or that you looked anything up.",
    "4. If the query is ambiguous, describe the most common food interpretation and avoid unsupported claims.",
  ].join("\n");
}

function parseDishAnswer(text: string, fallbackTitle: string): DishAnswer {
  const cleaned = cleanupGeneratedText(text);
  const jsonText = extractLastJSONObjectText(cleaned);
  const candidates = uniqueList([cleaned, jsonText ?? ""]);

  for (const candidate of candidates) {
    try {
      return dishAnswerFromParsed(JSON.parse(candidate), fallbackTitle);
    } catch {
      // Try the next candidate; Gemini occasionally wraps the JSON in extra text.
    }
  }

  const partial = dishAnswerFromPartialText(cleaned, fallbackTitle);
  if (partial.description || partial.title !== fallbackTitle) {
    return partial;
  }

  return {
    title: fallbackTitle,
    description: sanitizeGeneratedDescription(cleaned),
  };
}

function dishAnswerFromParsed(parsed: any, fallbackTitle: string): DishAnswer {
  let title = typeof parsed?.title === "string" && parsed.title.trim()
    ? parsed.title.trim()
    : fallbackTitle;
  let description =
    typeof parsed?.description === "string" && parsed.description.trim()
      ? parsed.description.trim()
      : null;

  if (description) {
    const nestedText = extractLastJSONObjectText(cleanupGeneratedText(description));
    if (nestedText) {
      try {
        const nested = JSON.parse(nestedText);
        if (typeof nested?.title === "string" && nested.title.trim()) {
          title = nested.title.trim();
        }
        if (typeof nested?.description === "string" && nested.description.trim()) {
          description = nested.description.trim();
        }
      } catch {
        description = sanitizeGeneratedDescription(description) ?? description;
      }
    }
  }

  description = sanitizeGeneratedDescription(description);
  return { title, description };
}

function dishAnswerFromPartialText(text: string, fallbackTitle: string): DishAnswer {
  const cleaned = cleanupGeneratedText(text);
  const title = extractJsonStringFieldPrefix(cleaned, "title")?.value.trim() ||
    fallbackTitle;
  const description = sanitizeGeneratedDescription(
    extractJsonStringFieldPrefix(cleaned, "description")?.value,
  );

  return {
    title,
    description,
  };
}

function sanitizeGeneratedDescription(value: string | null | undefined): string | null {
  if (typeof value !== "string") return null;

  const cleaned = cleanupGeneratedText(value);
  if (!cleaned) return null;

  const looksStructured = cleaned.startsWith("{") ||
    cleaned.includes("\"description\"") ||
    cleaned.includes("\\\"description\\\"");

  if (!looksStructured) {
    return cleaned;
  }

  try {
    const parsed = JSON.parse(cleaned);
    if (typeof parsed?.description === "string" && parsed.description.trim()) {
      return sanitizeGeneratedDescription(parsed.description);
    }
  } catch {
    // Fall through to prefix extraction for partial JSON.
  }

  const description = extractJsonStringFieldPrefix(cleaned, "description")?.value;
  if (description && description !== cleaned) {
    return sanitizeGeneratedDescription(description);
  }

  const nestedText = extractLastJSONObjectText(cleaned);
  if (nestedText && nestedText !== cleaned) {
    return sanitizeGeneratedDescription(nestedText);
  }

  return cleaned
    .replace(/^\{\s*"title"\s*:\s*"[^"]*"\s*,\s*"description"\s*:\s*"/, "")
    .replace(/"\s*\}\s*$/, "")
    .trim() || null;
}

function isProbablyIncompleteDescription(value: string | null | undefined): boolean {
  const clean = sanitizeGeneratedDescription(value);
  if (!clean) return true;

  const terminal = clean.trim().at(-1) ?? "";
  const hasSentenceEnd = /[。.!！？?]$/.test(terminal);
  if (!hasSentenceEnd) return true;

  const cjkChars = clean.match(/[\u3400-\u9fff]/g)?.length ?? 0;
  if (cjkChars > 0) {
    return cjkChars < 45;
  }

  const wordCount = clean.split(/\s+/).filter(Boolean).length;
  return wordCount < 35;
}

function completeDescription(
  value: string | null | undefined,
  target: string,
): string | null {
  const clean = sanitizeGeneratedDescription(value);
  if (!clean) return null;

  if (/[。.!！？?]$/.test(clean.trim())) {
    return clean.trim();
  }

  const trimmed = clean
    .replace(/[，,、；;：:]\s*$/, "")
    .trim();
  const isCJKTarget = /中文|chinese|zh|cn/i.test(target) ||
    /[\u3400-\u9fff]/.test(trimmed);

  return `${trimmed}${isCJKTarget ? "。" : "."}`;
}

function cleanupGeneratedText(text: string): string {
  return text
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
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
  if (!Array.isArray(parts)) {
    return "";
  }

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

function extractVisibleTextFromGeminiChunk(chunk: any): string {
  const candidates = Array.isArray(chunk?.candidates) ? chunk.candidates : [];
  let output = "";

  for (const candidate of candidates) {
    const parts = Array.isArray(candidate?.content?.parts)
      ? candidate.content.parts
      : [];

    for (const part of parts) {
      if (part?.thought === true) continue;
      if (typeof part?.text === "string") {
        output += part.text;
      }
    }
  }

  return output;
}

function extractJsonStringFieldPrefix(
  text: string,
  field: string,
): { value: string; complete: boolean } | null {
  const pattern = new RegExp(`"${escapeRegExp(field)}"\\s*:\\s*"`, "m");
  const match = pattern.exec(text);
  if (!match) return null;

  let index = match.index + match[0].length;
  let value = "";

  while (index < text.length) {
    const char = text[index];

    if (char === "\"") {
      return { value, complete: true };
    }

    if (char === "\\") {
      const next = text[index + 1];
      if (!next) break;

      switch (next) {
        case "\"":
        case "\\":
        case "/":
          value += next;
          index += 2;
          continue;
        case "b":
          value += "\b";
          index += 2;
          continue;
        case "f":
          value += "\f";
          index += 2;
          continue;
        case "n":
          value += "\n";
          index += 2;
          continue;
        case "r":
          value += "\r";
          index += 2;
          continue;
        case "t":
          value += "\t";
          index += 2;
          continue;
        case "u": {
          const hex = text.slice(index + 2, index + 6);
          if (hex.length < 4 || !/^[0-9a-fA-F]{4}$/.test(hex)) {
            return { value, complete: false };
          }
          value += String.fromCharCode(parseInt(hex, 16));
          index += 6;
          continue;
        }
        default:
          value += next;
          index += 2;
          continue;
      }
    }

    value += char;
    index += 1;
  }

  return { value, complete: false };
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function sseMessage(event: string, data: unknown): string {
  const payload = JSON.stringify(normalizeForJson(data));
  return `event: ${event}\ndata: ${payload}\n\n`;
}

function normalizeForJson(value: unknown): unknown {
  if (typeof value === "string") {
    return wellFormedString(value);
  }

  if (Array.isArray(value)) {
    return value.map((item) => normalizeForJson(item));
  }

  if (value && typeof value === "object") {
    const normalized: Record<string, unknown> = {};
    for (const [key, item] of Object.entries(value)) {
      normalized[key] = normalizeForJson(item);
    }
    return normalized;
  }

  return value;
}

function wellFormedString(value: string): string {
  let output = "";

  for (let index = 0; index < value.length; index += 1) {
    const code = value.charCodeAt(index);

    if (code >= 0xd800 && code <= 0xdbff) {
      const next = value.charCodeAt(index + 1);
      if (next >= 0xdc00 && next <= 0xdfff) {
        output += value[index] + value[index + 1];
        index += 1;
      } else {
        output += "\uFFFD";
      }
      continue;
    }

    if (code >= 0xdc00 && code <= 0xdfff) {
      output += "\uFFFD";
      continue;
    }

    output += value[index];
  }

  return output;
}

function extractGroundingSources(grounding: any): GroundingSource[] {
  const chunks = Array.isArray(grounding?.groundingChunks)
    ? grounding.groundingChunks
    : [];
  const seen = new Set<string>();
  const sources: GroundingSource[] = [];

  for (const chunk of chunks) {
    const uri = typeof chunk?.web?.uri === "string" ? chunk.web.uri : "";
    if (!uri || seen.has(uri)) continue;

    seen.add(uri);
    sources.push({
      title: typeof chunk?.web?.title === "string" && chunk.web.title.trim()
        ? chunk.web.title.trim()
        : uri,
      uri,
    });
  }

  return sources;
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

function geminiGenerateContentEndpoint(baseUrl: string, model: string): string {
  const base = baseUrl.replace(/\/+$/, "");
  return `${base}/v1beta/models/${encodeURIComponent(model)}:generateContent?alt=sse`;
}

function parseBaseUrls(value: string): string[] {
  return parseList(value);
}

function parseList(value: string): string[] {
  return value
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function uniqueBaseUrls(baseUrls: string[]): string[] {
  const seen = new Set<string>();
  const unique: string[] = [];

  for (const baseUrl of baseUrls) {
    const normalized = baseUrl.replace(/\/+$/, "");
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    unique.push(normalized);
  }

  return unique;
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

function shouldTryNextGeminiEndpoint(status: number, body: string): boolean {
  if (status === 429 || status >= 500) return true;
  return (status === 400 && body.includes("not supported")) ||
    (status === 403 && body.includes("1010"));
}
