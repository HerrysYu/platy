import { sanitizeDishImageQualifier } from "./dish_image_query.ts";

const GENERIC_CONTEXT_KEYS = new Set([
  "menu",
  "restaurant",
  "菜单",
  "餐厅菜单",
  "菜品",
  "美食",
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

export type DishImageProbeReviewSummary =
  | {
    status: "completed";
    reviewedImages: number;
    approvedImages: number;
    qualifier?: string;
  }
  | {
    status: "unavailable";
    reviewedImages: number;
  };

export type DishImageProbeOutcome = {
  needsDeepSearch: boolean;
  deepSearchTerm?: string;
  minimumApprovedImages: number;
};

function normalizedKey(value: string): string {
  return value.normalize("NFKC").replace(/\s+/g, " ").trim().toLowerCase();
}

function isUsefulContext(
  value: string | undefined,
  originalName: string,
): value is string {
  if (!value) return false;
  const key = normalizedKey(value);
  return key !== normalizedKey(originalName) && !GENERIC_CONTEXT_KEYS.has(key);
}

export function minimumApprovedDishImages(reviewedImages: number): number {
  const reviewed = Number.isFinite(reviewedImages)
    ? Math.max(0, Math.floor(reviewedImages))
    : 0;
  return Math.min(3, Math.ceil(reviewed / 2));
}

/**
 * Converts a completed per-image review into the probe response. An upstream
 * failure is not evidence that the search was inaccurate, so unavailable
 * reviews never request a deep search.
 */
export function deriveDishImageProbeOutcome(
  review: DishImageProbeReviewSummary,
  originalName: string,
  category?: string,
  menuContext?: string,
): DishImageProbeOutcome {
  const minimumApprovedImages = minimumApprovedDishImages(
    review.reviewedImages,
  );
  if (review.status !== "completed") {
    return { needsDeepSearch: false, minimumApprovedImages };
  }

  const approvedImages = Number.isFinite(review.approvedImages)
    ? Math.max(0, Math.floor(review.approvedImages))
    : 0;
  if (approvedImages >= minimumApprovedImages) {
    return { needsDeepSearch: false, minimumApprovedImages };
  }

  const modelQualifier = sanitizeDishImageQualifier(review.qualifier);
  const cleanCategory = sanitizeDishImageQualifier(category);
  const cleanMenuContext = sanitizeDishImageQualifier(menuContext);
  const deepSearchTerm = isUsefulContext(modelQualifier, originalName)
    ? modelQualifier
    : [cleanCategory, cleanMenuContext].find((value) =>
      isUsefulContext(value, originalName)
    );

  return {
    needsDeepSearch: Boolean(deepSearchTerm),
    deepSearchTerm,
    minimumApprovedImages,
  };
}
