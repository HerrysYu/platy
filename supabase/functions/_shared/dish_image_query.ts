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

function appendWithinBudget(
  current: string,
  value: string,
  budget: number,
): string {
  const available = budget - current.length - (current ? 1 : 0);
  if (available <= 0) return current;

  const addition = value.slice(0, available).trim();
  return addition ? [current, addition].filter(Boolean).join(" ") : current;
}

/**
 * Builds a dish-first Google Images query. The strongest category context is
 * attached directly to the dish as `dish（category）`; menu context remains a
 * weaker trailing hint because old records may derive it from nearby dishes.
 */
export function buildDishImageSearchQuery(
  originalName: string,
  category?: string,
  menuContext?: string,
): string {
  const dish = cleanQueryFragment(originalName) ?? "";
  const cleanCategory = cleanQueryFragment(category, true);
  const cleanMenuContext = cleanQueryFragment(menuContext, true);
  const dishKey = dedupeKey(dish);
  const categoryKey = cleanCategory ? dedupeKey(cleanCategory) : undefined;

  const usableCategory = cleanCategory && categoryKey !== dishKey
    ? cleanCategory
    : undefined;
  const menuContextKey = cleanMenuContext
    ? dedupeKey(cleanMenuContext)
    : undefined;
  const usableMenuContext = cleanMenuContext &&
      menuContextKey !== dishKey &&
      menuContextKey !== categoryKey
    ? cleanMenuContext
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
  if (usableCategory) {
    const categoryBudget = contextualBudget - contextualQuery.length - 2;
    if (categoryBudget > 0) {
      const categoryText = usableCategory.slice(0, categoryBudget).trim();
      if (categoryText) contextualQuery += `（${categoryText}）`;
    }
  }

  if (usableMenuContext) {
    contextualQuery = appendWithinBudget(
      contextualQuery,
      usableMenuContext,
      contextualBudget,
    );
  }

  return [contextualQuery, requiredSuffix].filter(Boolean).join(" ");
}
