import { cleanMenuName } from "./menu_name.ts";

const MAX_SEARCH_QUERY_LENGTH = 400;
const MAX_QUALIFIER_LENGTH = 80;

function replaceControlCharacters(value: string): string {
  return Array.from(value).map((character) => {
    const code = character.codePointAt(0) ?? 0;
    return code <= 0x1f || code === 0x7f ? " " : character;
  }).join("");
}

function cleanQueryFragment(
  value: string | undefined,
  removeParentheses = false,
): string | undefined {
  if (!value) return undefined;

  let clean = replaceControlCharacters(value.normalize("NFKC"))
    .replace(/["“”]/g, " ");
  if (removeParentheses) clean = clean.replace(/[()（）]/g, " ");
  clean = clean
    .replace(/\s+/g, " ")
    .trim();

  return clean || undefined;
}

/**
 * The probe search deliberately contains only the cleaned menu text. Visual
 * review happens after SerpAPI responds, so no category or model-generated
 * term is allowed to influence this first search.
 */
export function buildDishImageProbeQuery(originalName: string): string {
  return (cleanQueryFragment(originalName) ?? "")
    .slice(0, MAX_SEARCH_QUERY_LENGTH)
    .trim();
}

/**
 * Treats a model/client supplied qualifier as plain text, never as Google
 * search syntax. This also gives the deep-search endpoint the same validation
 * as the value returned by Gemini.
 */
export function sanitizeDishImageQualifier(
  value: string | undefined,
): string | undefined {
  let clean = cleanQueryFragment(value, true);
  if (!clean) return undefined;

  clean = clean
    .replace(/(?:https?:\/\/|www\.)\S+/giu, " ")
    .replace(
      /\b(?:site|filetype|inurl|intitle|allinurl|allintitle|related|cache)\s*:\s*\S*/giu,
      " ",
    )
    .replace(/(^|\s)[+-]\S+/gu, "$1")
    .replace(/\b(?:OR|AND)\b/giu, " ")
    .replace(/[*|`#@:：]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
  clean = cleanMenuName(clean).slice(0, MAX_QUALIFIER_LENGTH).trim();

  return clean && /\p{L}/u.test(clean) ? clean : undefined;
}

/** Builds the one allowed follow-up query: `originalName（qualifier）`. */
export function buildDishImageDeepSearchQuery(
  originalName: string,
  qualifier: string,
): string {
  const dish = cleanQueryFragment(originalName) ?? "";
  const context = sanitizeDishImageQualifier(qualifier) ?? "";
  if (!context) return dish.slice(0, MAX_SEARCH_QUERY_LENGTH).trim();

  const dishBudget = Math.max(0, MAX_SEARCH_QUERY_LENGTH - 2);
  const boundedDish = dish.slice(0, dishBudget).trim();
  const contextBudget = Math.max(
    0,
    MAX_SEARCH_QUERY_LENGTH - boundedDish.length - 2,
  );
  const boundedContext = context.slice(0, contextBudget).trim();

  return boundedContext ? `${boundedDish}（${boundedContext}）` : boundedDish;
}
