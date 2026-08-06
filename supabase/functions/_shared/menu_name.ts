const EDGE_DOT_CHARACTERS = new Set(
  Array.from(".。．…⋯․‥·•‧∙⋅・"),
);
const TRAILING_SEPARATOR_CHARACTERS = new Set(
  Array.from(".。．…⋯․‥·•‧∙⋅・-‐‑‒–—―_|｜¦~～:：;；,，"),
);

const AMOUNT = String.raw`\d{1,7}(?:[.,]\d{1,2})?`;
const CURRENCY_CODES = String
  .raw`(?:RMB|CNY|USD|EUR|GBP|JPY|KRW|HKD|TWD|NTD|SGD|AUD|CAD|THB|VND|INR|PHP|MYR|IDR)`;
const PREFIX_CURRENCY = String
  .raw`(?:(?:HK|NT|US|S|AU|CA)?\p{Sc}|${CURRENCY_CODES})`;
const SUFFIX_CURRENCY = String
  .raw`(?:\p{Sc}|元|圆|圓|块|塊|円|원|บาท|${CURRENCY_CODES})`;
const OPTIONAL_SERVING = String
  .raw`(?:\s*[/／]\s*(?:份|位|例|盘|盤|碟|碗|杯|个|個|只|人|斤|两|兩|克|g|kg|person|pc))?`;
const OPTIONAL_PRICE_QUALIFIER = String.raw`(?:\s*(?:起|以上|up))?`;
const OPTIONAL_SEPARATOR = String.raw`[\s.…⋯․‥·•‧∙⋅・:：|｜¦_＿~～‐‑‒–—―-]*`;
const REQUIRED_LEADER = String.raw`[\s.…⋯․‥·•‧∙⋅・:：|｜¦_＿~～‐‑‒–—―-]{2,}`;

const TRAILING_CURRENCY_PRICE = new RegExp(
  String
    .raw`${OPTIONAL_SEPARATOR}(?:(?:${PREFIX_CURRENCY}\s*${AMOUNT})|(?:${AMOUNT}\s*${SUFFIX_CURRENCY}))${OPTIONAL_SERVING}${OPTIONAL_PRICE_QUALIFIER}\s*$`,
  "iu",
);
const TRAILING_MARKET_PRICE = new RegExp(
  String.raw`${OPTIONAL_SEPARATOR}(?:时价|時價|market\s*price|m\.?p\.?)\s*$`,
  "iu",
);
const TRAILING_BARE_PRICE_AFTER_LEADER = new RegExp(
  String
    .raw`${REQUIRED_LEADER}(?:${PREFIX_CURRENCY}\s*)?${AMOUNT}(?:\s*${SUFFIX_CURRENCY})?${OPTIONAL_SERVING}${OPTIONAL_PRICE_QUALIFIER}\s*$`,
  "iu",
);

function isWhitespace(character: string): boolean {
  return /^\s$/u.test(character);
}

function trimEdgeDots(value: string): string {
  const characters = Array.from(value.trim());
  let start = 0;
  let end = characters.length;

  while (
    start < end &&
    (EDGE_DOT_CHARACTERS.has(characters[start]) ||
      isWhitespace(characters[start]))
  ) start += 1;
  while (
    end > start &&
    (EDGE_DOT_CHARACTERS.has(characters[end - 1]) ||
      isWhitespace(characters[end - 1]))
  ) end -= 1;

  return characters.slice(start, end).join("").trim();
}

function trimTrailingSeparators(value: string): string {
  const characters = Array.from(value.trim());
  let end = characters.length;
  while (
    end > 0 &&
    (TRAILING_SEPARATOR_CHARACTERS.has(characters[end - 1]) ||
      isWhitespace(characters[end - 1]))
  ) end -= 1;
  return characters.slice(0, end).join("").trim();
}

/**
 * Removes OCR leader dots, trailing separators, and a trailing menu price.
 * Internal punctuation and leading hyphens remain intact, so names such as
 * Dr. Pepper, 7-UP, A&W, and -18°C冰淇淋 are preserved.
 */
export function cleanMenuName(value: string): string {
  let cleaned = trimEdgeDots(value);
  cleaned = trimTrailingSeparators(cleaned);
  cleaned = cleaned.replace(TRAILING_MARKET_PRICE, "").trim();
  cleaned = cleaned.replace(TRAILING_CURRENCY_PRICE, "").trim();
  cleaned = cleaned.replace(TRAILING_BARE_PRICE_AFTER_LEADER, "").trim();
  cleaned = trimTrailingSeparators(cleaned);
  return trimEdgeDots(cleaned);
}
