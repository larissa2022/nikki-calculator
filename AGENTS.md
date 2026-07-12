# Nikki Calculator AI 执行入口

本文件是仓库中唯一的 AI / Codex 自动启动入口。其他 Markdown 文档不会仅因存在于仓库中而自动生效，必须由本文件或用户任务明确路由读取。

## 1. 固定约定

- 使用北京时间（UTC+8）记录时间。
- 使用中文 commit 信息和中文回传。
- GitHub 是远程事实源；未 push 的内容不算已发布。
- `main` 对应 production，`develop` 对应 development / preview。
- 默认从 `develop` 创建窄范围的 `docs/*`、`feature/*`、`fix/*` 或 `codex/*` 分支，并以 `develop` 为 PR 目标。
- 不自动 merge PR，不直接操作 `main`、production、Supabase、Vercel、env 或 migration。

## 2. 任务启动与读取路由

开始任务时先分类：`read-only`、`docs`、`business`、`database`、`config`、`release`。

所有任务先读取：

- 本文件。
- 用户明确指定的文件。
- 当前任务直接相关的代码或文档。

按任务条件补读：

| 条件 | 必须补读 |
| --- | --- |
| 用户说“继续”“下一步”或询问当前进度 | `docs/ai/CURRENT_TASK.md` |
| 任何文件修改、commit、push 或 PR 创建 | `docs/ai/RULES.md`，以及 `docs/ai/WORKFLOWS.md` 中对应任务章节 |
| 产品规则、用户行为或技术口径变化 | `docs/ai/DECISIONS.md`；按需读取 `docs/requirements/**`、`docs/planning/**` |
| 缺陷修复 | `docs/planning/缺陷文档.md` 和相关代码；涉及产品语义时追加 `DECISIONS.md` |
| `main`、production、release、hotfix | `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` |
| database、Supabase、SQL、RPC、RLS、migration | `docs/database/环境信息.md`、`docs/database/数据库开发安全方案.md`、`docs/database/数据库变更记录.md`；按需读取 `schema.md` |
| 文档职责冲突或文档收口 | `docs/README.md`；必要时读取 `docs/FILE_GOVERNANCE.md` |
| 复盘、Pattern Candidate、Rule Candidate | `docs/ai/LESSONS.md` |

不要因为旧对话、历史报告、历史计划或文件存在而自动扩大读取和执行范围。

## 3. 启动回执

任何修改开始前，必须先输出一次紧凑启动回执：

```text
当前分支：
任务类型：
自动入口：AGENTS.md
本任务额外读取：文件 + 原因
允许修改：
禁止事项：
验收：
停止点：
```

只读任务不需要单独等待确认，但最终回传仍应说明实际读取范围。已获任务级授权的批次不得逐命令重复询问；范围变化、命令失败、环境变化或触发停止点时必须暂停。

## 4. 强制边界摘要

- 用户本人是最终决策者。
- docs、business、database、config、release 不在同一 PR 混合，除非用户明确授权。
- `main`、production、database、Supabase、Vercel、migration、env、PR merge、历史改写、分支删除、修改 `RULES.md`，必须单独确认目标、影响、验证和 rollback。
- `gh pr merge` 永远需要用户再次明确确认。
- 不提交 `tmp/**`、`.env*`、`supabase/.temp/**`、token、验证码、授权链接、keyring 信息或 production 写库脚本。
- 发现实际范围超出任务单、出现规则冲突或会改变未确认的用户行为时，立即停止。

完整强规则见 `docs/ai/RULES.md`，具体执行步骤见 `docs/ai/WORKFLOWS.md`。

## 5. 回传格式

只回传：完成内容、修改文件、验证结果、风险、rollback、尚未确认、建议下一步。不要粘贴无关日志、完整大 JSON、SQL 全量结果或重复历史背景；默认最多提供 10 条异常样本。