# Rules

用途：记录已经生效或待审核的协作规则。正式 Rule 只能由用户本人批准，ChatGPT、Codex、Gemini 都不能自行批准正式 Rule。

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

Candidate Rule → Verified Pattern → Rule

- Candidate Rule：候选规则，来自任务、复盘、风险发现或用户反馈；不得作为正式执行依据。
- Verified Pattern：已验证模式，来自 Candidate Rule 的实际执行和事实验证；仍需用户确认。
- Rule：正式规则，来自 Verified Pattern + 用户确认；进入 Project Rules 或 Personal Rules 后生效。

禁止跳级：Candidate Rule 不得直接升级为 Rule。

## Candidate Cleanup Policy

- Candidate Rule 保留最多 10 条。
- 超过 10 条时，必须进入 Verified Pattern，或移入 Rejected Ideas 并从 Rule Candidates 移除。
- Candidate Rule 超过 30 天未验证时，自动标记为 stale。
- stale Candidate Rule 不自动删除，必须进入 Review Queue。
- Review Queue 每次复盘必须清理或升级：清理到 Rejected Ideas，或升级为 Verified Pattern。

## Pattern Registry

- Verified Pattern 必须有唯一编号，例如 `Pattern-01`、`Pattern-02`。
- Verified Pattern 必须基于至少 2 次 GitHub 可验证行为。
- Verified Pattern 不自动升级为 Rule，必须经用户确认后才能进入正式 Rule。
- Pattern 状态包括：
  - Active：当前仍适用。
  - Deprecated：已废弃但不删除，用于保留历史判断。
  - Superseded：已被新的 Pattern 或 Rule 替代。
- 每个 Pattern 必须记录来源说明，且来源至少包含 2 次 GitHub 可验证行为。
- 每个 Pattern 必须记录对应 Rule；如尚未升级为 Rule，则标记为“未升级”。

## Rule Evolution Log

记录 Candidate Rule → Verified Pattern → Rule 的转化历史。

每条记录必须包含：

- Candidate Rule 名称或摘要。
- Pattern 编号。
- Rule 归属位置：Project Rules 或 Personal Rules。
- 用户确认时间。
- GitHub commit reference；如果不存在，标记为“无”。

## Project Rules

项目级规则，用于约束本仓库开发、测试、数据库和文档协作。

- 不直接操作 production。
- production 写库脚本不放入可提交路径。
- 涉及数据库前必须确认 dev / prod 状态。
- 数据库任务必须先看数据库安全文档和变更记录。
- 文档收口任务不得顺手修改业务代码。

### 字段新增约束

- 除数据库设计阶段外，禁止 ChatGPT / Codex 随意提出或新增字段。
- 任何新增字段、枚举值、状态值、表字段、文档字段，必须先明确标注“需要审核”，并经用户确认后才能进入任务单。
- 不得为了完善方案自行扩展项目中未确认存在的字段。
- 字段相关规则必须以 `DECISIONS.md`、现有数据库结构、现有代码、用户明确确认内容为准。

### 陪审团制度

- 投票幂等性规则：同一用户同一审核项（user_id + audit_id）只能存在一条有效投票记录。
- 防重复提交处理机制：重复请求不得产生多条有效票；相同内容重复提交应忽略，不同内容重复提交按“不允许改票”规则拒绝或返回错误。
- 后端写入优先原则：后端写入为唯一真相，前端状态不可信。

## Personal Rules

用户个人偏好和协作习惯规则。

- 用户本人负责最终产品判断、功能审核、流程把控和产品测试。
- git commit 信息使用中文。

## Rule Candidates

待用户本人审核的候选规则。审核通过后才能移动到 Project Rules 或 Personal Rules。

暂无。
