# Workflows

## 0. 用途

本文档是操作手册层，记录可迭代流程、命令顺序、检查清单和回传模板；不等同于正式 Rule。若本文件与 [`RULES.md`](RULES.md) 冲突，以 `RULES.md` 为准。

`RULES.md` 是宪法层，`WORKFLOWS.md` 是操作手册层，`LESSONS.md` 是复盘经验层，`BRANCH_ENVIRONMENT_POLICY.md` 是分支 / 环境治理层，`CURRENT_TASK.md` 是当前任务状态层。

## 1. 任务开始流程

1. 读取必要文档：
   - `docs/ai/RULES.md`
   - `docs/ai/CURRENT_TASK.md`
   - `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`
   - `docs/ai/WORKFLOWS.md`
   - 涉及数据库或环境时读取 `docs/database/环境信息.md`
2. 执行本地只读盘点：
   - `git status`
   - `git branch --show-current`
   - 需要远端事实时执行 `git fetch origin`
3. 确认任务边界：
   - 允许修改范围
   - 禁止修改范围
   - 是否涉及 `main` / production
   - 是否涉及数据库 / Supabase / Vercel
4. 如出现规则冲突、字段缺失、生产风险或会改变用户行为的内容，暂停并向用户确认。

## ChatGPT 预审批与 Codex 连续执行流程

本流程用于减少 docs-only 任务中不必要的执行中断。敏感命令的风险说明和授权边界，应优先在 ChatGPT 生成 Codex 指令前完成；Codex 收到用户已确认的任务级授权后，应在授权范围内连续执行。

核心规则：

1. ChatGPT 负责在发送 Codex 指令前完成任务级预审批：
   - 明确任务目标。
   - 明确允许修改范围。
   - 明确禁止范围。
   - 明确敏感命令清单。
   - 明确是否涉及 `main` / production / database / Supabase / Vercel。
   - 明确失败处理。
2. 用户在 ChatGPT 中确认后，Codex 应在授权范围内连续执行：
   - 不要在每个已授权命令前重复要求确认。
   - 不要把 docs-only 的 `git add` / `git commit` / `git push` 拆成多轮用户审批。
   - 不要因命令属于敏感命令就自动停止，前提是该命令已在 ChatGPT 指令中预审批。
3. Codex 必须停止的情况：
   - 审批层拒绝命令。
   - 命令执行失败。
   - 实际修改文件超出允许范围。
   - 当前分支或目标分支与指令不一致。
   - 出现 `main` / production / database / Supabase / Vercel 相关操作。
   - 需要修改 `RULES.md` 但用户未明确授权。
   - 需要 merge PR。
   - 需要删除分支。
   - 发现 rollback 不明确。
4. docs-only 标准授权模式：
   在 ChatGPT 指令已明确授权的情况下，Codex 可连续执行：
   - fetch / checkout / pull
   - 新建 docs 分支
   - 修改允许的 docs 文件
   - `git diff` 检查
   - `git add` 指定 docs 文件
   - `git commit`
   - `git push` 到该 docs 分支
   - `gh pr create` 到 `develop`
5. merge 仍需单独确认：
   - `gh pr merge` 永远不包含在普通 docs-only 自动授权中。
   - merge 前必须由用户再次明确确认。
   - `develop -> main` 必须单独审计和确认。
6. 审批层拒绝后的处理：
   - 立即停止。
   - 回传被拒绝的命令、错误信息、当前 `git status`。
   - 不重复执行。
   - 不改用其他命令绕过。
   - 不把失败命令拆成变体重试。

## 2. PR 只读检查流程

适用于 PR 合并前、发布前、风险审计前的只读确认。

1. 刷新远端：
   - `git fetch origin`
2. 查看远端差异：
   - `git diff --name-status base...head`
3. 使用 GitHub CLI 查询 PR：
   - `gh pr view <number> --repo <owner/repo> --json number,state,baseRefName,headRefName,mergeable,changedFiles,commits,url,files`
   - 当前 CLI 字段不支持 `merged` 时，可用 `mergedAt` 等价判断是否已合并。
4. 必要时查看 PR diff：
   - `gh pr diff <number> --repo <owner/repo>`
5. 将文件分类：
   - 文档
   - 业务代码
   - 数据库 / Supabase
   - 配置 / 构建
6. 判断风险：
   - 是否包含 `src/**`
   - 是否包含 `supabase/**`
   - 是否包含 migration
   - 是否包含 `package*.json` / `vite.config.*`
   - 是否包含 `.env*`
   - 是否包含 production 写库脚本
7. 回传 rollback 方案和未确认事项。

## 3. docs-only PR 流程

