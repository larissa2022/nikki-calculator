# 当前任务

当前任务：docs-only 数据库安全文档与历史报告职责收口。

## 本次任务边界

- 只收口允许范围内的 `docs/` 文档。
- 不开发业务功能。
- 不修改数据库、Supabase、Vercel 或构建配置。
- 不操作 `main` / production。
- 不修改 `docs/ai/RULES.md`。
- 不新增 `docs/ai/DOCUMENT_MAP.md`。

## 当前状态

- 工作分支：`docs/cleanup-db-safety-and-reports`。
- 目标 base：`develop`。
- 已同步 PR #14 merge 后的 `develop`。
- 允许更新数据库安全说明、历史报告归档说明、文件治理说明和当前任务状态。
- 如发现需要修改 `RULES.md`、业务 / 配置文件、数据库连接配置或新增文档地图文件，应记录为未确认事项，不在本任务内越权修改。

## 本次重点

- 收口 `docs/database/数据库开发安全方案.md` 中偏旧的环境风险表述。
- 明确 `docs/ai/CODEX_REPORT.md` 是历史执行报告 / 归档参考，不作为当前任务事实源。
- 更新 `docs/FILE_GOVERNANCE.md` 中对应未确认事项状态。
- 保持 docs-only，不新增正式 Rule。
