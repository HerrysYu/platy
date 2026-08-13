import {
  deriveDishImageProbeOutcome,
  minimumApprovedDishImages,
} from "./dish_image_review_outcome.ts";

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

Deno.test("uses half of reviewed images capped at three as the approval threshold", () => {
  const cases = [
    [0, 0],
    [1, 1],
    [2, 1],
    [3, 2],
    [4, 2],
    [5, 3],
    [6, 3],
    [20, 3],
  ];

  for (const [reviewed, expected] of cases) {
    assert(
      minimumApprovedDishImages(reviewed) === expected,
      `Expected ${reviewed} reviewed images to require ${expected}`,
    );
  }
});

Deno.test("does not deep search when enough reviewed images were approved", () => {
  const outcome = deriveDishImageProbeOutcome(
    {
      status: "completed",
      reviewedImages: 6,
      approvedImages: 3,
      qualifier: "鲜切牛肉",
    },
    "嫩牛肉",
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );

  assert(!outcome.needsDeepSearch, "Three of six approvals must be enough");
  assert(outcome.deepSearchTerm === undefined, "No deep term should be sent");
});

Deno.test("deep searches a completed low-approval review with its qualifier", () => {
  const outcome = deriveDishImageProbeOutcome(
    {
      status: "completed",
      reviewedImages: 6,
      approvedImages: 2,
      qualifier: "鲜切牛肉",
    },
    "脚趾肉",
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );

  assert(
    outcome.needsDeepSearch,
    "Two of six approvals must trigger deep search",
  );
  assert(outcome.deepSearchTerm === "鲜切牛肉", "Expected model qualifier");
});

Deno.test("uses a non-generic category or menu context for an empty qualifier", () => {
  const categoryOutcome = deriveDishImageProbeOutcome(
    {
      status: "completed",
      reviewedImages: 4,
      approvedImages: 1,
      qualifier: "",
    },
    "脚趾肉",
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );
  assert(categoryOutcome.deepSearchTerm === "鲜切牛肉", "Expected category");

  const menuOutcome = deriveDishImageProbeOutcome(
    {
      status: "completed",
      reviewedImages: 4,
      approvedImages: 1,
    },
    "脚趾肉",
    "招牌推荐",
    "潮汕牛肉火锅",
  );
  assert(
    menuOutcome.deepSearchTerm === "潮汕牛肉火锅",
    "A generic category must fall through to the menu context",
  );
});

Deno.test("never deep searches an unavailable review even when context exists", () => {
  const outcome = deriveDishImageProbeOutcome(
    { status: "unavailable", reviewedImages: 0 },
    "脚趾肉",
    "鲜切牛肉",
    "潮汕牛肉火锅",
  );

  assert(!outcome.needsDeepSearch, "Unavailable is not an unsafe verdict");
  assert(outcome.deepSearchTerm === undefined, "Unavailable has no deep term");
});

Deno.test("does not invent a generic deep term after low approval", () => {
  const outcome = deriveDishImageProbeOutcome(
    {
      status: "completed",
      reviewedImages: 3,
      approvedImages: 0,
      qualifier: "脚趾肉",
    },
    "脚趾肉",
    "推荐菜",
    "菜单",
  );

  assert(!outcome.needsDeepSearch, "A useful qualifier is required");
  assert(
    outcome.deepSearchTerm === undefined,
    "Generic context must be ignored",
  );
});