适用于只修改文档的工作流。

1. 从 `develop` 创建 docs 分支：
   - `git checkout develop`
   - `git pull origin develop`
   - `git checkout -b docs/<topic>`
2. 只修改明确允许的 `docs/**` 文件。
3. 禁止顺手修改：
   - `src/**`
   - `supabase/**`
   - migration
   - `package*.json`
   - `vite.config.*`
   - `.env*`
   - production 写库脚本
4. 提交前验证：
   - `git status`
   - `git diff --name-status`
   - `git diff`
5. 确认 diff 只包含允许的文档文件后再提交。
6. 暂存、提交、推送：
   - `git add <allowed docs files>`
   - `git commit -m "<中文提交信息>"`
   - `git push origin <docs-branch>`
7. 创建 PR 到 `develop`：
   - `gh pr create --repo <owner/repo> --base develop --head <docs-branch> --title "<标题>" --body "<PR body>"`
8. PR body 建议包含：
   - 概述
   - 变更范围
   - 风险说明
   - Rollback
9. merge 前仍需按 PR 只读检查流程确认。

## 4. develop -> main 发布流程

`main` 只对应 production，`develop` 只对应 development / preview。任何 `develop -> main` 发布都必须先完成只读审计和用户确认。

1. 刷新远端并确认 PR 状态。
2. 执行 `develop -> main` 只读差异审计。
3. 按文档 / 业务 / 数据库 / 配置分类。
4. 如果高风险内容混入低风险 PR，停止并建议拆分。
5. 确认 Vercel production 只对应 `main`。
6. 涉及数据库时确认 Supabase project ref、development 验证、备份和 rollback。
7. production 相关 merge 前必须获得用户明确确认。
8. 合并后只做观察和回传，不主动 rollback；rollback 需用户另行确认。

## 5. GitHub CLI 工作流

`gh` 是优先的本地 PR / workflow 状态确认工具，但不改变 GitHub 是事实源、用户是最终决策者的规则。

常用只读命令：

- `gh pr view`
- `gh pr diff`
- `gh pr list`
- `gh run list`
- `gh run view`

安全边界：

- `gh pr merge` 是写操作，必须用户明确确认后才能执行。
- production 相关 merge 前必须再次确认用户授权、环境映射和 rollback。
- `gh auth` token、验证码、授权链接、keyring 信息不得写入仓库、文档、日志或 commit。
- `gh` 不可用时，回退到 GitHub 页面或 ChatGPT GitHub 连接器。
- `gh` 查询结果必须和 `git diff` / PR changed files 一起判断，不能只凭单一工具合并。

## 6. 数据库相关工作流

数据库任务必须先确认环境和 project ref。

1. 读取：
   - `docs/database/环境信息.md`
   - `docs/database/数据库开发安全方案.md`
   - `docs/database/数据库变更记录.md`
2. 确认目标环境：
   - `develop` 对应 development / preview
   - `main` 对应 production
3. migration 必须先在 development 验证。
4. 已应用 migration 需要修正时，新增 patch migration，不原地修改期待远端重跑。
5. production 数据库操作需要：
   - 用户明确确认
   - 备份
   - development 验证记录
   - rollback 方案
   - project ref 再确认

## 7. 审批层高风险命令 Preflight

以下命令容易触发审批层拦截。这些分类用于 ChatGPT 生成 Codex 指令前的任务级预审批，不是让 Codex 在执行中反复询问。执行前应在 ChatGPT 指令中说明目的、是否只读、是否会修改远端或 production、是否需要用户确认。若已预先确认且仍在授权范围内，Codex 可继续执行；若被审批层拒绝，应立即停止，不反复重试，不换方式绕过。

### 7.1 网络 / 远端读取类

命令：

- `git fetch origin`
- `git pull origin <branch>`
- `gh pr view`
- `gh pr diff`
- `gh run list`
- `gh run view`

Preflight：

- 目的：刷新远端引用、读取 PR / diff / workflow 状态。
- 只读：通常是只读；但 `git pull origin <branch>` 会更新本地工作树和本地分支。
- 远端 / production 修改：不修改远端，不直接修改 production。
- 预审批：涉及网络访问或本地分支更新时，应在 ChatGPT 指令中说明用途和失败处理；若用户已确认任务范围，Codex 可在授权范围内继续执行。
- 被拒绝处理：立即停止，回传错误；不得反复重试或改用其他工具绕过。

### 7.2 本地写入 / 暂存 / 提交类

命令：

- `git add <path>`
- `git commit -m "..."`
- `git restore <path>`
- `git checkout -- <path>`

Preflight：

