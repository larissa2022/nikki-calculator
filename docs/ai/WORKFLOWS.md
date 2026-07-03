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

## 7. 回传模板

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
