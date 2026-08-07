import { buildDishImageSearchQuery } from "./dish_image_query.ts";

function assertEquals(actual: string, expected: string): void {
  if (actual !== expected) {
    throw new Error(
      `Expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`,
    );
  }
}

Deno.test("puts the original dish first and its category in parentheses", () => {
  const query = buildDishImageSearchQuery(
    "脚趾肉",
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );

  if (!query.startsWith("脚趾肉（鲜切牛肉） 潮汕牛肉火锅 菜品 美食")) {
    throw new Error(`Unexpected query order: ${query}`);
  }
});

Deno.test("uses menu context as a weak fallback when category is absent", () => {
  const query = buildDishImageSearchQuery(
    "脚趾肉",
    undefined,
    "吊龙、匙仁、五花趾",
  );

  if (!query.startsWith("脚趾肉 吊龙、匙仁、五花趾 菜品 美食")) {
    throw new Error(`Unexpected fallback query: ${query}`);
  }
});

Deno.test("does not repeat the dish or category as menu context", () => {
  const withDishDuplicate = buildDishImageSearchQuery(
    "金针菇",
    "金针菇",
    "菌菇类",
  );
  const withCategoryDuplicate = buildDishImageSearchQuery(
    "金针菇",
    "菌菇类",
    "菌菇类",
  );

  if (!withDishDuplicate.startsWith("金针菇 菌菇类 菜品 美食")) {
    throw new Error(`Unexpected dish de-duplication: ${withDishDuplicate}`);
  }
  if (!withCategoryDuplicate.startsWith("金针菇（菌菇类） 菜品 美食")) {
    throw new Error(
      `Unexpected category de-duplication: ${withCategoryDuplicate}`,
    );
  }
});

Deno.test("keeps the query within the configured limit", () => {
  const query = buildDishImageSearchQuery(
    "菜".repeat(200),
    "分类".repeat(80),
    "菜单".repeat(80),
  );

  if (query.length > 400) {
    throw new Error(`Query is too long: ${query.length}`);
  }
});

Deno.test("preserves the simple no-context query behavior", () => {
  const query = buildDishImageSearchQuery("7-UP");
  const expectedPrefix = "7-UP 菜品 美食";
  assertEquals(query.slice(0, expectedPrefix.length), expectedPrefix);
});
