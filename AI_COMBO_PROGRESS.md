# AI Combo 智能推荐功能 — 实施进度

> 目的:任何 agent(Claude 等)读取本文件即可从中断处继续工作。
> 每完成一步,把对应条目从 `[ ]` 改为 `[x]`,并在"当前状态"更新。

## 需求摘要
- 在扫描完菜单后(MenuPage),用户可触发 AI 智能推荐。
- AI(Gemini)作为 agent,结合**整份菜单 OCR 数据** + **用户偏好**(过敏原/饮食/文化背景,存于 supabase `profiles` 表),推荐一个 combo(菜品+主食 / 奶茶+甜品 等组合)。
- Agent 可通过工具调用:读菜单数据、读用户偏好、联网搜索(google_search grounding)。
- 云端:新建 supabase edge function `combo_recommend_api`,Gemini 调用方式参考 `dish_detail_api_gemini`(多 base-url + 多 model fallback,SSE 流式)。
- 本地:炫酷但不过分的触发动效(MenuPage 悬浮 AI 球 + 推荐 sheet),保证前后端连通。

## 关键事实(已勘察)
- 项目根:`/Users/herrysyu/Documents/platy`
- iOS 工程:`ProjectMayaIOS/ProjectMayaIOS`,objectVersion 77(fileSystemSynchronizedGroups),**新增 swift 文件无需改 pbxproj**
- supabase 项目 ref:`yxsjccowvxzxjiqfhazg`,CLI 已登录,workdir `/Users/herrysyu/Documents/platy`
- Gemini 密钥:edge function secret `GEMINI_API_KEY` 已存在(dish_detail_api_gemini 在用),base url `https://api.cubence.com`(代理),model `gemini-3-flash-preview`,fallback `gemini-2.5-flash`
- iOS 调 edge function 模式:见 `ProjectMayaIOS/ProjectMayaIOS/Api/dish_api.swift`(DishService,带 SSE 解析),URL 由 `PlatyConfig.functionURL(slug)` 生成,header 需 `apikey` + `Authorization: Bearer <token>`(authService.getAuthHeader())
- 菜单数据:`MenuPage` 持有 `menuBlocksList: [MenuBlocks]`,每个 block 有 `text`(原文)与 `translatedText`
- 用户偏好:`SupabaseClient.fetchProfile(authToken:userID:)` → `SupabaseProfileRecord`(allergies, dietaryPreferences, country, systemLanguage, menuLanguage)
- 订单:`OrderManager.add(dish: DishDetail, originalName:)`;主题/动效工具:`PlatyTheme` / `PlatyMotion` / `PlatyPressStyle` / `platyEntrance()`(Colors/ColorExtendsion.swift)

## 设计决定
- **云端** `supabase/functions/combo_recommend_api/index.ts`:
  - 请求体:`{ menu_items: [{name, translated?}], preferences: {allergies, diets, country, language}, target: "中文"|"English", stream: true }`
  - Agent loop:Gemini function-calling,工具 `get_menu_items` / `get_user_preferences` / `web_search`(web_search 内部用 google_search grounding 的二次 Gemini 调用实现,因为 functionDeclarations 不能与 google_search 同请求混用)
  - SSE 事件:`combo_status`(阶段文案,驱动前端动效)、`combo_done`(最终 JSON)、`combo_error`
  - 最终 JSON:`{ theme, summary, items: [{name, original_name, role, reason}], tips }`,role ∈ main/staple/drink/dessert/side
- **本地**:
  - `Api/combo_api.swift`:`ComboService`(SSE 解析参考 DishService)+ `ComboRecommendation` 模型
  - `Views/MenuTab/ComboAIButton.swift`:发光渐变 AI 悬浮球(呼吸光晕+缓慢旋转高光),放 MenuPage bottomBar 左侧
  - `Views/MenuTab/ComboRecommendationView.swift`:sheet;加载时旋转角向渐变光环+流式状态文案,完成后 combo 卡片(role 徽章、推荐理由、一键全部加入订单)
  - `MenuPage.swift`:接入按钮 + sheet,汇总所有页 blocks 文本(去重、截断 ~120 条)

