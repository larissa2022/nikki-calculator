# 项目文档索引

本文档目录用于集中管理需求、开发计划、技术实现和数据库安全记录。

AI / Codex 开始任务前，按“默认必读 + 条件读取”进入，不再要求普通低风险任务默认读取所有治理文档。

默认必读：

- [AI 协作规则](ai/RULES.md)
- [当前任务](ai/CURRENT_TASK.md)
- [AI / Codex 操作手册](ai/WORKFLOWS.md)

条件读取：

- 涉及 `main` / production / release：读 [分支与环境治理规则](governance/BRANCH_ENVIRONMENT_POLICY.md)。
- 涉及 database / Supabase：读 [数据库环境信息](database/环境信息.md) 和 [数据库开发安全方案](database/数据库开发安全方案.md)。
- 涉及产品 / 技术口径：读 [AI 决策记录](ai/DECISIONS.md)。
- 新 ChatGPT 对话迁移：读 [对话迁移与交接](ai/CONVERSATION_HANDOFF.md)。
- 文档职责冲突：读 [文档文件治理盘点](FILE_GOVERNANCE.md)。
- 复盘 / 规则候选整理：读 [AI 协作复盘](ai/LESSONS.md)。

## 治理

| 文档 | 作用 |
| --- | --- |
| [分支与环境治理规则](governance/BRANCH_ENVIRONMENT_POLICY.md) | 规定 main / develop / feature 分支与 Vercel、Supabase 环境的对应关系 |
| [AI 协作规则](ai/RULES.md) | 宪法层：记录强规则、角色边界、门禁和安全边界 |
| [AI / Codex 操作手册](ai/WORKFLOWS.md) | 操作手册层：记录 PR 检查、docs-only、发布、GitHub CLI 和数据库工作流 |
| [对话迁移与交接](ai/CONVERSATION_HANDOFF.md) | 新 ChatGPT 对话启动、上下文迁移和 ChatGPT -> Codex 指令交接模板 |
| [当前任务](ai/CURRENT_TASK.md) | 记录当前任务状态和是否允许进入开发 |
| [AI 协作复盘](ai/LESSONS.md) | 复盘经验层：记录 AI / Codex / GitHub CLI / GitHub / Vercel / Supabase 协作中的可复用经验 |
| [文档文件治理盘点](FILE_GOVERNANCE.md) | 记录 docs 文件职责边界、入口关系、重复/过期位置和未确认事项 |

## 工作流入口

- 具体操作流程见 [AI / Codex 操作手册](ai/WORKFLOWS.md)。
- PR 状态、`mergeable`、changed files、workflow 查询和 `gh` 使用规范都在 `WORKFLOWS.md` 中维护。
- docs-only / 只读检查等低风险任务采用 Fast Lane：在任务级预审批和明确范围内连续执行，具体规则见 [AI / Codex 操作手册](ai/WORKFLOWS.md)。
- `RULES.md` 保留强规则和门禁；如果 `WORKFLOWS.md` 与 `RULES.md` 冲突，以 `RULES.md` 为准。
- 当前任务状态以 [当前任务](ai/CURRENT_TASK.md) 为准；历史执行流水不要作为当前任务事实源。
- 文件归属不清或入口重复时，先查看 [文档文件治理盘点](FILE_GOVERNANCE.md)。

## 需求与规划

| 文档 | 作用 |
| --- | --- |
| [产品设计书](requirements/产品设计书.md) | 记录产品定位、目标用户、核心场景、功能边界和优先级 |
| [需求文档](requirements/需求文档.md) | 记录业务规则、产品口径和需求风险 |
| [开发文档](planning/开发文档.md) | 记录开发阶段、暂停确认点和验收标准 |
| [技术实现文档](planning/技术实现文档.md) | 记录表结构、RPC、RLS、前端模块和测试方案 |
| [缺陷文档](planning/缺陷文档.md) | 记录已发现缺陷、影响范围、状态和建议修复方向 |
| [角色权限数字化迁移方案](planning/角色权限数字化迁移方案.md) | 记录 `profiles.role` 从字符串权限迁移到数字权限的安全方案 |
| [工作流优化方案](planning/工作流优化方案.md) | 记录缺陷分级、数据库安全命令和工作区收口规则 |

## 数据库

| 文档 | 作用 |
| --- | --- |
| [数据库开发安全方案](database/数据库开发安全方案.md) | 数据库开发门禁、备份、隔离、回滚和上线检查 |
| [数据库变更记录](database/数据库变更记录.md) | 每次 migration、RPC、RLS、数据修复的记录模板 |
| [数据库环境信息](database/环境信息.md) | Supabase production / development 项目信息 |
| [schema](database/schema.md) | 当前数据库表结构摘要 |
| [Supabase Review Setup](database/SUPABASE_REVIEW.md) | Supabase 审查上下文与常用命令 |

## 阅读策略

1. 默认先看 [AI 协作规则](ai/RULES.md)、[当前任务](ai/CURRENT_TASK.md)、[AI / Codex 操作手册](ai/WORKFLOWS.md)。
2. 再按任务类型补读上方“条件读取”文档。
3. 普通 docs-only / 只读检查任务，不默认读取所有治理、数据库、复盘和交接文档。
4. 涉及数据库前，必须补读 [数据库环境信息](database/环境信息.md) 和 [数据库开发安全方案](database/数据库开发安全方案.md)。
5. 每次数据库变更后，更新 [数据库变更记录](database/数据库变更记录.md)。
