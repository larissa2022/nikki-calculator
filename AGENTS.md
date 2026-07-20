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
| 用户说“继续”“下一步”、询问进度或开始项目任务 | `docs/ai/CURRENT_TASK.md` |
| 任何文件修改、commit、push 或 PR 创建 | `docs/ai/RULES.md`，以及 `docs/ai/WORKFLOWS.md` 中对应任务章节 |
| 产品规则、用户行为或技术口径变化 | `docs/ai/DECISIONS.md`；按需读取 `docs/requirements/**`、`docs/planning/**` |
| 缺陷修复 | `docs/planning/缺陷文档.md` 和相关代码；涉及产品语义时追加 `DECISIONS.md` |
| `main`、production、release、hotfix | `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` |
| database、Supabase、SQL、RPC、RLS、migration | `docs/database/环境信息.md`、`docs/database/数据库开发安全方案.md`、`docs/database/数据库变更记录.md`；按需读取 `schema.md` |
| 文档职责冲突或文档收口 | `docs/README.md` |
| 复盘、Pattern Candidate、Rule Candidate 或未采纳方案复查 | `docs/ai/LESSONS.md` |

`CURRENT_TASK.md` 是业务看板，重点记录业务目标、技术目标、最近完成、下一步任务和阻塞；分支创建、命令顺序和新任务启动规则放在本文件或 `WORKFLOWS.md`，不得占据看板主体。

不要因为旧对话、历史报告、历史计划或文件存在而自动扩大读取和执行范围。`docs/archive/**` 仅用于历史审计，不参与当前任务路由。

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

只读任务不需要单独等待确认，但最终回传仍应说明实际读取范围。

## 4. 连续批次执行

- 用户已经确认目标和任务级范围后，默认一次连续执行到当前授权的停止点：只读盘点 → 创建分支 → 修改 → 验证 → commit / push → 创建 PR。
- 不在分支创建、单个文件修改、单次 commit、push 或 PR 创建之间逐步等待确认。
- 不为“任务已启动”“PR 已创建”“PR 已合并”分别建立多个纯状态 PR；看板只在业务状态或下一步任务实质变化时更新。
- 对话进度只在发现关键结论、触发风险门禁或完成一个有意义的里程碑时更新，不逐条播报低层工具动作。
- 只有以下情况暂停：进入需单独确认的敏感操作、范围或环境变化、工具失败、规则冲突、出现未确认产品语义、验证失败或 rollback 不明确。
- PR merge、`main`、production、database / Supabase 写入、Vercel 写入、migration、历史改写和分支删除仍需单独明确确认。

## 5. 强制边界摘要

- 用户本人是最终决策者。
- docs、business、database、config、release 不在同一 PR 混合，除非用户明确授权。
- `main`、production、database、Supabase、Vercel、migration、env、PR merge、历史改写、分支删除、修改 `RULES.md`，必须单独确认目标、影响、验证和 rollback。
- `gh pr merge` 永远需要用户再次明确确认。
- 不提交 `tmp/**`、`.env*`、`supabase/.temp/**`、token、验证码、授权链接、keyring 信息或 production 写库脚本。
- 发现实际范围超出任务单、出现规则冲突或会改变未确认的用户行为时，立即停止。

完整强规则见 `docs/ai/RULES.md`，具体执行步骤见 `docs/ai/WORKFLOWS.md`。

## 6. 回传格式

最终回传只保留：完成内容、修改文件、验证结果、commit / PR、风险、rollback、尚未确认、下一步任务。

每次项目任务完成后必须附上当前任务看板链接。在本地 Codex App 中优先使用当前工作区的绝对文件链接；只有执行环境无法提供本地链接时才使用远程链接。

回传中的“下一步任务”必须与看板一致。不要粘贴无关日志、完整大 JSON、SQL 全量结果或重复历史背景；默认最多提供 10 条异常样本。
