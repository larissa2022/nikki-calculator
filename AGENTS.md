# Nikki Calculator 仓库规则

## 固定约定

- 使用北京时间（UTC+8）记录时间。
- 使用中文 `git commit` 信息。
- GitHub 是远程事实源；本地未推送内容不算已发布。
- `main` 对应 production，`develop` 对应 development / preview。
- 默认从 `develop` 创建 `codex/*`、`docs/*`、`feature/*` 或 `fix/*` 分支，并以 `develop` 为 PR 目标。
- 不擅自合并 PR、操作 `main`、写 production、写 Supabase、写 Vercel、修改 env 或执行 migration。

## 默认读取

- 每个任务只先读本文件和用户明确指定的文件。
- 需要了解项目进度时，再读 `docs/ai/CURRENT_TASK.md`。
- 只有涉及 production、database、Supabase、Vercel、migration、发布或治理冲突时，才读 `docs/ai/RULES.md`、`docs/ai/WORKFLOWS.md` 及对应专题文档。
- 不因旧对话、历史计划或待确认事项自动扩大任务范围。

## 风险边界

- 普通文档或只读检查：可直接执行并验证。
- 业务代码或非生产配置：按用户指定范围执行并运行相关验证。
- `main`、production、database、Supabase、Vercel、migration、PR merge、历史改写、分支删除、`RULES.md`：必须单独确认目标、影响、验证和 rollback。
- 不在同一 PR 混合 docs、business、database、config，除非用户明确要求。
- 不提交 `tmp/**`、`.env*`、`supabase/.temp/**`、token、验证码、授权链接、keyring 信息或 production 写入脚本。

## 常用验证

- 构建：`npm.cmd run build`
- 通用验证：`npm.cmd run verify`
- development 数据库链接检查：`npm.cmd run db:check`
- 数据库安全验证：`npm.cmd run verify:db`
- seal100x 只读审计：`npm.cmd run audit:seal100x-clothes`
- seal100x 样本 dry-run：`npm.cmd run data-sync:seal100x-clothes-sample`

## 回传格式

- 只用中文回传：完成内容、修改文件、验证结果、风险、尚未确认、建议下一步。
- 不粘贴无关日志；失败时只提供定位问题所需的关键错误。
- 超大审计文件只在本地处理，默认只回传计数、分类、异常和最多 10 条样本。
- 同一授权批次连续执行；验收通过后立即收口，独立任务开启新对话。
