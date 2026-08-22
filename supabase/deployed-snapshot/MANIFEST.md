# Supabase Edge Functions — 云端部署快照
- **项目**: ProjectMaya (`yxsjccowvxzxjiqfhazg`)
- **抓取时间**: 2026-08-22 09:47:10 UTC
- **抓取方式**: `supabase functions download --project-ref yxsjccowvxzxjiqfhazg --use-api`
- **对应 repo commit**: `d4cf2da`

这份快照是**云端实际在跑的代码**（从部署的 eszip bundle 反解出来的），用来和 `supabase/functions/` 下的仓库源码做对照。**不要直接部署这个目录** —— 它是备份，不是源码。

## 已部署的函数

| 函数 | 版本 | 云端更新时间 | verify_jwt | bundle sha256 | 与仓库源码 |
|---|---|---|---|---|---|
| `combo_recommend_api` | 8 | 2026-07-29 01:18:59 UTC | true | `667dbd55a586…` | in sync |
| `dish_advice_api` | 4 | 2026-06-13 17:52:06 UTC | true | `2f9ff41bcea6…` | in sync |
| `dish_detail_api` | 127 | 2026-06-05 18:34:18 UTC | true | `f90dce2b5473…` | **DRIFT** |
| `dish_detail_api_gemini` | 16 | 2026-06-09 09:09:47 UTC | true | `ccf66b055da8…` | **DRIFT** |
| `dish_detail_new` | 6 | 2026-08-06 13:33:53 UTC | true | `46ec6ef03740…` | in sync |
| `get_dish_images` | 38 | 2026-08-13 10:30:36 UTC | true | `a8ebc86f96d1…` | in sync |
| `translation_service` | 45 | 2026-08-06 13:33:46 UTC | true | `a2901fb5df9b…` | in sync |

## bundle 里带出来的 `_shared` 文件

| 文件 | 与仓库源码 |
|---|---|
| `_shared/dish_detail_api_gemini.ts` | in sync |
| `_shared/dish_image_query.ts` | in sync |
| `_shared/dish_image_review.ts` | in sync |
| `_shared/dish_image_review_outcome.ts` | in sync |
| `_shared/dish_image_search_unavailable.ts` | in sync |
| `_shared/fetch_text_with_timeout.ts` | in sync |
| `_shared/menu_name.ts` | in sync |

> 仓库里的 `_shared/*_test.ts` 不会进 bundle，所以快照里没有，属正常。

## ⚠️ 需要处理的漂移

### 1. `dish_detail_api` — 云端被单独改过

只差一行，`index.ts:11`：

| | `DEEPSEEK_MODEL` 默认值 |
|---|---|
| 仓库源码 | `deepseek-v4-pro` |
| 云端 v127 | `deepseek-v4-flash` |

这一行从初始 commit 起在 git 里就没变过，所以是**云端**被单独改成了 `flash`（dashboard 手改，或从未提交的本地状态部署上去的），不是仓库落后。

两个选择：
- 云端的 `flash` 是有意的 → 把仓库源码改成 `flash` 提交，让 git 反映现实
- 云端是误改 → `supabase functions deploy dish_detail_api` 把 `pro` 推回去

（注：线上如果设了 `DEEPSEEK_MODEL` 环境变量，这个默认值其实不生效，可以先查一下再决定。）

### 2. `dish_detail_api_gemini` — 云端是旧版，本地重构没部署

| | 内容 |
|---|---|
| 仓库源码 | 104 字节的 stub，`import { startDishDetailServer } from "../_shared/dish_detail_api_gemini.ts"` |
| 云端 v16 | 2026-06-09 的单体版本，29.5 KB，自己内联了一整套逻辑 |

7-31 把这个函数重构成了共享模块（`_shared/dish_detail_api_gemini.ts`，同一个模块 `dish_detail_new` 在用，且已经部署且 in sync），但 `dish_detail_api_gemini` 本身**一直没重新部署**。

也就是说线上这个函数跑的还是两个月前的逻辑，之后 `_shared` 里所有的改进它都没吃到。要对齐就部署：

```
supabase functions deploy dish_detail_api_gemini --project-ref yxsjccowvxzxjiqfhazg
```

部署前先确认它需要的环境变量（`GOOGLE_GEMINI_BASE_URL` / `GEMINI_MODEL` 等）在新的共享实现里语义没变。
