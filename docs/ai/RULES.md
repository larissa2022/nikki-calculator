# Rules

用途：记录已经生效或待审核的协作规则。正式 Rule 只能由用户本人批准，ChatGPT、Codex、Gemini 都不能自行批准正式 Rule。

## Rule 审核机制

- 用户本人是最终决策者。
- 用户本人是正式 Rule 的唯一批准者。
- ChatGPT 只能提出 Lesson、Pattern、Rule Candidate。
- Codex 只能按已批准 Rule 和当前任务单执行。
- Gemini 可用于挑战方案、发现盲点和提出反例，但不能批准 Rule。
- 未经用户本人明确确认的规则，只能放在 Rule Candidates。

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

## Rule Candidates

待用户本人审核的候选规则。审核通过后才能移动到 Project Rules 或 Personal Rules。

### Candidate: AIOS 轻量协作边界

- 提出来源：AIOS v1.1 初始化
- 候选内容：ChatGPT 负责整理任务、写任务单、判断下一步；Codex 负责按任务单执行；Gemini 负责 challenge；用户本人负责最终审核和批准。
- 待审核原因：需要用户确认是否作为长期协作规则。
- 状态：待用户审核

