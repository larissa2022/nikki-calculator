# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 当前任务

- 名称：Phase 2——合并重复职责并归档历史材料。
- 类型：`docs`，Fast Lane。
- 目标分支：`develop`。
- 工作分支：`docs/consolidate-document-archive`。
- PR：尚未创建。

## 目标

在 Phase 1 单一入口已经进入 `develop` 的基础上，继续减少重复文件：

1. ChatGPT → Codex 执行单职责收口到 `WORKFLOWS.md` 现有执行单、预审批和回传模板。
2. 文档职责地图收口到 `docs/README.md`。
3. 空的 Rejected Ideas 模板不再独立保留，未采纳方案按 `LESSONS.md` 的复盘状态记录。
4. Codex 历史报告和 Token 使用审计迁入 `docs/archive/**`。
5. 删除旧路径和活动入口中的过期引用。

## 当前状态

- PR #66 已合并到 `develop`，merge commit：`4ca13eff0666681a74b332c407b68df06c81f624`。
- 已从最新 `develop` 创建 `docs/consolidate-document-archive`。
- 已建立 `docs/archive/` 并写入归档索引。
- 已归档 Codex 历史报告摘要和 Token 使用审计。
- 正在更新活动入口并删除重复旧文件。
- 未修改 `RULES.md`、代码、数据库、Supabase、Vercel、env、migration 或构建配置。
- 未操作 `main`、production 或 PR merge。

## 下一步

1. 删除已完成职责迁移的旧文件。
2. 对 `develop...docs/consolidate-document-archive` 执行只读差异检查。
3. 创建 docs-only PR 到 `develop`。
4. PR merge 必须由用户再次明确确认。
5. 是否同步到 `main` 属于独立 release 任务，需先做 `develop -> main` 只读审计。

## 当前允许范围

- `AGENTS.md`
- `docs/README.md`
- `docs/ai/WORKFLOWS.md`（仅在发现现有执行单不足时修改）
- `docs/ai/LESSONS.md`（仅在存在实际迁移内容时修改）
- `docs/ai/CURRENT_TASK.md`
- `docs/archive/**`
- 删除已被上述文件替代的五个旧文档。

## 禁止事项与停止点

- 不修改 `RULES.md`、`DECISIONS.md`、需求、规划、数据库或业务代码。
- 不操作 `main`、production、Supabase、Vercel、env、migration 或构建配置。
- 不 merge PR，不删除分支。
- 发现旧文件仍承担当前事实源、内容无法安全归档或活动入口出现断链时，停止并回传。

## Rollback

- PR merge 前：关闭 PR，保留 `develop` 不变。
- merge 到 `develop` 后：创建独立 revert PR。
- 完整旧报告仍可从 Git 历史和原 blob SHA 恢复。
- 无代码、数据库、Supabase、Vercel 或 production rollback 需求。
