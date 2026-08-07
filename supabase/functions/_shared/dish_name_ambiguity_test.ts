import { parseGeminiNeedsContext } from "./dish_name_ambiguity.ts";

function geminiResponse(text: string): unknown {
  return {
    candidates: [{
      content: {
        parts: [{ text }],
      },
    }],
  };
}

Deno.test("parses a structured Gemini ambiguity decision", () => {
  const ambiguous = parseGeminiNeedsContext(
    geminiResponse('{"needsContext":true}'),
  );
  const clear = parseGeminiNeedsContext(
    geminiResponse('```json\n{"needsContext":false}\n```'),
  );

  if (ambiguous !== true) throw new Error("Expected an ambiguous decision");
  if (clear !== false) throw new Error("Expected a clear decision");
});

Deno.test("ignores Gemini thought parts before the final decision", () => {
  const decision = parseGeminiNeedsContext({
    candidates: [{
      content: {
        parts: [
          { thought: true, text: "Internal reasoning" },
          { text: '{"needsContext":true}' },
        ],
      },
    }],
  });

  if (decision !== true) throw new Error("Expected the final JSON decision");
});

Deno.test("rejects malformed Gemini ambiguity output", () => {
  const missingBoolean = parseGeminiNeedsContext(
    geminiResponse('{"needsContext":"yes"}'),
  );
  const commentary = parseGeminiNeedsContext(
    geminiResponse("The dish is ambiguous."),
  );

  if (missingBoolean !== undefined || commentary !== undefined) {
    throw new Error("Malformed decisions must be rejected");
  }
});