- 目的：暂存文档修改、创建本地提交，或丢弃指定路径的本地修改。
- 只读：不是只读。
- 远端 / production 修改：不修改远端，不直接修改 production。
- 本地影响：`git add` 虽然不修改文件内容，但会修改 Git 暂存区；`git commit` 会创建本地历史；`git restore` / `git checkout --` 会丢弃本地修改，属于潜在破坏性操作。
- 预审批：执行前必须在 ChatGPT 指令中说明目的、影响范围、是否只限 docs-only、rollback 方式；对已授权 docs-only 任务，`git add`、`git commit`、`git push` 应拆成明确步骤并分别回传结果，但不需要逐步重新请求用户确认。
- 命令边界：不要把 `git add`、`git commit`、`git push` 混在同一条复合命令里。
- 被拒绝处理：立即停止，回传错误；不得反复执行或换命令绕过。

### 7.3 远端写操作类

命令：

- `git push origin <branch>`
- `gh pr create`
- `gh pr merge`
- `gh pr close`
- `gh pr review`

Preflight：

- 目的：推送分支、创建 / 合并 / 关闭 / 审查 PR。
- 只读：不是只读。
- 远端 / production 修改：`git push origin <branch>` 属于 Git 远端写操作；`gh pr create` / `gh pr merge` 属于 GitHub 远端写操作；`gh pr merge` 合并到 `main` 时会影响 production 发布链路。
- 预审批：远端写操作必须在 ChatGPT 指令中明确目标 repo、base/head、操作类型和是否涉及 production；若用户已确认 docs-only 任务范围，`git push` 和 `gh pr create` 可连续执行。`gh pr merge` 必须单独明确确认。
- 被拒绝处理：立即停止，回传错误；不得用 GitHub 页面、连接器或其他命令绕过。

### 7.4 Git 历史改写 / 删除类

命令：

- `git reset --hard`
- `git clean -fd`
- `git rebase`
- `git push --force`
- `git push --force-with-lease`
- `git branch -D`

Preflight：

- 目的：改写历史、清理文件、强制推送或删除分支。
- 只读：不是只读。
- 远端 / production 修改：本地命令可能删除未提交内容；强制推送会改写远端历史，涉及 `main` 时会影响 production 链路。
- 预审批：必须在 ChatGPT 指令中逐项说明影响范围和 rollback；没有明确批准不得执行。
- 被拒绝处理：立即停止，回传错误；不得尝试等价破坏性命令。

### 7.5 数据库 / Supabase 类

命令：

- `supabase link`
- `supabase db push`
- `supabase migration up`
- `supabase db reset`
- `supabase functions deploy`
- `psql`

Preflight：

- 目的：切换 Supabase project、推送 schema / migration、重置数据库、部署函数或直接访问数据库。
- 只读：通常不是只读；`psql` 取决于执行语句，但仍视为高风险。
- 远端 / production 修改：可能修改 development 或 production 数据库 / functions；production 风险极高。
- 预审批：必须先在 ChatGPT 指令中确认 project ref、环境、备份、development 验证和 rollback；production 操作必须单独明确确认。
- 被拒绝处理：立即停止，回传错误；不得连接 production 或换用其他数据库入口绕过。

### 7.6 Vercel / production 类

命令：

- `vercel deploy`
- `vercel --prod`
- `vercel rollback`
- `vercel env add`
- `vercel env rm`

Preflight：

- 目的：部署、生产发布、回滚或修改 Vercel 环境变量。
- 只读：不是只读。
- 远端 / production 修改：可能修改 Vercel deployment、production 流量或环境变量。
- 预审批：必须在 ChatGPT 指令中明确目标 project、branch、environment、rollback 方案和是否 production；production 操作必须单独明确确认。
- 被拒绝处理：立即停止，回传错误；不得手动触发 Vercel 或改用其他入口绕过。

## 8. 回传模板

每一步或每个阶段完成后，优先回传：

- `git status`
- 当前分支
- 关键命令结果
- 修改文件范围
- 风险判断
- rollback 方案
- 未确认事项

rollback 回传建议写清：

- 未 merge 前：关闭 PR 或删除临时分支。
- 已 merge 文档 PR：revert merge commit。
- 涉及数据库时：说明是否需要数据库 rollback；无数据库变更时明确写“无数据库 rollback 需求”。
- 涉及 production 时：说明前端部署、数据库、数据一致性各自的 rollback 边界。

docs-only PR 最终回传建议包含：

- 已读取文档
- `git status`
- 当前分支
- 修改文件
- `git diff --name-status`
- 迁移 / 保留内容摘要
- commit hash
- PR URL
- 风险判断
- rollback 方案
- 未确认事项
