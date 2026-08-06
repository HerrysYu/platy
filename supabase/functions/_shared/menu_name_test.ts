import { cleanMenuName } from "./menu_name.ts";

function assertClean(input: string, expected: string): void {
  const actual = cleanMenuName(input);
  if (actual !== expected) {
    throw new Error(
      "Expected " + JSON.stringify(input) + " to become " +
        JSON.stringify(expected) + ", got " + JSON.stringify(actual),
    );
  }
}

Deno.test("removes OCR leaders and trailing prices", () => {
  assertClean("金针菇..", "金针菇");
  assertClean("…金针菇⋯", "金针菇");
  assertClean("金针菇---12元/份", "金针菇");
  assertClean("金针菇---12元-", "金针菇");
  assertClean("金针菇……￥12.00", "金针菇");
  assertClean("金针菇......12", "金针菇");
  assertClean("金针菇......12--", "金针菇");
  assertClean("金针菇--", "金针菇");
  assertClean("金针菇 时价", "金针菇");
  assertClean("金针菇 时价--", "金针菇");
  assertClean("...", "");
});

Deno.test("preserves punctuation and numbers inside legitimate names", () => {
  assertClean("Dr. Pepper", "Dr. Pepper");
  assertClean("A&W", "A&W");
  assertClean("7-UP", "7-UP");
  assertClean("-18°C冰淇淋", "-18°C冰淇淋");
  assertClean("C++", "C++");
  assertClean("#1套餐", "#1套餐");
  assertClean("酸菜鱼/水煮鱼", "酸菜鱼/水煮鱼");
  assertClean("クリーム・ブリュレ", "クリーム・ブリュレ");
});
