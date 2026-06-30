# Rules

用途：记录已经生效或待审核的协作规则。正式 Rule 只能由用户本人批准，ChatGPT、Codex、Gemini 都不能自行批准正式 Rule。

## Rule 审核机制

- 用户本人是最终决策者。
- 用户本人是正式 Rule 的唯一批准者。
- ChatGPT 只能提出 Lesson、Pattern、Rule Candidate。
- Codex 只能按已批准 Rule 和当前任务单执行。
- Gemini 可用于挑战方案、发现盲点和提出反例，但不能批准 Rule。
- 未经用户本人明确确认的规则，只能放在 Rule Candidates。

## Rule System v2

规则系统采用三层结构，禁止跳级：

1. Candidate Rule
   - 来源：一次任务、一次复盘、一次风险发现或一次用户反馈。
   - 状态：候选规则。
   - 限制：不得作为正式执行依据，只能用于后续观察和验证。

2. Verified Pattern
   - 来源：Candidate Rule 经重复行为验证后形成。
   - 状态：已验证模式。
   - 验证要求：同类行为至少重复 2~3 次，并能被 GitHub 提交、PR、文档记录或用户测试结果支持。
   - 限制：仍不是正式 Rule，必须等待用户确认。

3. Rule
   - 来源：Verified Pattern + 用户本人确认。
   - 状态：正式规则。
   - 作用：进入 Project Rules 或 Personal Rules，作为后续 Codex、ChatGPT、Gemini 协作的执行依据。

升级路径：

Candidate Rule → Verified Pattern → Rule

禁止：

- 禁止 Candidate Rule 直接升级为 Rule。
- 禁止单轮讨论直接生成 Rule。
- 禁止未经验证的设计进入 Rule。

## Rule Gate

一条规则进入正式 Rule 前，必须通过以下强制验证：

- Codex 实现：规则相关行为已经由 Codex 在实际任务中执行。
- GitHub commit / push 验证：对应变更必须能在 GitHub 事实源中追踪；未 push 的内容不作为已完成事实。
- 重复行为验证：同类行为至少重复 2~3 次，确认不是偶发经验。
- 用户确认：用户本人明确批准后，才能进入 Project Rules 或 Personal Rules。

## ChatGPT Constraint v2

- ChatGPT 不得直接生成正式 Rule。
- ChatGPT 不得跳过验证生成规则。
- ChatGPT 只能输出 Candidate、Pattern 或 Rule Proposal。
- GitHub 是唯一事实源。
- 未 push = 不存在。
- Rule 只能来自 Verified Pattern + 用户确认。
- 禁止 ChatGPT 单轮升级规则。
- 禁止未验证设计进入 Rule。

## Project Rules

项目级规则，用于约束本仓库开发、测试、数据库和文档协作。

- 不直接操作 production。
- production 写库脚本不放入可提交路径。
- 涉及数据库前必须确认 dev/prod 状态。
- 数据库任务必须先看数据库安全文档和变更记录。
- 文档收口任务不得顺手修改业务代码。

## Personal Rules

用户个人偏好和协作习惯规则。

- 用户本人负责最终产品判断、功能审核、流程把控和产品测试。
- git commit 信息使用中文。
- 遇到需求风险、规则冲突、字段缺失或会改变用户行为的地方，先暂停并向用户确认。

### AIOS 轻量协作边界

- 来源：AIOS v1.1 初始化。
- 类型：Personal Rule。
- 批准人：用户本人。
- ChatGPT 负责整理任务、写任务单、判断下一步。
- Codex 负责按任务单执行。
- Gemini 负责 challenge、发现反例和风险。
- GitHub 是事实来源，用于确认提交、分支、PR、历史记录和代码变更状态。
- 用户本人负责最终审核、最终产品判断和正式 Rule 批准。

## Rule Candidates

待用户本人审核的候选规则。审核通过后才能移动到 Project Rules 或 Personal Rules。

暂无。
