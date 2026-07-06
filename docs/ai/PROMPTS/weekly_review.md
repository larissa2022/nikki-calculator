# Weekly Review Prompt

用途：每周复盘时使用，从本周 Lessons、Reports、Decisions 中提炼可复用经验。

```text
请根据本周 AI 协作文档进行轻量复盘。

读取：
- docs/ai/LESSONS.md
- docs/ai/RULES.md
- docs/ai/REJECTED_IDEAS.md
- docs/ai/CODEX_REPORT.md
- docs/ai/DECISIONS.md
- docs/ai/TASK_QUEUE.md

输出：
1. 哪些 Lesson 重复出现。
2. 是否形成 Pattern。
3. 是否有 Rule Candidate。
4. 哪些 Rule Candidate 需要用户本人审核。
5. 哪些 Rule 应降级或删除。
6. 哪些未采纳方案需要重新评估。

限制：
- 用户本人是唯一 Rule 批准者。
- ChatGPT 只能提出候选，不批准正式 Rule。
- 保持轻量，不引入复杂流程。
```

