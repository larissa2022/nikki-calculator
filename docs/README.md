# 项目文档索引

本文件是给人查看的文档目录和文件职责地图，不是 Codex 自动入口，也不维护另一套任务读取规则。

AI / Codex 的唯一自动启动入口是仓库根目录 [`AGENTS.md`](../AGENTS.md)。任务读取顺序、条件文档、连续执行和启动回执均以 `AGENTS.md` 为准。

## 1. 核心执行文档

| 文档 | 唯一职责 | 不承担 |
| --- | --- | --- |
| [`AGENTS.md`](../AGENTS.md) | 自动入口、任务分类、读取路由、连续批次和启动回执 | 长篇流程、产品决策、历史流水 |
| [项目强规则](ai/RULES.md) | 角色边界、强门禁、安全约束 | 具体命令、读取清单、临时任务状态 |
| [AI / Codex 工作流程](ai/WORKFLOWS.md) | 执行步骤、检查清单、执行单、验证、rollback、回传模板 | 正式 Rule、产品实现细节 |
| [当前业务看板](ai/CURRENT_TASK.md) | 业务目标、技术目标、当前阶段、最近完成、下一步任务、阻塞与待确认 | Git 操作步骤、PR 状态流水、新任务启动教程、长期历史 |
| [Final 决策记录](ai/DECISIONS.md) | 已确认的产品和技术口径 | 待确认事项、临时推测、执行步骤 |

权威关系：

1. 读取路由和执行节奏只在 `AGENTS.md` 中维护。
2. 强门禁以 `RULES.md` 为准。
3. 操作流程以 `WORKFLOWS.md` 为准。
4. 当前业务状态与下一步以 `CURRENT_TASK.md` 为准。
5. 产品与技术 Final 口径以 `DECISIONS.md` 为准。

每次项目任务完成回传都必须附上 `CURRENT_TASK.md` 链接，并确保回复中的下一步与看板一致。

## 2. 需求、规划与验证

| 文档 | 使用场景 | 不承担 |
| --- | --- | --- |
| [产品设计书](requirements/产品设计书.md) | 产品定位、目标用户、核心场景、功能边界 | Codex 执行步骤、数据库实现 |
| [需求文档](requirements/需求文档.md) | 需求背景、业务规则、风险、待确认事项 | 未确认事项的直接实现 |
| [开发文档](planning/开发文档.md) | 将已确认需求拆成阶段、暂停点和验收标准 | Final 决策、具体 SQL / RPC 实现 |
| [技术实现文档](planning/技术实现文档.md) | 跨模块、RPC、RLS、schema、前端模块和测试方案 | 需求源头、未经确认的产品规则 |
| [缺陷文档](planning/缺陷文档.md) | 已复现缺陷、影响、状态和修复方向 | 新需求设计、当前任务事实源 |
| [测试清单](ai/TEST_CHECKLIST.md) | Preview / production 人工回归或专项验证 | 自动生效的发布许可 |

需求文档不等于执行单；未确认事项不得直接进入实现。大型业务任务通常按“Final 决策 → 需求 → 开发计划 → 技术实现 → 代码”的顺序核对，但实际读取范围仍由 `AGENTS.md` 根据任务路由。

## 3. 分支、环境与数据库

| 文档 | 使用场景 | 不承担 |
| --- | --- | --- |
| [分支与环境治理](governance/BRANCH_ENVIRONMENT_POLICY.md) | `main`、production、release、hotfix | 具体 git / gh 命令 |
| [数据库环境信息](database/环境信息.md) | Supabase project ref 和非敏感环境事实 | 密钥、token、真实用户隐私数据 |
| [数据库开发安全方案](database/数据库开发安全方案.md) | 数据库备份、development 验证、上线与 rollback | 当前业务任务状态 |
| [数据库变更记录](database/数据库变更记录.md) | migration、RPC、RLS、数据修复执行记录 | 未执行规划、未经确认设计 |
| [schema 摘要](database/schema.md) | development 数据库结构相关任务 | production 实时事实 |
| [Supabase Review](database/SUPABASE_REVIEW.md) | 专项 Supabase 审查背景和命令 | 默认数据库执行入口 |

所有 database / Supabase 任务都进入 Strict Lane；不能只凭本目录索引直接执行 SQL 或 migration。

## 4. 复盘与历史材料

| 文档 | 定位 |
| --- | --- |
| [协作复盘](ai/LESSONS.md) | Lesson、Pattern Candidate、Rule Candidate 和未采纳方案；不是执行规则 |
| [历史归档](archive/README.md) | 已结束报告和一次性审计；仅供追溯，不参与当前任务 |

历史材料不会因为存在于仓库中而自动生效。`docs/archive/**` 中的“当前”“下一步”“待确认”只代表记录当时，不得直接交给 Codex 执行。

## 5. 已收口的旧入口

以下职责已合并，不再保留独立文件：

- ChatGPT → Codex 执行单：并入 `docs/ai/WORKFLOWS.md`。
- 文档职责地图：并入本文件。
- Rejected Ideas：并入 `docs/ai/LESSONS.md`。
- Codex 历史报告与 Token 使用审计：迁入 `docs/archive/**`。

后续新增文档前，应先判断现有文件能否承担职责，避免重新形成多个入口。