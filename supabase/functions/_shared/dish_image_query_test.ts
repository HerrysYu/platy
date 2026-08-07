import { buildDishImageSearchQuery } from "./dish_image_query.ts";

function assertEquals(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("adds category in parentheses only for an ambiguous dish", () => {
  const query = buildDishImageSearchQuery(
    "脚趾肉",
    true,
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );

  if (!query.startsWith("脚趾肉（鲜切牛肉） 菜品 美食")) {
    throw new Error(`Unexpected query order: ${query}`);
  }
});

Deno.test("does not add context for an unambiguous dish", () => {
  const query = buildDishImageSearchQuery(
    "金针菇",
    false,
    "菌菇类",
    "潮汕牛肉火锅",
  );

  if (!query.startsWith("金针菇 菜品 美食") || query.includes("菌菇类")) {
    throw new Error(`Unexpected clear-name query: ${query}`);
  }
});

Deno.test("uses menu context in parentheses when category is absent", () => {
  const query = buildDishImageSearchQuery(
    "脚趾肉",
    true,
    undefined,
    "潮汕牛肉火锅",
  );

  if (!query.startsWith("脚趾肉（潮汕牛肉火锅） 菜品 美食")) {
    throw new Error(`Unexpected menu-context query: ${query}`);
  }
});

Deno.test("prefers menu context over a generic category", () => {
  const query = buildDishImageSearchQuery(
    "吊龙",
    true,
    "招牌推荐",
    "潮汕牛肉火锅",
  );

  if (!query.startsWith("吊龙（潮汕牛肉火锅） 菜品 美食")) {
    throw new Error(`Unexpected generic-category query: ${query}`);
  }
});

Deno.test("keeps the query within the configured limit", () => {
  const query = buildDishImageSearchQuery(
    "菜".repeat(200),
    true,
    "分类".repeat(80),
    "菜单".repeat(80),
  );

  if (query.length > 400) {
    throw new Error(`Query is too long: ${query.length}`);
  }
});

Deno.test("preserves the simple no-context query behavior", () => {
  const query = buildDishImageSearchQuery("7-UP", false);
  const expectedPrefix = "7-UP 菜品 美食";
  assertEquals(query.slice(0, expectedPrefix.length), expectedPrefix);
});
