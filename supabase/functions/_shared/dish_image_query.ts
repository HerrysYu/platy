const MAX_SEARCH_QUERY_LENGTH = 400;

const FOOD_INTENT_TERMS = ["菜品", "美食"];
const NON_FOOD_EXCLUSIONS = [
  "甲沟炎",
  "灰指甲",
  "趾甲",
  "皮肤病",
  "医疗",
  "医院",
  "疾病",
  "手术",
  "治疗",
  "人体",
];
const GENERIC_CATEGORY_KEYS = new Set([
  "招牌",
  "招牌菜",
  "招牌推荐",
  "推荐",
  "推荐菜",
  "新品",
  "新品推荐",
  "特色",
  "特色菜",
  "必点",
  "热销",
  "人气",
  "主厨推荐",
]);

function cleanQueryFragment(
  value: string | undefined,
  removeParentheses = false,
): string | undefined {
  if (!value) return undefined;

  let clean = value
    .normalize("NFKC")
    .replace(/["“”]/g, " ");
  if (removeParentheses) clean = clean.replace(/[()（）]/g, " ");
  clean = clean
    .replace(/\s+/g, " ")
    .trim();

  return clean || undefined;
}

function dedupeKey(value: string): string {
  return value.normalize("NFKC").toLowerCase();
}

function isGenericCategory(value: string | undefined): boolean {
  return value ? GENERIC_CATEGORY_KEYS.has(dedupeKey(value)) : false;
}

/**
 * Builds a dish-first Google Images query. Context is attached as
 * `dish（category）` only when the ambiguity classifier says it is needed.
 */
export function buildDishImageSearchQuery(
  originalName: string,
  needsContext: boolean,
  category?: string,
  menuContext?: string,
): string {
  const dish = cleanQueryFragment(originalName) ?? "";
  const cleanCategory = cleanQueryFragment(category, true);
  const cleanMenuContext = cleanQueryFragment(menuContext, true);
  const dishKey = dedupeKey(dish);
  const contextCandidates = isGenericCategory(cleanCategory)
    ? [cleanMenuContext, cleanCategory]
    : [cleanCategory, cleanMenuContext];
  const disambiguationContext = needsContext
    ? contextCandidates.find((value) => value && dedupeKey(value) !== dishKey)
    : undefined;

  const requiredSuffix = [
    ...FOOD_INTENT_TERMS,
    ...NON_FOOD_EXCLUSIONS.map((term) => `-${term}`),
  ].join(" ");
  const contextualBudget = Math.max(
    0,
    MAX_SEARCH_QUERY_LENGTH - requiredSuffix.length - 1,
  );

  let contextualQuery = dish.slice(0, contextualBudget).trim();
  if (disambiguationContext) {
    const categoryBudget = contextualBudget - contextualQuery.length - 2;
    if (categoryBudget > 0) {
      const categoryText = disambiguationContext.slice(0, categoryBudget)
        .trim();
      if (categoryText) contextualQuery += `（${categoryText}）`;
    }
  }

  return [contextualQuery, requiredSuffix].filter(Boolean).join(" ");
}
