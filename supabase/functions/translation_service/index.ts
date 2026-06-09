// /functions/translate-deepl/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

console.log("🚀 Translation Function Started (using Supabase built-in JWT auth)");

serve(async (req) => {
  try {
    // -------- 1. 解析请求内容 --------
    const { words, targetLang } = await req.json();

    if (!Array.isArray(words)) {
      return jsonError("Missing 'words' array", 400);
    }
    if (!targetLang) {
      return jsonError("Missing 'targetLang'", 400);
    }

    // -------- 2. 读取 DeepL API Key --------
    const apiKey = Deno.env.get("DEEPL_API_KEY");
    if (!apiKey) {
      return jsonError("DEEPL_API_KEY is not configured", 500);
    }

    // -------- 3. 构建 DeepL 翻译请求 --------
    const formData = new URLSearchParams();
    words.forEach((w) => formData.append("text", w));
    formData.append("target_lang", targetLang);
    formData.append("model_type","quality_optimized");
    const deeplRes = await fetch("https://api-free.deepl.com/v2/translate", {
      method: "POST",
      headers: {
        "Authorization": `DeepL-Auth-Key ${apiKey}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: formData.toString(),
    });

    if (!deeplRes.ok) {
      const errText = await deeplRes.text();
      return jsonError("DeepL translation failed", deeplRes.status, errText);
    }

    const deeplData = await deeplRes.json();

    const translations = deeplData.translations.map((t: any) => ({
      detectedSourceLang: t.detected_source_language,
      text: t.text,
    }));

    // -------- 4. 返回结果 --------
    return new Response(
      JSON.stringify({
        count: translations.length,
        original: words,
        translations,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );

  } catch (e) {
    return jsonError(e.message, 500);
  }
});

// -------- Helper --------

function jsonError(message: string, status = 400, detail: any = null) {
  return new Response(JSON.stringify({ error: message, detail }), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
