# Review Prompt

用途：阶段复盘时使用，判断本阶段是否完成、是否有缺口、是否需要文档收口。

```text
请对当前阶段进行复盘。

输入材料：
- 当前任务单
- CODEX_REPORT.md
- TEST_CHECKLIST.md
- 相关需求 / 开发 / 缺陷文档
- git log

输出：
1. 本阶段完成了什么。
2. 哪些内容已经验证。
3. 哪些文档可能过期。
4. 哪些风险仍未解决。
5. 是否需要用户确认。
6. 是否产生 Lesson / Pattern / Rule Candidate。

注意：
- 不新增正式 Rule。
- 不替用户批准 Rule。
- 不提出超出当前阶段的复杂系统。
```

