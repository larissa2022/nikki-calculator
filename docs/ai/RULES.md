# Rules

用途：记录已经生效或待审核的协作规则。`RULES.md` 是宪法层，只保存强规则、角色边界、门禁和安全边界；具体操作流程放在 [`WORKFLOWS.md`](WORKFLOWS.md)。若 `WORKFLOWS.md` 与本文件冲突，以本文件为准。

正式 Rule 只能由用户本人批准，ChatGPT、Codex、Gemini 都不能自行批准正式 Rule。

## Core Governance Layer

### Core Governance Rules

- 用户本人是最终决策者，也是正式 Rule 的唯一批准者。
- GitHub 是唯一事实源；未 push = 不存在。
- ChatGPT 负责整理任务、写任务单、判断下一步，但不得直接生成正式 Rule。
- ChatGPT 只能输出 Candidate Rule、Verified Pattern 或 Rule Proposal。
- Codex 负责按当前任务单和已批准 Rule 执行。
- Gemini 负责 challenge、发现反例和风险，不批准规则。
- Rule 只能来自 Verified Pattern + 用户确认。
- 禁止 ChatGPT 单轮升级规则。
- 禁止未验证设计进入 Rule。
- 遇到需求风险、规则冲突、字段缺失或会改变用户行为的地方，先暂停并向用户确认。

### Rule Gate

一条规则进入正式 Rule 前，必须同时满足：

- GitHub 已 push。
- Codex 已执行。
- 用户已确认。

说明：重复行为验证可作为形成 Verified Pattern 的依据，但不作为独立强制门槛。

## Rule System v2.1

保留三层结构，升级路径固定为：

Candidate Rule -> Verified Pattern -> Rule

- Candidate Rule：候选规则，来自任务、复盘、风险发现或用户反馈；不得作为正式执行依据。
- Verified Pattern：已验证模式，来自 Candidate Rule 的实际执行和事实验证；仍需用户确认。
- Rule：正式规则，来自 Verified Pattern + 用户确认；进入 Project Rules 或 Personal Rules 后生效。

禁止跳级：Candidate Rule 不得直接升级为 Rule。

## Rule Pollution Guard（规则防污染机制）

- `RULES.md` 只能包含跨项目稳定原则、强边界、门禁和安全约束。
- 具体 git / gh 命令、PR 检查步骤、commit / push / PR 创建流程、rollback 回传模板和每一步回传格式，必须放入 [`WORKFLOWS.md`](WORKFLOWS.md)。
- 禁止将以下内容写入 `RULES.md`：
  - 具体数据库结构（如 user_id + audit_id）。
  - 具体业务流程实现。
  - 单项目功能规则（积分、陪审团、投票逻辑）。
  - 可随工具变化迭代的操作手册。
- 所有实现细节必须进入 `DECISIONS.md`、`WORKFLOWS.md` 或项目实现层。
- ChatGPT / Codex 不得将实现方案升级为 Rule，除非用户明确确认且跨项目适用。

## Fact Rebuildability Principles（事实可重算原则）

- 所有核心系统必须满足“事实可重算”。
- 不允许依赖可变状态存储最终结果。
- 所有关键行为必须写入不可变日志（ledger 思维）。
- 系统应优先采用“事件记录”而非“状态覆盖”。
- 核心数据必须可重算（Reconstructable State Principle）。
- 不得仅依赖最终状态存储业务结果。
- 核心业务数据必须具备数据库层约束（唯一性 / 不可变性 / 状态合法性）。
- 不可仅依赖应用层逻辑保证一致性。

## Project Rules

项目级规则，用于约束本仓库开发、测试、数据库和文档协作。

