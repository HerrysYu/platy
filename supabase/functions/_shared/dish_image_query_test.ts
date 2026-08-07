import {
  buildDishImageDeepSearchQuery,
  buildDishImageProbeQuery,
  sanitizeDishImageQualifier,
} from "./dish_image_query.ts";

function assertEquals(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("probe query uses only the original menu name", () => {
  assertEquals(buildDishImageProbeQuery("脚趾肉"), "脚趾肉");
  assertEquals(buildDishImageProbeQuery("  金针菇  "), "金针菇");
});

Deno.test("probe query does not append food or exclusion terms", () => {
  const query = buildDishImageProbeQuery("脚趾肉");
  for (const forbidden of ["鲜切牛肉", "菜品", "美食", "-甲沟炎"]) {
    if (query.includes(forbidden)) {
      throw new Error(`Probe query unexpectedly contains ${forbidden}`);
    }
  }
});

Deno.test("deep query appends only the Gemini qualifier in parentheses", () => {
  assertEquals(
    buildDishImageDeepSearchQuery("脚趾肉", "鲜切牛肉"),
    "脚趾肉（鲜切牛肉）",
  );
});

Deno.test("deep query strips nested parentheses from the qualifier", () => {
  assertEquals(
    buildDishImageDeepSearchQuery("脚趾肉", "（潮汕）鲜切牛肉"),
    "脚趾肉（潮汕 鲜切牛肉）",
  );
});

Deno.test("deep qualifier is plain text rather than search syntax", () => {
  assertEquals(
    sanitizeDishImageQualifier(
      "site:evil.example 鲜切牛肉 OR filetype:html -甲沟炎 https://evil.example",
    ) ?? "",
    "鲜切牛肉",
  );
  assertEquals(
    buildDishImageDeepSearchQuery("脚趾肉", "site:evil.example 鲜切牛肉"),
    "脚趾肉（鲜切牛肉）",
  );
});

Deno.test("queries stay within the configured limit", () => {
  const probe = buildDishImageProbeQuery("菜".repeat(500));
  const deep = buildDishImageDeepSearchQuery(
    "菜".repeat(200),
    "分类".repeat(200),
  );

  if (probe.length > 400 || deep.length > 400) {
    throw new Error(
      `Query is too long: probe=${probe.length}, deep=${deep.length}`,
    );
  }
});

Deno.test("preserves meaningful punctuation in the dish name", () => {
  assertEquals(buildDishImageProbeQuery("7-UP"), "7-UP");
  assertEquals(
    buildDishImageDeepSearchQuery("-18°C冰淇淋", "甜品"),
    "-18°C冰淇淋（甜品）",
  );
});
