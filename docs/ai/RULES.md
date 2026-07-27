# 项目强规则

本文件只保存稳定的决策边界、安全门禁和环境规则。操作步骤放在 [`WORKFLOWS.md`](WORKFLOWS.md)，产品口径放在 [`DECISIONS.md`](DECISIONS.md)。冲突时以本文件为准。

正式 Rule 只能由用户本人批准。用户已于 2026-07-27 批准项目切换为 Codex 单人开发模式。

## 1. 责任与事实源

- 用户本人是最终决策者，负责产品取舍、production 发布、破坏性数据操作和最终业务验收。
- Codex 对已确认目标端到端负责，包括调查、实现、测试、构建、文档收口、commit、push、PR 和允许范围内的 development 验证。
- 本地工作区是开发中状态的事实源；GitHub 是已共享、已推送、PR、合并和发布状态的远程事实源。未 push 的内容不算已发布，但开发过程不要求持续上传。
- 旧的 ChatGPT 预审批、执行单转交和 Codex 机械执行分工不再适用。

## 2. 分支与环境

- `main` 只对应 production；`develop` 只对应 development / preview。
- 默认从最新 `develop` 创建一个窄范围任务分支，以一个 PR 交付一个可独立验收的业务结果。
- 普通开发只在最终验证后集中 push。修复最终检查发现的问题时可继续更新同一 PR，不为过程状态另建 PR。
- 用户明确要求实现、修改或修复且未要求停在合并前时，授权包含：本地修改、相称验证、commit、push、创建或更新 PR，以及检查通过后合并普通 `develop` PR。
- `develop` 合并不等于 production 授权。任何 `develop -> main`、production 或 hotfix 发布仍按独立发布门禁执行。
- Vercel production 只能对应 `main`；preview / development 只能对应 `develop` 或短期任务分支。

## 3. 必须单独确认的操作

以下操作必须由用户针对本次目标明确确认，不能从一般性开发指令推断：

- 任何 `main`、production、production deployment 或 production rollback。
- production 数据库操作，以及真实业务数据的删除、批量回填、批量改写或身份数据清理。
- development database / Supabase / SQL / RPC / RLS / migration apply。可以在任务开始时一次授权固定 project ref、固定 migration 集合、验证和 rollback；目标与文件未变化时不重复确认同一批次的前检、apply、事务验证和后检。
- env、凭据、Vercel 写配置或环境绑定变更。
- force push、`reset --hard`、`git clean`、rebase、分支删除或其他历史改写。
- 修改本文件。

范围、环境、project ref、migration 集合或 rollback 发生变化时，原授权失效并重新确认。普通 `develop` PR merge 不再作为独立确认点；用户明确要求停在合并前时必须遵守。

## 4. 任务与 PR 隔离

- 一个业务结果默认使用一个任务分支和一个 `develop` PR。数据库结构、同一功能的业务接入、前端和直接支持文档默认在同一 PR 内交付。
- 只有当数据库变更需要独立部署 / rollback、数据迁移风险明显高于业务代码，或用户明确要求时，才拆成数据库 PR 与业务 PR。
- 治理规则、无关 config、release 和当前业务实现不得混入同一个 PR。
- `CURRENT_TASK.md`、缺陷状态、验收记录和数据库变更记录是支持文档，只在最终收口批次更新一次；不得为任务启动、等待、审计、PR 创建或合并状态建立纯状态提交或 PR。
- 修改 `CURRENT_TASK.md` 时必须描述合并后仍成立的业务状态，不得写当前 PR 编号、“等待合并”或授权提示。
- 已应用 migration 的修正必须新增 patch migration，不得改写 migration history。

## 5. 产品与需求门禁

- 涉及产品规则、用户行为、数据库结构、权限边界或既有功能语义变化时，先核对 `DECISIONS.md` 和相关需求事实。
- 用户已经明确给出的产品选择可直接进入实现，不需要再转换成另一份审批单。
- 只有存在互斥选择、信息不足会显著改变用户行为或实现会越出目标时才暂停；可由代码和仓库事实确定的问题由 Codex自行判断。
- 未确认的历史规划、临时推测和复盘建议不得当作 Final 决策实现。

## 6. 数据、权限与凭据安全

- 不提交或传播 `.env*`、token、验证码、授权链接、keyring 信息、真实用户隐私数据、`tmp/**`、`supabase/.temp/**` 或 production 写库脚本。
- migration 必须先在 development 验证；production 前必须确认环境、备份、前值、预计影响、事务方案、后检和 rollback。
- database 和批量数据任务不得删除事务数量断言、提交后回读或 rollback 依据，但不得重复执行同一份无变化前检来制造证据。
- 核心业务事实必须可追溯、可重算；错误积分等审计事实使用追加式反向记录，不删除历史。

## 7. 规则治理

- `RULES.md` 只保留必须长期稳定的强边界；工具命令、检查顺序和报告模板只放 `WORKFLOWS.md`。
- `LESSONS.md` 中的经验和 Candidate Rule 不自动生效。
- 普通流程优化优先修改 `WORKFLOWS.md`；只有改变授权、安全或环境边界时才修改本文件。
