# 当前任务

当前任务：记录 PR #17 数据库审计结论。

## 本次任务边界

- 类型：docs-only。
- 目标分支：`develop`。
- 工作分支：`docs/pr17-database-audit`。
- 只允许修改：
  - `docs/ai/CURRENT_TASK.md`
  - `docs/database/SUPABASE_REVIEW.md`
  - `docs/database/数据库变更记录.md`
- 不修改业务代码、数据库、Supabase、Vercel、env、migration、schema 或 `docs/ai/RULES.md`。
- 不执行 Supabase / psql / SQL。
- 不操作 `main` / production。
- 不 merge PR。

## PR #17 审计结论

- PR #17 当前是 database migration 草案，内容为新增贡献与积分 schema。
- PR #17 当前 base 为 `main`，不应按当前状态继续 merge。
- PR #17 应标记为 blocked / paused。
- 下一步应先处理 Supabase 安全 / RLS / `SECURITY DEFINER` advisor 风险，再继续 database feature。
- 后续如继续贡献 / 积分 schema，应关闭当前 PR 后从 `develop` 重开，或 retarget 到 `develop` 后保持 blocked，并拆分为多个 database PR。

## 后续必须补齐

- migration apply 前必须先做 development 重复数据预检、SQL / RLS 验证和 rollback 方案。
- `clothes(category, game_id)` partial unique index 需要先查重复键。
- `security_invoker` view + revoke 底层表权限可能导致公开 contributor view / RPC 不可读，需要单独验证。
- `source_pending_id` 缺失会影响追溯、回滚和争议处理，应在后续 schema 设计中补齐或明确放弃。
- schema 创建、RPC 接入、展示 view、历史 backfill 应拆成多个 database PR。

## 当前状态

- 本轮只记录审计结论。
- 未执行 database / Supabase / SQL / Vercel 操作。
- 未触碰 production。
- 未修改 `docs/ai/RULES.md`。
