import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.46.1";

const EMBEDDING_API_URL =
  Deno.env.get("EMBEDDING_API_URL") ?? "https://api.gpt.ge/v1/embeddings";
const EMBEDDING_MODEL =
  Deno.env.get("EMBEDDING_MODEL") ?? "text-embedding-3-large";
const DEEPSEEK_API_URL =
  Deno.env.get("DEEPSEEK_API_URL") ??
    "https://api.deepseek.com/chat/completions";
const DEEPSEEK_MODEL = Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-v4-pro";
const MATCH_COUNT = clampNumber(
  Number(Deno.env.get("DISH_RAG_MATCH_COUNT") ?? "5"),
  1,
  10,
);

type DishInfoMatch = {
  id: string;
  name: string;
  category: string;
  description: string;
  image_url: string | null;
  similarity: number;
};

type DishAnswer = {
  title: string | null;
  description: string | null;
};

console.log("dish_detail_api started: embedding + dish_info RAG + DeepSeek");

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

    if (!dish) {
      return respond(req, 400, empty());
    }

    const queryEmbedding = await embedText(dish);
    const matches = await matchDishInfo(req, queryEmbedding, MATCH_COUNT);
    const answer = await generateDishAnswer(dish, target, matches);

    const bestMatch = matches[0] ?? null;
    const image = bestMatch?.image_url && isHttpUrl(bestMatch.image_url)
      ? bestMatch.image_url
      : null;

    return respond(req, 200, {
      title: answer.title ?? bestMatch?.name ?? dish,
      description: answer.description ?? bestMatch?.description ?? null,
      thumbil: image ? [image] : [],
      source: image ? [image] : [],
      matches: matches.map((match) => ({
        id: match.id,
        name: match.name,
        category: match.category,
        similarity: match.similarity,
      })),
    });
  } catch (err) {
    console.error("dish_detail_api error:", err);
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
      "authorization, x-client-info, apikey, content-type",
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

async function embedText(input: string): Promise<number[]> {
  const apiKey = getRequiredEnv(
    "EMBEDDING_API_KEY",
    "GPT_GE_API_KEY",
    "OPENAI_API_KEY",
  );

  const res = await fetchWithTimeout(
    EMBEDDING_API_URL,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: EMBEDDING_MODEL,
        input,
      }),
    },
    20000,
  );

  if (!res.ok) {
    throw new Error(`Embedding API failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  const embedding = data?.data?.[0]?.embedding;
  if (!isNumberArray(embedding) || embedding.length !== 3072) {
    throw new Error("Embedding API returned an invalid 3072-d vector");
  }

  return embedding;
}

async function matchDishInfo(
  req: Request,
  embedding: number[],
  matchCount: number,
): Promise<DishInfoMatch[]> {
  const supabaseUrl = getRequiredEnv("SUPABASE_URL");
  const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ??
    getRequiredEnv("SUPABASE_ANON_KEY");
  const authorization = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    ? `Bearer ${supabaseKey}`
    : req.headers.get("Authorization") ?? `Bearer ${supabaseKey}`;

  const supabase = createClient(supabaseUrl, supabaseKey, {
    auth: { persistSession: false },
    global: {
      headers: {
        Authorization: authorization,
      },
    },
  });

  const { data, error } = await supabase.rpc("match_dish_info", {
    query_embedding: vectorLiteral(embedding),
    match_count: matchCount,
  });

  if (error) {
    throw new Error(`match_dish_info RPC failed: ${error.message}`);
  }

  if (!Array.isArray(data)) return [];

  return data
    .map((item: any) => ({
      id: String(item.id),
      name: String(item.name ?? ""),
      category: String(item.category ?? ""),
      description: String(item.description ?? ""),
      image_url: typeof item.image_url === "string" ? item.image_url : null,
      similarity: Number(item.similarity ?? 0),
    }))
    .filter((item) => item.id && item.name && item.description);
}

async function generateDishAnswer(
  queryDish: string,
  target: string,
  matches: DishInfoMatch[],
): Promise<DishAnswer> {
  if (matches.length === 0) {
    return { title: queryDish, description: null };
  }

  const apiKey = getRequiredEnv("DEEPSEEK_API_KEY");
  const prompt = buildRagPrompt(queryDish, target, matches);

  const res = await fetchWithTimeout(
    DEEPSEEK_API_URL,
    {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: DEEPSEEK_MODEL,
        messages: [
          {
            role: "system",
            content:
              "You are ProjectMaya's dish knowledge assistant. Return only valid JSON. The JSON object must contain string fields title and description.",
          },
          {
            role: "user",
            content: prompt,
          },
        ],
        response_format: { type: "json_object" },
        stream: false,
        temperature: 0.25,
        max_tokens: 700,
        thinking: { type: "disabled" },
      }),
    },
    30000,
  );

  if (!res.ok) {
    throw new Error(`DeepSeek API failed: ${res.status} ${await res.text()}`);
  }

  const data = await res.json();
  const content = data?.choices?.[0]?.message?.content;
  if (typeof content !== "string" || !content.trim()) {
    throw new Error("DeepSeek API returned an empty message");
  }

  return parseDishAnswer(content, queryDish, matches[0]);
}

function buildRagPrompt(
  queryDish: string,
  target: string,
  matches: DishInfoMatch[],
): string {
  const context = matches
    .map((item, index) =>
      [
        `候选 ${index + 1}`,
        `id: ${item.id}`,
        `name: ${item.name}`,
        `category: ${item.category}`,
        `similarity: ${item.similarity.toFixed(4)}`,
        `description: ${item.description}`,
      ].join("\n")
    )
    .join("\n\n");

  return [
    `用户查询菜名: ${queryDish}`,
    `目标输出语言: ${target}`,
    "",
    "以下是从 dish_info 数据库用 embedding 相似度检索得到的候选资料，按相似度从高到低排序:",
    context,
    "",
    "请基于最相关的候选资料生成菜品详情。",
    "要求:",
    "1. 只输出合法 JSON，不要 Markdown，不要代码块。",
    "2. JSON 格式必须是 {\"title\":\"...\",\"description\":\"...\"}。",
    "3. title 使用目标语言；如果菜名是专有名词，可以保留原菜名或自然翻译。",
    "4. description 使用目标语言，写成一段自然、简洁的介绍，说明典型口味、外观色泽、常见食材或上桌形式。",
    "5. 不要提到 embedding、RAG、数据库、候选、相似度或“根据资料”。",
    "6. 如果查询词和候选不是完全同一道菜，请优先解释最可能对应的菜，并避免编造数据库中没有的具体事实。",
  ].join("\n");
}

function parseDishAnswer(
  content: string,
  queryDish: string,
  bestMatch: DishInfoMatch,
): DishAnswer {
  const cleaned = content
    .replace(/^```json\s*/i, "")
    .replace(/^```\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();

  try {
    const parsed = JSON.parse(cleaned);
    const title = typeof parsed?.title === "string" && parsed.title.trim()
      ? parsed.title.trim()
      : bestMatch.name || queryDish;
    const description =
      typeof parsed?.description === "string" && parsed.description.trim()
        ? parsed.description.trim()
        : bestMatch.description;
    return { title, description };
  } catch {
    return {
      title: bestMatch.name || queryDish,
      description: cleaned || bestMatch.description,
    };
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

function getRequiredEnv(...names: string[]): string {
  for (const name of names) {
    const value = Deno.env.get(name);
    if (value) return value;
  }
  throw new Error(`Missing required env var: ${names.join(" or ")}`);
}

function vectorLiteral(vector: number[]): string {
  return `[${vector.join(",")}]`;
}

function isNumberArray(value: unknown): value is number[] {
  return Array.isArray(value) &&
    value.every((item) => typeof item === "number" && Number.isFinite(item));
}

function isHttpUrl(value: string): boolean {
  return /^https?:\/\//i.test(value);
}

function clampNumber(value: number, min: number, max: number): number {
  if (!Number.isFinite(value)) return min;
  return Math.max(min, Math.min(max, Math.trunc(value)));
}
