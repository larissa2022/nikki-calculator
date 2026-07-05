# Conversation Handoff

## 0. 用途

本文档用于 ChatGPT 对话迁移、新对话启动、ChatGPT -> Codex 指令交接。

本文件属于 Workflow 层，不是正式 Rule；若与 [`docs/ai/RULES.md`](RULES.md) 冲突，以 `RULES.md` 为准。

## 1. 适用场景

- ChatGPT 当前对话过长，需要开启新对话。
- 用户需要把旧对话中的项目上下文迁移到新 ChatGPT。
- 用户希望新 ChatGPT 继续生成 Codex 指令。
- 用户希望减少上下文丢失、重复解释和错误操作。

## 2. 迁移原则

- 用户手动迁移关键上下文，不依赖模型自动记忆。
- 迁移内容必须区分事实、决策、偏好、未确认事项。
- 只迁移当前项目必要信息，避免把临时推测升级为规则。
- 新对话中的 ChatGPT 必须先读交接内容，再生成 Codex 指令。
- ChatGPT 应在给 Codex 指令前完成任务级预审批。
- Codex 指令应一次性包含敏感命令清单、授权边界、失败处理。
- 对 docs-only 任务，若用户已确认任务范围，Codex 可连续执行 fetch / checkout / pull / add / commit / push / pr create。
- Codex 不应在每一步重复请求用户确认。
- Codex 仍只执行用户明确允许的任务。
- `gh pr merge`、`main`、production、database、Supabase、Vercel 操作仍需单独确认。

## 3. 迁移内容清单

迁移时必须包含以下内容。

### 3.1 项目事实

- 仓库名。
- 当前主分支策略。
- `main` / `develop` 环境映射。
- 当前已合并 PR。
- 当前打开 PR。
- 当前所在任务阶段。

### 3.2 治理规则

- GitHub 是事实源，未 push = 不存在。
- 用户是最终决策者。
- docs / business / database / config 分 PR。
- production 操作前必须再次确认。
- database migration 先在 development 验证。
- `gh` token / 验证码 / 授权链接不得入库。

### 3.3 当前状态

- 当前分支。
- 工作区是否 clean。
- 最新 commit。
- 未完成任务。
- rollback 方案。
- 未确认事项。

### 3.4 用户偏好

- 回答语言。
- 指令格式。
- 是否偏好简短精准。
- 是否需要结论先行。
- 是否需要 Codex 可直接执行的指令。

## 4. ChatGPT 新对话启动模板

用户可将以下模板复制到新的 ChatGPT 对话中，并按当前事实替换方括号内容。

```text
你将继续协助我管理 Nikki Calculator 项目。

项目背景：
- Repo: larissa2022/nikki-calculator
- 当前治理结构：
  - RULES.md = 宪法层
  - WORKFLOWS.md = 操作手册层
  - LESSONS.md = 复盘经验层
  - BRANCH_ENVIRONMENT_POLICY.md = 分支/环境治理层
  - CURRENT_TASK.md = 当前任务状态层
- 分支策略：
  - main = production
  - develop = development / preview
  - docs/feature/fix 分支默认从 develop 创建并回到 develop

你的角色：
- ChatGPT 负责整理上下文、判断风险、生成 Codex 可执行指令。
- ChatGPT 不直接批准正式 Rule，不执行生产操作。
- ChatGPT 必须区分事实、决策、偏好、未确认事项。

Codex 的角色：
- Codex 按用户确认的指令执行文件修改、验证、commit、push、创建 PR，并回传结果。
- Codex 不应越权修改禁止范围。
- Codex 不应在已授权 docs-only 任务中对每个 git add / commit / push / gh pr create 反复请求确认。

审批模式：
- 敏感操作的审批应优先在 ChatGPT 中完成。
- ChatGPT 生成 Codex 指令时，必须把敏感命令、用途、影响范围、失败处理写清楚。
- 用户确认后，Codex 在该任务授权范围内连续执行。
- Codex 只有在审批层拒绝、命令失败、范围变化、越权或涉及更高风险操作时停止。
- 不要让 Codex 在 docs-only 任务中对 git add / commit / push / gh pr create 反复请求确认。
- gh pr merge、main、production、database、Supabase、Vercel 操作仍需单独确认。

禁止事项：
- 不要把旧对话临时结论直接升级为 Rule。
- 不要混合 docs / business / database / config 变更。
- 不要在未确认时操作 main、production、database、Supabase、Vercel。
- 不要把 token、验证码、授权链接、keyring 信息写入仓库。

当前状态：
- 当前分支：[填写]
- 工作区状态：[填写 clean / dirty]
- 最新 commit：[填写]
- 当前已合并 PR：[填写]
- 当前打开 PR：[填写]
- 未完成任务：[填写]
- rollback 方案：[填写]
- 未确认事项：[填写]

当前任务：
[填写希望 ChatGPT 帮你整理的任务]

期望输出：
- 先给风险判断和任务边界。
- 再给 Codex 可直接执行的指令。
- 指令必须包含前置读取、敏感命令 Preflight、允许/禁止修改范围、执行步骤、验证步骤、提交/PR 步骤、回传要求和 rollback。
```

