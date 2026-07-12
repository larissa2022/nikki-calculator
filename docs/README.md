# 项目文档索引

本文件是给人查看的文档目录，不是 Codex 自动入口，也不维护另一套任务读取规则。

AI / Codex 的唯一自动启动入口是仓库根目录 [`AGENTS.md`](../AGENTS.md)。任务读取顺序、条件文档和启动回执均以 `AGENTS.md` 为准。

## 1. 核心执行文档

| 文档 | 唯一职责 | 不承担 |
| --- | --- | --- |
| [`AGENTS.md`](../AGENTS.md) | 自动入口、任务分类、读取路由、启动回执 | 长篇流程、产品决策、历史流水 |
| [项目强规则](ai/RULES.md) | 角色边界、强门禁、安全约束 | 具体命令、读取清单、临时任务状态 |
| [AI / Codex 工作流程](ai/WORKFLOWS.md) | 执行步骤、检查清单、验证、rollback、回传模板 | 正式 Rule、产品实现细节 |
| [当前任务看板](ai/CURRENT_TASK.md) | 当前活动任务、状态、边界、下一步和阻塞 | 长期规则、历史报告、累计流水 |
| [Final 决策记录](ai/DECISIONS.md) | 已确认的产品和技术口径 | 待确认事项、临时推测、执行步骤 |

权威关系：

1. 强门禁以 `RULES.md` 为准。
2. 操作流程以 `WORKFLOWS.md` 为准。
3. 当前任务以 `CURRENT_TASK.md` 为准。
4. 产品与技术 Final 口径以 `DECISIONS.md` 为准。
5. 读取路由只在 `AGENTS.md` 中维护。

## 2. 条件业务文档

| 文档 | 何时使用 |
| --- | --- |
| [产品设计书](requirements/产品设计书.md) | 新模块、产品定位、目标用户或功能边界变化 |
| [需求文档](requirements/需求文档.md) | 新需求、业务规则、产品风险和待确认事项 |
| [开发文档](planning/开发文档.md) | 将已确认需求拆成阶段、暂停点和验收标准 |
| [技术实现文档](planning/技术实现文档.md) | 跨模块、RPC、RLS、schema 或测试方案设计 |
| [缺陷文档](planning/缺陷文档.md) | 已复现缺陷、影响、状态和修复方向 |
| [测试清单](ai/TEST_CHECKLIST.md) | Preview / production 人工回归或专项验证 |

需求文档不等于执行单；未确认事项不得直接进入实现。大型业务任务通常按“Final 决策 → 需求 → 开发计划 → 技术实现 → 代码”的顺序核对，但实际读取范围仍由 `AGENTS.md` 根据任务路由。

## 3. 分支、环境与数据库

| 文档 | 何时使用 |
| --- | --- |
| [分支与环境治理](governance/BRANCH_ENVIRONMENT_POLICY.md) | `main`、production、release、hotfix |
| [数据库环境信息](database/环境信息.md) | Supabase project ref 和非敏感环境事实 |
| [数据库开发安全方案](database/数据库开发安全方案.md) | 数据库备份、development 验证、上线与 rollback |
| [数据库变更记录](database/数据库变更记录.md) | migration、RPC、RLS、数据修复执行记录 |
| [schema 摘要](database/schema.md) | 数据库结构相关任务 |
| [Supabase Review](database/SUPABASE_REVIEW.md) | 专项 Supabase 审查背景和命令 |

所有 database / Supabase 任务都进入 Strict Lane；不能只凭本目录索引直接执行 SQL 或 migration。

## 4. 复盘、职责与历史材料

| 文档 | 定位 |
| --- | --- |
| [协作复盘](ai/LESSONS.md) | Lesson、Pattern Candidate、Rule Candidate；不是执行规则 |
| [文档职责盘点](FILE_GOVERNANCE.md) | 文件职责冲突或文档收口时参考；普通任务不前置读取 |
| [对话交接模板](ai/CONVERSATION_HANDOFF.md) | 当前仍为 ChatGPT → Codex 执行单模板；Phase 2 再评估合并或删除 |
| [Codex 历史报告](ai/CODEX_REPORT.md) | 历史归档参考，不是当前任务事实源 |
| [Token 使用审计](ai/TOKEN_USAGE_AUDIT.md) | 一次性审计证据，不是任务入口 |
| [Rejected Ideas](ai/REJECTED_IDEAS.md) | 当前低频记录；Phase 2 再评估并入 `LESSONS.md` |

这些文件不会因为存在于仓库中而自动生效，也不应作为普通任务默认上下文。

## 5. 当前阶段

Phase 1 只收口核心入口和职责，不删除历史文件。待核心入口验证稳定后，再单独执行 Phase 2：合并重复模板、迁移归档报告、删除确认无引用的空壳文件。