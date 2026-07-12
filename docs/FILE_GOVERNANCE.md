# 文档文件治理盘点

本文档用于记录 docs-only 文件治理结果，说明 `docs/` 内核心文档的职责边界、入口关系和待收口事项。本文不是正式 Rule，不新增业务规则；如与 `docs/ai/RULES.md` 冲突，以 `RULES.md` 为准。

## 1. 文档入口

- 总入口：[`docs/README.md`](README.md)
- AI / Codex 治理入口：[`docs/ai/RULES.md`](ai/RULES.md)、[`docs/ai/WORKFLOWS.md`](ai/WORKFLOWS.md)、[`docs/ai/CURRENT_TASK.md`](ai/CURRENT_TASK.md)
- 分支与环境入口：[`docs/governance/BRANCH_ENVIRONMENT_POLICY.md`](governance/BRANCH_ENVIRONMENT_POLICY.md)
- 数据库环境入口：[`docs/database/环境信息.md`](database/环境信息.md)
- 文件职责参考：本文档；普通任务不作为前置必读

## 2. 核心文档职责

| 文件 | 职责 | 不承载内容 |
| --- | --- | --- |
| `docs/ai/RULES.md` | 已批准的强规则、角色边界、门禁和安全边界 | 具体命令、PR 操作步骤、临时任务状态、未经确认的新 Rule |
| `docs/ai/WORKFLOWS.md` | 操作手册、命令顺序、检查清单、回传模板 | 正式 Rule、业务实现细节、数据库结构决策 |
| `docs/ai/CURRENT_TASK.md` | 当前任务状态、当前允许/禁止范围、下一步状态 | 长期规则、历史流水、完整报告 |
| `docs/ai/CONVERSATION_HANDOFF.md` | 新对话迁移、ChatGPT -> Codex 指令模板 | 正式 Rule、长期事实源、业务实现方案 |
| `docs/ai/LESSONS.md` | 复盘经验、Pattern Candidate、Rule Candidate 线索 | 已批准规则、最终产品决策 |
| `docs/ai/DECISIONS.md` | 已确认的产品与技术决策 | 未确认事项、临时推测、执行流水 |
| `docs/ai/CODEX_REPORT.md` | 历史执行报告 / 归档参考 | 当前任务事实源、正式 Rule、未确认事项的执行依据 |
| `docs/requirements/产品设计书.md` | 需求层：产品定位、目标用户、核心场景、功能边界和优先级 | 具体执行计划、数据库结构方案、当前任务状态 |
| `docs/requirements/需求文档.md` | 需求层：需求背景、业务规则、产品口径、风险和待确认事项 | Codex 直接执行步骤、Final 决策、未经确认的技术实现 |
| `docs/planning/开发文档.md` | 执行计划层：承接已确认需求，记录开发阶段、暂停点、验收标准和拆分顺序 | Final 决策、未经确认需求、具体 SQL / RPC 实现细节 |
| `docs/planning/技术实现文档.md` | 技术实现层：基于已确认执行计划记录表结构、RPC、RLS、前端模块和测试方案 | 需求源头、Final 决策、未经确认需求的直接实现 |
| `docs/planning/缺陷文档.md` | 缺陷事实层：记录已复现或高度可信的缺陷、影响、状态和修复方向 | 新需求设计、Final 决策、当前任务事实源 |
| `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` | 分支与环境映射、发布门禁 | 具体 git / gh 操作步骤 |
| `docs/database/环境信息.md` | Supabase 环境非敏感信息、project ref 与本地连接建议 | 密钥、token、真实用户隐私数据 |
| `docs/database/数据库开发安全方案.md` | 数据库开发安全流程、备份、回滚和上线检查 | 当前任务状态、业务功能开发计划 |
| `docs/database/数据库变更记录.md` | migration、RPC、RLS、数据修复记录 | 未执行的业务规划、未经确认的字段设计 |
| `docs/database/schema.md` | development schema 摘要 | production 实时事实、密钥、临时任务状态 |

## 3. 本次盘点结论

- 不新增 `docs/ai/DOCUMENT_MAP.md`：当前文件已能承担文件职责参考，新增入口会增加重复和读取负担。
- `docs/README.md` 作为总入口，应采用“默认必读 + 条件读取”，避免普通 docs-only / 只读任务默认读取所有治理文档。
- `docs/FILE_GOVERNANCE.md` 作为文档职责参考，只在文件职责冲突、文档收口或入口归属判断时读取，不作为普通任务前置必读。
- `docs/ai/CONVERSATION_HANDOFF.md` 仅在新 ChatGPT 对话迁移或交接时读取。
- `docs/ai/LESSONS.md` 仅在复盘、Pattern Candidate 或 Rule Candidate 整理时读取。
- `docs/ai/WEEKLY_REVIEW.md` 和 `docs/ai/PROMPTS/**` 已作为低使用模板移除；后续复盘模板和 prompt 线索统一收口到 `docs/ai/LESSONS.md`。
- `docs/ai/CODEX_REPORT.md` 包含大量历史执行结果，适合作为报告归档，不适合作为当前任务事实源。
- `docs/ai/DECISIONS.md` 已承载较多 Final 决策，应继续保持 Final Only，不把待确认事项或临时推测写入其中。
- `docs/requirements/**` 属于需求层，负责说明为什么要做、要解决什么问题、哪些事项待确认；需求文档本身不等于 Codex 执行计划。
- `docs/planning/开发文档.md` 属于执行计划层，负责把已确认需求拆成阶段、暂停点和验收标准；未确认需求不能直接从这里进入开发。
- `docs/planning/技术实现文档.md` 属于技术实现层，负责在执行计划确认后描述表结构、RPC、RLS、前端模块和测试方案；不得绕过需求确认直接承接口头需求。
- `docs/database/环境信息.md` 与 `docs/database/数据库开发安全方案.md` 都涉及环境安全；前者记录当前非敏感环境事实，后者记录数据库安全流程。两者职责可区分，不需要合并；仅在 database / Supabase 任务中前置读取。
- `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` 与 `docs/ai/WORKFLOWS.md` 存在交叉引用但职责清晰：前者定义分支 / 环境映射，后者定义执行流程。

