# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 当前任务

- 名称：Phase 1——收口 AI / Codex 文档入口。
- 类型：`docs`；因修改 `RULES.md`，按 Strict Lane 管理。
- 目标分支：`develop`。
- 工作分支：`docs/consolidate-ai-document-entry`。
- PR：#66，状态 open，尚未 merge。

## 目标

建立一套实际生效、无重复冲突的文档入口：

1. `AGENTS.md` 作为唯一自动入口和读取路由。
2. `RULES.md` 只保留强门禁与安全边界。
3. `WORKFLOWS.md` 只保留执行流程、验证、rollback 和回传模板。
4. `CURRENT_TASK.md` 只保留当前活动任务事实。
5. `docs/README.md` 只作为人工文档索引。

## 当前状态

- 已从 `develop` 创建 `docs/consolidate-ai-document-entry`。
- 已修改上述五个授权文件。
- PR #66 已创建到 `develop`。
- 未修改代码、数据库、Supabase、Vercel、env、migration 或构建配置。
- 未操作 `main`、production 或 PR merge。

## 下一步

1. 对 PR #66 执行只读复核：changed files、链接、职责边界和高风险门禁保留情况。
2. 用户确认后才能 merge PR #66 到 `develop`。
3. Phase 1 稳定后，再单独讨论 Phase 2：合并重复模板、迁移归档报告、删除确认无引用的空壳文件。
4. 如需把本次治理文档同步到 `main`，必须另做 `develop -> main` 差异审计并再次确认。

## 当前允许范围

- 只允许修改：`AGENTS.md`、`docs/ai/RULES.md`、`docs/ai/WORKFLOWS.md`、`docs/ai/CURRENT_TASK.md`、`docs/README.md`。
- 允许只读检查 PR #66 和上述文件差异。

## 禁止事项与停止点

- 不 merge PR。
- 不操作 `main` 或 production。
- 不修改其他文档、代码、数据库、Supabase、Vercel、env、migration 或构建配置。
- 发现文件范围扩大、核心安全门禁遗漏、链接失效或规则冲突时，停止并回传。

## Rollback

- merge 前：关闭 PR #66。
- merge 到 `develop` 后：创建独立 revert PR。
- 无代码、数据库、Supabase、Vercel 或 production rollback 需求。