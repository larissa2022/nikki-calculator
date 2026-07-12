# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 当前状态

- 当前无活动任务。
- Phase 1“收口 AI / Codex 文档入口”已完成：PR #66 已合并到 `develop`，merge commit 为 `4ca13eff0666681a74b332c407b68df06c81f624`。
- Phase 2“合并重复职责并归档历史材料”已完成：PR #67 已合并到 `develop`，merge commit 为 `5e5e0491663e42b10bd1cd1c9c1ffb3d4f423f6d`。
- `AGENTS.md` 现为唯一自动入口；读取路由只在该文件维护。
- `docs/ai/RULES.md` 只承担强门禁，`docs/ai/WORKFLOWS.md` 承担执行流程，`docs/README.md` 承担人工文档索引。
- 历史报告已移入 `docs/archive/**`，不参与当前任务路由。

## 最近完成

- 2026-07-12：完成 `BUG-20260711-015` development 浏览器验证；冲突短编号被安全跳过，混合输入中的有效编号正常录入，弹窗和结果报告文案符合预期。
- 验证未登录执行；仅在临时浏览器会话构造冲突样本，无数据库、Supabase、Vercel 或 production 写入。

## 新任务启动

1. 从最新 `develop` 创建窄范围任务分支。
2. 按仓库根目录 `AGENTS.md` 进行任务分类和条件读取。
3. 在修改前明确允许范围、禁止事项、验收、停止点和 rollback。
4. 新任务不得继承本轮已经结束的临时授权。

## 当前边界

- 不直接修改 `main`、production、数据库、Supabase、Vercel、env 或 migration。
- PR merge、`main`、production、database、Supabase、Vercel 和修改 `RULES.md` 仍需用户单独明确确认。
- 如需将本轮文档治理同步到 `main`，必须作为独立 release 任务先执行 `develop -> main` 只读差异审计。
- `docs/archive/**` 只用于历史审计，不作为当前状态或执行依据。

## Rollback

- 本看板收口 PR merge 前：关闭 PR。
- merge 到 `develop` 后：创建独立 revert PR。
- 无代码、数据库、Supabase、Vercel 或 production rollback 需求。