## 进度 checklist
- [x] 0. 勘察代码库、确定方案、创建本进度文件
- [x] 1. 云端:编写 `supabase/functions/combo_recommend_api/index.ts`
- [x] 2. 云端:`supabase functions deploy combo_recommend_api`(已部署成功)
- [x] 3. 云端:curl 冒烟测试 ✓ 非流式与流式(SSE)均验证通过。注意:**publishable key 不是 JWT,curl 测试需真实用户 JWT**(已建测试号 combo-smoke-test-20260610@example.com / SmokeTest!20260610,用 /auth/v1/token?grant_type=password 换 token)。agent 正确调用 get_menu_items/get_user_preferences,避开过敏原,流式事件序列:combo_status(start→reading_menu→reading_preferences→thinking→done)→combo_done
- [x] 4. 本地:`Api/combo_api.swift`(ComboRecommendation/ComboMenuItem/ComboPreferences 模型 + ComboService 流式 SSE)
- [x] 5. 本地:`Views/MenuTab/ComboAIButton.swift`(发光 AI 球:旋转渐变环 + 呼吸光晕 + 点击爆发环,respects reduceMotion)
- [x] 6. 本地:`Views/MenuTab/ComboRecommendationView.swift`(thinking 光环 + 流式状态文案 → combo 卡片 + 一键加入订单 + 重试/换一套)
- [x] 7. 本地:`MenuPage.swift` 接入(bottomBar 左侧 AI 球、sheet、comboMenuItems 汇总去重截断 120 条;偏好在 sheet 内 fetchProfile)
- [x] 8. 验证:xcodebuild BUILD SUCCEEDED(generic/platform=iOS Simulator)
- [x] 9. 收尾:全部完成
- [x] 10. 增强(用户追加需求):combo item **必须**来自本 session 扫描的菜单(1-2 张均覆盖)。
  - 客户端本就满足:`MenuPage.comboMenuItems` 遍历整个 `menuBlocksList`(所有页)。
  - 云端新增硬校验(`enforceMenuMatch`/`filterToMenuItems`/`matchMenuItem`):归一化匹配(去空白/标点/数字、容忍 OCR 价格噪声),agent loop 中不匹配则把违规项反馈给模型重选;最终兜底静默丢弃无法匹配项;`original_name` 强制回写为菜单 OCR 原文。已重新部署并冒烟验证(带 ¥ 价格噪声的菜单,original_name 精确回写)。

## 测试命令
```bash
# 部署
cd /Users/herrysyu/Documents/platy && supabase functions deploy combo_recommend_api

# 冒烟测试(非流式)。anon key 即 iOS config.swift 里的 supabasePublishableKey
curl -sS -X POST "https://yxsjccowvxzxjiqfhazg.supabase.co/functions/v1/combo_recommend_api" \
  -H "Content-Type: application/json" \
  -H "apikey: sb_publishable_B6KCU2Zd4F-nz9xUVODKjQ_3bl3Nzow" \
  -H "Authorization: Bearer sb_publishable_B6KCU2Zd4F-nz9xUVODKjQ_3bl3Nzow" \
  -d '{"menu_items":[{"name":"剁椒鱼头","translated":"Chopped Chili Fish Head"},{"name":"扬州炒饭","translated":"Yangzhou Fried Rice"},{"name":"珍珠奶茶","translated":"Bubble Tea"},{"name":"杨枝甘露","translated":"Mango Pomelo Sago"}],"preferences":{"allergies":["Nuts"],"diets":[],"country":"China","language":"中文"},"target":"中文"}'

# 编译验证
cd /Users/herrysyu/Documents/platy/ProjectMayaIOS && xcodebuild -project ProjectMayaIOS.xcodeproj -scheme ProjectMayaIOS -destination 'generic/platform=iOS Simulator' build 2>&1 | tail -5
```

## Round 3(2026-06-10 用户追加)checklist — ✅ 全部完成,BUILD SUCCEEDED
- [x] R3-1 Combo 禁止双主食:prompt 硬规则 5(面/饭/粥/饺/包/饼均算主食,最多一个;主菜本身是主食则占用主食位)。已部署,3 次冒烟(牛肉面+粥+炒饭诱导菜单)均只出 1 个主食
- [x] R3-2 冷启动历史为空,三个根因全修:
  - `MealHistory.swift`:meals 从 UserDefaults(4MB 上限,带图必写失败)改为文件持久化 Application Support/saved_meals.json(原子写,旧 key 一次性迁移);远端同步改合并不覆盖本地;`MenuImage.swift` encode 改 JPEG 0.72
  - `auth_service.swift`:restoreSession 过期不再 signOut,改走 refresh_token 续期;新增 `refreshSessionIfNeeded(completion:)`
  - `ProjectMayaIOSApp.swift`:scenePhase → active 时续期 token + 拉取 meals;`LandingPage.swift`:onReceive($recentMeals) 响应同步完成 + .task 主动 refreshFromRemoteIfNeeded
