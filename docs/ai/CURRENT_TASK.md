# 当前任务

当前任务：衣柜短编号录入生产缺陷修复已完成，进入收口状态。

## 已完成

- PR #44：修复衣柜短编号录入按一级分类匹配，已 merge 到 `develop`。
- PR #45：从 `main` 派生 hotfix，只同步 PR #44 的 `src/components/ImportZone.vue` 修复，已 merge 到 `main`。
- Preview 验证：PR #44 Preview 已由用户确认成功。
- Production 验证：PR #45 merge 后，用户确认未发现明显问题。

## 本次缺陷结论

- 缺陷位置：录入衣柜功能中的“分类 + 短编号录入”。
- 原问题：短编号录入 UI 和匹配逻辑依赖 `FULL_CATEGORIES` 的二级 / 三级分类，例如 `饰品-头饰-发饰`、`饰品-耳饰`。
- 正确规则：玩家短编号录入只需要选择一级分类；同一一级分类下 `game_id` 已确认唯一。
- 修复方式：短编号录入模式只展示一级分类，并按“一级分类 + 归一化短编号”匹配 item。
- 保存结构：仍只保存 item id，不改变 `owned_clothes` 云端保存结构。
- 保护逻辑：保留同一一级分类 + 归一化短编号重复时的冲突提示和跳过保护。

## 当前状态

- 当前没有业务开发在进行。
- 衣柜短编号录入生产缺陷已通过 develop 修复和 main hotfix 处理完成。
- 未执行 Supabase / SQL / migration 操作。
- 未执行 Vercel 写操作或 env 修改。
- `develop` 相对 `main` 仍可能存在 docs 差异；后续同步 main 前仍需按规则做只读差异审计。

## 下一阶段候选

1. PR #43 的 docs 规则变更是否同步到 `main`。
2. Supabase advisor 安全风险拆分。
3. 需求文档正文结构审计。
4. 陪审团 / 重审 / 积分需求到执行计划梳理。
5. 业务开发入口审计。

## 进入下一任务前门槛

- 必须先判断任务类型：docs / business / database / config / incident。
- 涉及 `main`、production、database、Supabase、Vercel、env 或 merge 时，必须单独确认。
- `develop -> main` 前必须做只读差异审计，并按 docs / business / database / config 分类。
- 不得混合 docs / business / database / config 变更。
- 涉及未确认产品口径、字段、状态值、权限边界或数据安全时，必须暂停并取得用户确认。