## 4. 收口建议

- 新任务开始时优先从 `docs/README.md` 进入，默认读取 `docs/ai/RULES.md`、`docs/ai/CURRENT_TASK.md`、`docs/ai/WORKFLOWS.md`，再按任务类型补读 governance、database、handoff、lessons 或文件治理文档。
- 当前任务状态只写入 `docs/ai/CURRENT_TASK.md`，不要写入 `CODEX_REPORT.md` 或 `RULES.md`。
- 操作步骤、命令清单、回传模板继续写入 `docs/ai/WORKFLOWS.md`。
- 复盘经验、轻量复盘模板和 prompt 线索继续写入 `docs/ai/LESSONS.md`，除非用户明确确认，不升级为正式 Rule。
- 已确认的产品与技术口径写入 `docs/ai/DECISIONS.md`；待确认事项保持在任务单、报告、需求文档或规划文档中。
- 未确认事项不能写入 `docs/ai/DECISIONS.md`，也不能直接进入 Codex 修改阶段；必须先完成用户确认和执行计划拆分。
- 本次只调整文档职责与读取策略，不新增正式 Rule。

## 5. 未确认事项

- `docs/database/数据库开发安全方案.md` 后续如环境事实变化，应同步 `docs/database/环境信息.md`。
- `docs/ai/CODEX_REPORT.md` 已明确为历史执行报告 / 归档参考；是否进一步拆分为归档目录或按日期归档，需用户后续单独确认。
- 暂不新增 `docs/ai/DOCUMENT_MAP.md`：当前 `docs/FILE_GOVERNANCE.md` 可以承载文件职责参考，新增更细入口可能造成重复。若后续 `docs/ai` 文件继续扩张，再单独评估。
- 暂不删除 `docs/ai/REJECTED_IDEAS.md`：该文件仍与 `RULES.md` 中的 Rejected Ideas 机制有关，删除前需要单独评估是否修改规则层。

## 6. 2026-07-12 文档审计结论

### 当前在用入口

- 默认入口：`docs/README.md`、`docs/ai/RULES.md`、`docs/ai/WORKFLOWS.md`、`docs/ai/CURRENT_TASK.md`。
- 对话交接：`docs/ai/CONVERSATION_HANDOFF.md`。
- 产品与技术口径：`docs/ai/DECISIONS.md`、`docs/requirements/**`、`docs/planning/开发文档.md`、`docs/planning/技术实现文档.md`。
- 缺陷和回归：`docs/planning/缺陷文档.md`、`docs/ai/TEST_CHECKLIST.md`。
- 数据库任务：`docs/database/环境信息.md`、`docs/database/数据库开发安全方案.md`、`docs/database/数据库变更记录.md`、`docs/database/schema.md`。

### 条件读取或历史保留

- `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`：仅涉及 main、production、release 时读取。
- `docs/database/SUPABASE_REVIEW.md`：Supabase 审查和 contributions / points 草案复核时读取。
- `docs/planning/角色权限数字化迁移方案.md`：未来权限迁移方案，production 未执行，不作为当前实现事实。
- `docs/planning/seal100x-clothes-sync-plan.md`：已完成同步任务的历史计划，后续只作为审计背景读取。
- `docs/ai/CODEX_REPORT.md`：历史执行报告，不作为当前状态来源。
- `docs/ai/LESSONS.md`、`docs/ai/REJECTED_IDEAS.md`：复盘和规则候选机制，低频条件读取；即使内容暂时为空也保留入口职责。

### 本次合并或删除

- `docs/planning/工作流优化方案.md`：有效内容已合并到 `docs/ai/WORKFLOWS.md` 2.2 节，原文件删除。
- `docs/ai/TASK_QUEUE.md`：空壳文件，已删除。
- `docs/ai/TOKEN_AUDIT_2026-07-12.md`：一次性报告已由长期版 `docs/ai/TOKEN_USAGE_AUDIT.md` 替代，不保留重复入口。

### SQL 文件边界

- `docs/database/dev_test_data.sql` 和 `docs/database/local-only/**` 仅用于 development / 本地审计，不能当作默认工作流或 production 脚本。
- `docs/database/read-only/生产pending盘点.sql` 是只读 production 盘点工具，执行前仍需 Strict Lane 环境确认。
- `docs/database/local-only/production_pending_batch_20260628.sql` 是历史 production 写入草案，只能作为审计材料，禁止按当前任务直接执行。
