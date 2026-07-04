# 文档文件治理盘点

本文档用于记录 docs-only 文件治理结果，说明 `docs/` 内核心文档的职责边界、入口关系和待收口事项。本文不是正式 Rule，不新增业务规则；如与 `docs/ai/RULES.md` 冲突，以 `RULES.md` 为准。

## 1. 文档入口

- 总入口：[`docs/README.md`](README.md)
- AI / Codex 治理入口：[`docs/ai/RULES.md`](ai/RULES.md)、[`docs/ai/WORKFLOWS.md`](ai/WORKFLOWS.md)、[`docs/ai/CURRENT_TASK.md`](ai/CURRENT_TASK.md)
- 分支与环境入口：[`docs/governance/BRANCH_ENVIRONMENT_POLICY.md`](governance/BRANCH_ENVIRONMENT_POLICY.md)
- 数据库环境入口：[`docs/database/环境信息.md`](database/环境信息.md)
- 文件职责地图：本文档

## 2. 核心文档职责

| 文件 | 职责 | 不承载内容 |
| --- | --- | --- |
| `docs/ai/RULES.md` | 已批准的强规则、角色边界、门禁和安全边界 | 具体命令、PR 操作步骤、临时任务状态、未经确认的新 Rule |
| `docs/ai/WORKFLOWS.md` | 操作手册、命令顺序、检查清单、回传模板 | 正式 Rule、业务实现细节、数据库结构决策 |
| `docs/ai/CURRENT_TASK.md` | 当前任务状态、当前允许/禁止范围、下一步状态 | 长期规则、历史流水、完整报告 |
| `docs/ai/CONVERSATION_HANDOFF.md` | 新对话迁移、ChatGPT -> Codex 指令模板 | 正式 Rule、长期事实源、业务实现方案 |
| `docs/ai/LESSONS.md` | 复盘经验、Pattern Candidate、Rule Candidate 线索 | 已批准规则、最终产品决策 |
| `docs/ai/DECISIONS.md` | 已确认的产品与技术决策 | 未确认事项、临时推测、执行流水 |
| `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` | 分支与环境映射、发布门禁 | 具体 git / gh 操作步骤 |
| `docs/database/环境信息.md` | Supabase 环境非敏感信息、project ref 与本地连接建议 | 密钥、token、真实用户隐私数据 |
| `docs/database/数据库开发安全方案.md` | 数据库开发安全流程、备份、回滚和上线检查 | 当前任务状态、业务功能开发计划 |
| `docs/database/数据库变更记录.md` | migration、RPC、RLS、数据修复记录 | 未执行的业务规划、未经确认的字段设计 |
| `docs/database/schema.md` | development schema 摘要 | production 实时事实、密钥、临时任务状态 |

## 3. 本次盘点结论

- `docs/README.md` 已具备总入口职责，但此前缺少“文件职责地图”入口，容易让新任务在 `RULES.md`、`WORKFLOWS.md`、`CODEX_REPORT.md`、`CURRENT_TASK.md` 之间混用事实源。
- `docs/ai/CURRENT_TASK.md` 内容已过期，仍停留在“等待用户确认分支 / PR 治理操作”，需要更新为本次 docs-only 文件治理状态。
- `docs/ai/CODEX_REPORT.md` 包含大量历史执行结果，适合作为报告归档，不适合作为当前任务事实源。
- `docs/ai/DECISIONS.md` 已承载较多 Final 决策，应继续保持 Final Only，不把待确认事项或临时推测写入其中。
- `docs/database/环境信息.md` 与 `docs/database/数据库开发安全方案.md` 都涉及环境安全；前者记录当前非敏感环境事实，后者记录数据库安全流程。两者职责可区分，不需要合并。
- `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` 与 `docs/ai/WORKFLOWS.md` 存在交叉引用但职责清晰：前者定义分支 / 环境映射，后者定义执行流程。

## 4. 收口建议

- 新任务开始时优先从 `docs/README.md` 进入，再按任务类型读取 AI、governance、database 文档。
- 当前任务状态只写入 `docs/ai/CURRENT_TASK.md`，不要写入 `CODEX_REPORT.md` 或 `RULES.md`。
- 操作步骤、命令清单、回传模板继续写入 `docs/ai/WORKFLOWS.md`。
- 复盘经验继续写入 `docs/ai/LESSONS.md`，除非用户明确确认，不升级为正式 Rule。
- 已确认的产品与技术口径写入 `docs/ai/DECISIONS.md`；待确认事项保持在任务单、报告或规划文档中。

## 5. 未确认事项

- `docs/database/数据库开发安全方案.md` 开头仍保留“生产库和开发库尚未隔离”等较早风险表述，而 `docs/database/环境信息.md` 已登记 development 项目；本次因允许修改范围未包含该文件，暂不修改，建议后续单独确认是否收口。
- `docs/ai/CODEX_REPORT.md` 体量较大且历史信息混杂，是否拆分为归档目录或按日期归档，需用户后续单独确认。
- 是否为 `docs/ai` 新增更细的文档地图文件，例如 `docs/ai/DOCUMENT_MAP.md`，本次暂不新增，避免重复入口。