## 5. ChatGPT -> Codex 指令模板

```text
按治理流程执行：[任务名称]

目标：
- [任务目标]

审批层敏感命令 Preflight：
- 本任务已由 ChatGPT 完成任务级预审批。
- 允许 Codex 在本任务授权范围内连续执行：
  - git status
  - git branch --show-current
  - git fetch origin
  - git checkout develop
  - git pull origin develop
  - git checkout -b [docs/branch]
  - git diff --name-status
  - git diff
  - git add [指定 docs 文件]
  - git commit
  - git push origin [docs/branch]
  - gh pr create 到 develop
- 这些命令仅限本任务、仅限 docs-only 分支、仅限允许文件范围。
- 若审批层拒绝或命令失败，立即停止并回传，不重复执行，不换方式绕过。
- gh pr merge、main、production、database、Supabase、Vercel 仍需单独确认。

前置读取：
- docs/ai/RULES.md
- docs/ai/CURRENT_TASK.md
- docs/ai/WORKFLOWS.md
- docs/ai/CONVERSATION_HANDOFF.md
- docs/ai/LESSONS.md
- docs/governance/BRANCH_ENVIRONMENT_POLICY.md
- docs/database/环境信息.md
- docs/README.md

允许修改：
- [文件列表]

禁止修改：
- src/**
- supabase/**
- migration
- package*.json
- vite.config.*
- .env*
- production 写库脚本
- [其他禁止文件]

执行步骤：
1. git status
2. git branch --show-current
3. git fetch origin
4. git checkout develop
5. git pull origin develop
6. git checkout -b [docs/branch]
7. 修改允许的 docs 文件

验证步骤：
1. git status
2. git diff --name-status
3. git diff
4. 确认只修改允许文件。

提交 / PR：
1. git add [指定 docs 文件]
2. git commit -m "[中文提交信息]"
3. git push origin [docs/branch]
4. gh pr create --repo larissa2022/nikki-calculator --base develop --head [docs/branch] --title "[标题]" --body "[PR body]"

不要 merge PR。

回传要求：
- 已读取文档
- git status
- 当前分支
- 修改文件
- git diff --name-status
- diff 摘要
- commit hash
- PR URL
- 风险判断
- rollback 方案
- 未确认事项
```

## 6. Codex 回传模板

Codex 每次任务结束必须回传：

- 已读取文档。
- `git status`。
- 当前分支。
- 执行命令结果。
- 修改文件。
- diff 摘要。
- commit hash。
- PR URL。
- 风险判断。
- rollback 方案。
- 未确认事项。

## 7. 常见错误

- 把旧对话临时结论当成 Rule。
- 新对话未读取项目治理文档就生成指令。
- ChatGPT 未在 Codex 指令前完成任务级预审批。
- Codex 指令没有写清敏感命令、用途、授权边界和失败处理。
- 把 `gh` / `git` 命令混在一个大步骤里。
- 被审批层拒绝后反复执行。
- 忘记区分 `main` / `develop`。
- 忘记 production 前再次确认。

## 8. 当前项目的新对话启动指令

当前项目新对话建议直接从“ChatGPT 新对话启动模板”开始，并补齐以下事实：

- 当前 repo：`larissa2022/nikki-calculator`
- 当前环境映射：`main = production`，`develop = development / preview`
- 当前治理入口：
  - `docs/ai/RULES.md`
  - `docs/ai/CURRENT_TASK.md`
  - `docs/ai/WORKFLOWS.md`
  - `docs/ai/CONVERSATION_HANDOFF.md`
  - `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`
  - `docs/database/环境信息.md`
  - `docs/FILE_GOVERNANCE.md`
- 当前任务需要说明是否 docs-only、是否涉及 production、是否需要 Codex 直接执行。