- [x] R3-3 相机页:CameraView .resizeAspectFill 占满全屏;去掉右上角历史/设置按钮及其 navigationDestination;取景框改屏宽自适应(aspectRatio 0.74 + 横向 padding 30);删扫描横线和 "Ready" 胶囊;torch 接通(CameraService 基类 isTorchOn/setTorch,RealCameraService 用 AVCaptureDevice lockForConfiguration,按钮亮起 accent 色;Stub/模拟器只切状态)
- [x] R3-4 PhotoPreviewPage:按钮改 "Translate Menu →",处理中切换为旋转弧+"Translating"(ZStack 隐形 ghost 保持宽度稳定,scale+opacity 过渡);照片入场改 1.05→1 "落定" 动画(去掉双重动画),加投影
- [x] R3-5 ComboRecommendationView:theme 标题去渐变改纯白;thinking 改安静版(细弧 spinner + 静态 fork.knife 图标,删光晕/双环/脉冲/渐变 sparkles)
- [x] R3-6 DishDetailView 按钮 "Generating" → "Thinking"
- [x] R3-7 zoom 卡顿:`OCROverlayViewModel` 增加 isPinching;pinch 期间整个标签层从视图树移除(不再逐帧测量全部标签),结束 0.14s 淡回;删掉标签层随 scale 的 softSpring 逐帧动画
- [x] R3-8 防误触:viewModel 发布 isZoomedIn(scale > fitted+0.01),经 onZoomChange 回调上抛到 MenuPage,TabView `.scrollDisabled(isZoomedIn)`,放大平移不再误翻页

## Round 4(2026-06-14 用户追加)checklist — ✅ 全部完成,BUILD SUCCEEDED
- [x] R4-1 多菜单拍照逻辑重设计:PhotoPreviewPage 重写为 header(页数) + 大图(按 selectedIndex)+ 缩略图条(每张可 × 删除、点选切换大图)+ 末尾 + 加页 + Translate。真值 vm.capturedImages;删空自动 dismiss 回相机。删除无用的 ButtonsAtTop
- [x] R4-2 相机页去掉 "Platy" + "Menu Lens"(删 topBar 视图与属性)
- [x] R4-3 相机页扫描框放大(FocusFrame 横向 padding 30→16)
- [x] R4-4a 设置页(UserCenterPage)整页重写为内联编辑:Region 内联 TextField(已选显示真实值,空显示 "Select Country" 占位)+ 过敏原/饮食 chips + App/Menu 语言 segmented,改动经 UserSettingsViewModel(@StateObject,600ms 防抖)自动 upsert Supabase,顶部显示 saving/Saved。删除跳转 PreferencesPage;PreferencesPage.swift 已删(无其他引用)
- [x] R4-4b 移除 smart filter:删 Services/SmartMenuTextFilter.swift + Services/MLXSmartMenuTextFilter.swift;PhotoPreviewPage.processSingleImage 去掉过滤直接用 OCR;UserCenterPage 清掉全部 smart filter 代码。**并从 pbxproj 移除 SPM 依赖**(mlx-swift-lm/swift-transformers/swift-huggingface 及 MLXLLM/MLXLMCommon/MLXHuggingFace/HuggingFace/Tokenizers 五个 product),构建确认 mlx bundle 已从 app 移除。pbxproj 备份在 /tmp/project.pbxproj.bak

## 当前状态
✅ **全部完成(2026-06-10)**。云端已部署并通过流式/非流式冒烟测试;iOS 编译通过。
剩余可选项(未做,按需):真机端到端走查 UI;删除冒烟测试用户 combo-smoke-test-20260610@example.com(Supabase Dashboard → Auth)。

## 改动文件清单
- 新增 `supabase/functions/combo_recommend_api/index.ts`(已部署)
- 新增 `ProjectMayaIOS/ProjectMayaIOS/Api/combo_api.swift`
- 新增 `ProjectMayaIOS/ProjectMayaIOS/Views/MenuTab/ComboAIButton.swift`
- 新增 `ProjectMayaIOS/ProjectMayaIOS/Views/MenuTab/ComboRecommendationView.swift`
- 修改 `ProjectMayaIOS/ProjectMayaIOS/Views/MenuTab/MenuPage.swift`(bottomBar 加 AI 球、combo sheet、comboMenuItems 汇总)