- 分支与环境治理以 [`docs/governance/BRANCH_ENVIRONMENT_POLICY.md`](../governance/BRANCH_ENVIRONMENT_POLICY.md) 为准。
- 具体执行流程以 [`docs/ai/WORKFLOWS.md`](WORKFLOWS.md) 为操作手册；若流程与本文件冲突，以本文件为准。
- 任务开始前必须读取 `docs/ai/RULES.md`、`docs/ai/CURRENT_TASK.md`、`docs/governance/BRANCH_ENVIRONMENT_POLICY.md`、`docs/ai/WORKFLOWS.md`。
- `main` 只对应 production。
- `develop` 只对应 development / preview。
- 不允许直接从 `feature/*`、`fix/*`、`docs/*` 合入 `main`，除非是明确批准的紧急 hotfix。
- `develop -> main` 前必须做只读差异审计，并按文档 / 业务 / 数据库 / 配置分类。
- 文档 / 业务 / 数据库 / 配置变更应按风险拆分 PR；高风险内容不得混入低风险文档 PR。
- GitHub CLI（`gh`）可作为 PR 和 workflow 状态确认工具，但 GitHub 事实源和用户确认门禁不变。
- `gh pr merge` 属于写操作，必须在用户明确确认后才能执行。
- `gh auth` token、验证码、授权链接、keyring 信息不得写入仓库、文档、日志或 commit。
- 数据库相关任务必须先确认 Supabase project ref。
- 数据库 migration 必须先在 development 验证。
- 已执行过的 migration 如需修正，必须新增 patch migration。
- Vercel production 只能跟 `main` 对应。
- Vercel preview / dev 只能跟 `develop` 或短期 feature 分支对应。
- 不直接操作 production。
- production 操作前必须重新确认 Vercel / Supabase 环境绑定。
- production 相关 merge 前必须再次获得用户确认。
- production 写库脚本不放入可提交路径。
- 涉及数据库前必须确认 dev / prod 状态。
- 数据库任务必须先看数据库安全文档和变更记录。
- 文档收口任务不得顺手修改业务代码。

### 需求源门禁

- 涉及业务规则、产品口径、用户行为、数据库结构、权限边界或既有功能语义变化的任务，在进入实现前，必须先确认事实源与决策层级。
- 若仓库已有需求、决策、规划或技术实现文档，必须优先读取并对齐；用户口头描述只能作为补充上下文，不得单独作为实现依据。
- 已确认规则、待确认事项、历史规划、执行计划和技术实现必须分层处理；不得将待确认事项或临时推测直接写入 `DECISIONS.md`、任务单或代码实现。
- 进入 Codex 修改阶段前，必须先列出目标、依据、范围、风险分类、未确认事项、验证方式和 rollback；涉及未确认产品口径、字段、状态值、权限边界或数据安全时，必须暂停并取得用户确认。

### 字段新增约束

- 除数据库设计阶段外，禁止 ChatGPT / Codex 随意提出或新增字段。
- 任何新增字段、枚举值、状态值、表字段、文档字段，必须先明确标注“需要审核”，并经用户确认后才能进入任务单。
- 不得为了完善方案自行扩展项目中未确认存在的字段。
- 字段相关规则必须以 `DECISIONS.md`、现有数据库结构、现有代码、用户明确确认内容为准。

## Candidate / Pattern Governance

以下内容保留原则性约束；具体复盘、登记和清理动作可放入 [`WORKFLOWS.md`](WORKFLOWS.md) 或 `LESSONS.md`。

### Candidate Cleanup Policy

- Candidate Rule 保留最多 10 条。
- 超过 10 条时，必须进入 Verified Pattern，或移入 Rejected Ideas 并从 Rule Candidates 移除。
- Candidate Rule 超过 30 天未验证时，标记为 stale。
- stale Candidate Rule 不自动删除，必须进入 Review Queue。

### Pattern Registry

- Verified Pattern 必须有唯一编号，例如 `Pattern-01`、`Pattern-02`。
- Verified Pattern 必须基于至少 2 次 GitHub 可验证行为。
- Verified Pattern 不自动升级为 Rule，必须经用户确认后才能进入正式 Rule。
- Pattern 状态包括 Active、Deprecated、Superseded。
- 每个 Pattern 必须记录来源说明、对应 Rule 或“未升级”状态。

### Rule Evolution Log

记录 Candidate Rule -> Verified Pattern -> Rule 的转化历史。每条记录必须包含：

- Candidate Rule 名称或摘要。
- Pattern 编号。
- Rule 归属位置：Project Rules 或 Personal Rules。
- 用户确认时间。
- GitHub commit reference；如果不存在，标记为“无”。

## Personal Rules

用户个人偏好和协作习惯规则。

- 用户本人负责最终产品判断、功能审核、流程把控和产品测试。
- git commit 信息使用中文。

## Rule Candidates

待用户本人审核的候选规则。审核通过后才能移动到 Project Rules 或 Personal Rules。

暂无。
