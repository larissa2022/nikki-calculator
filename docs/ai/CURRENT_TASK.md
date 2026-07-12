# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 当前任务

- 名称：Phase 2——合并重复职责并归档历史材料。
- 类型：`docs`，Fast Lane。
- 目标分支：`develop`。
- 工作分支：`docs/consolidate-document-archive`。
- PR：#67，状态 open，尚未 merge。

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
- 已建立 `docs/archive/` 和归档索引。
- Token 使用审计已迁入归档目录。
- 原 Codex 历史报告已从活动目录移除；归档摘要记录原 blob SHA，完整原文仍保存在 Git 历史。
- `CONVERSATION_HANDOFF.md`、`FILE_GOVERNANCE.md`、`REJECTED_IDEAS.md` 已删除，其职责已由现有核心文档承担。
- 活动入口引用已更新。
- PR #67 已创建到 `develop`。
- 未修改 `RULES.md`、代码、数据库、Supabase、Vercel、env、migration 或构建配置。
- 未操作 `main`、production 或 PR merge。

## 下一步

1. 对 PR #67 复核 changed files、归档边界和活动入口。
2. 用户再次明确确认后才能 merge PR #67 到 `develop`。
3. merge 后将当前看板收口为 Phase 2 已完成。
4. 是否同步到 `main` 属于独立 release 任务，需先做 `develop -> main` 只读审计。

## 当前允许范围

- 只读检查 PR #67、活动入口和归档文件。
- 如复核发现 Phase 2 引入的文档断链，只允许在当前分支修正对应文档。

## 禁止事项与停止点

- 不修改 `RULES.md`、`DECISIONS.md`、需求、规划、数据库或业务代码。
- 不操作 `main`、production、Supabase、Vercel、env、migration 或构建配置。
- 不 merge PR，不删除分支。
- 发现旧文件仍承担当前事实源、内容无法安全归档或活动入口出现断链时，停止并回传。

## Rollback

- PR merge 前：关闭 PR #67，`develop` 保持不变。
- merge 到 `develop` 后：创建独立 revert PR。
- 完整旧报告仍可从 Git 历史和原 blob SHA 恢复。
- 无代码、数据库、Supabase、Vercel 或 production rollback 需求。
