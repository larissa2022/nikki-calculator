# Lessons

用途：记录项目协作中反复出现的经验、问题和改进线索。Lesson 不是强制规则，只是可复盘的经验记录。

## 记录格式

### Lesson: 标题

- 日期：
- 来源任务：
- 现象：
- 原因：
- 处理方式：
- 后续影响：
- Pattern Candidate：
- Rule Candidate：
- 状态：观察中 / 可复用 / 已转为 Rule Candidate / 已废弃

## 当前 Lessons

### Lesson: GitHub CLI 纳入治理工作流

- 日期：2026-07-03
- 来源任务：安装并验证 GitHub CLI，更新 PR / workflow 状态确认工作流
- 现象：PR 状态、`mergeable`、changed files 和 workflow 状态经常需要在合并前重复确认。只依赖页面人工查看或连接器回传，容易增加操作成本，也容易漏掉本地命令可复核的证据。
- 原因：本地 `gh` 能提高 PR 状态、`mergeable`、changed files 和 workflow 查询效率，但 `gh auth` / token 泄露、把 `gh pr merge` 当成默认动作、以及网络不可用都会带来治理风险。
- 处理方式：
  - PR 和 workflow 只读确认优先使用 `gh`，包括 `gh pr view`、`gh pr diff`、`gh pr list`、`gh run list`、`gh run view`。
  - `gh` 不可用时，回退到 GitHub 页面或 ChatGPT GitHub 连接器。
  - `gh pr merge` 必须在用户明确确认后才能执行，不得因为工具可用就默认合并。
  - `gh auth` token、验证码、授权链接和 keyring 信息不得写入仓库、文档、日志或 commit。
  - production 相关 merge 前必须再次确认用户授权、环境映射和 rollback。
- 后续影响：后续 PR 治理可以把 `gh` 作为优先只读检查工具，但合并权限、production 边界和 GitHub 事实源原则保持不变。
- Pattern Candidate：PR 发布前采用“gh 优先查询 -> git diff / changed files 交叉确认 -> 用户授权后才执行写操作”的工作流。
- Rule Candidate：暂无。
- 状态：可复用

### Lesson: AI + Codex + 双环境项目治理工作流复盘

- 日期：2026-07-03
- 来源任务：恢复分支与环境治理、拆分 develop -> main 发布、验证 Supabase development migration、Preview 管理员审核流程修复
- 现象：项目同时涉及 GitHub 分支、Vercel 部署、Supabase 双环境、数据库 migration、前端审核流程和 AI 协作规则。如果直接合并 develop 到 main，容易把未审计的业务代码、数据库变更或环境风险带入 production。
- 原因：`main = production`、`develop = development / preview` 的事实源曾被分支历史、PR 状态、Vercel / Supabase 绑定和文档状态打乱；同时 Codex 可能在没有明确边界时把文档、业务、数据库和配置变更混在一次提交中。
- 处理方式：
  - 先确立事实源：以 GitHub、Vercel、Supabase project ref 和 `docs/ai` / `docs/governance` 文档为准。
  - 角色分工：
    - 用户：最终决策者，确认生产操作、环境绑定、PR 合并和业务验收结果。
    - ChatGPT：整理任务、拆分风险、形成 Codex 指令和 PR 文案，不直接执行生产操作。
    - Codex：按任务边界执行文件修改、验证、commit / push，并回传 `git status`、命令结果、风险和 rollback。
  - AI / Codex 开始任务前先读 `docs/ai/RULES.md`、`docs/ai/CURRENT_TASK.md` 和 `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`。
  - 固定环境映射：`main = production`，`develop = development / preview`。
  - 只读盘点优先：任何治理、发布或数据库任务先做 `git status`、分支 / PR / 差异盘点，再决定是否修改。
  - develop -> main 前必须做差异分类：文档、业务代码、数据库 / Supabase、配置 / 构建。
  - 文档 / 业务 / 数据库 / 配置按风险拆 PR；高风险内容不得跟低风险文档治理混合发布。
  - migration 必须先在 development 验证，再考虑 production。
  - 已执行过的 migration 不原地改来期待远端重跑；如果需要修正，新增 patch migration。
  - 每一步必须回传：`git status`、关键命令结果、风险判断、rollback 方案和未确认事项。
- 后续影响：后续任何 develop -> main 发布都应先按此流程走，只在目标环境验证，发布前重新确认 Vercel / Supabase 绑定，并准备前端、migration 和数据一致性 rollback。
- Pattern Candidate：双环境项目发布前采用“事实源确认 -> 只读盘点 -> 分层审计 -> 环境内验证 -> 分风险 PR -> rollback 准备”的固定工作流。
- Rule Candidate：已同步到 `RULES.md` 的硬规则包括任务前阅读治理文档、develop -> main 只读审计、migration 先 dev 验证、已执行 migration 用 patch migration 修正、production 操作前确认环境绑定。
- 状态：可复用

### Lesson: 大模块开发前先拆阶段包

- 日期：2026-06-30
- 来源任务：整理积分、贡献者、重审池、报错修正的最小开发计划
- 现象：积分、贡献者、重审池、报错修正、陪审团和排行榜之间依赖很多，如果直接进入数据库和功能开发，容易一次性改动过大。
- 原因：这些模块同时影响正式库、pending 状态、用户衣柜、积分权益和管理员审核，产品口径仍有多项待确认。
- 处理方式：先把第一版目标、不做范围、依赖对象、用户确认点、开发风险和建议顺序写入需求、开发和技术实现文档。
- 后续影响：下一阶段可优先开发贡献者记录和积分流水，再逐步接入重审池和报错修正，陪审团和排行榜后置。
- Pattern Candidate：大型功能进入开发前，先做“阶段包任务”，把最小闭环、后置范围和暂停确认点写清楚。
- Rule Candidate：暂无。
- 状态：可复用
