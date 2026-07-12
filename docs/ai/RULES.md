# 项目强规则

用途：只记录已经生效的角色边界、强门禁和安全约束。任务读取路由由仓库根目录 `AGENTS.md` 统一管理；具体操作步骤、命令和回传模板放在 [`WORKFLOWS.md`](WORKFLOWS.md)。如流程与本文件冲突，以本文件为准。

正式 Rule 只能由用户本人批准。ChatGPT、Codex、Gemini 均不得自行创建或升级正式 Rule。

## 1. 事实源与角色边界

- 用户本人是最终决策者，负责产品判断、功能审核、流程把控和最终确认。
- GitHub 是唯一远程事实源；未 push 的内容不算已发布。
- ChatGPT 负责任务收敛、风险判断、执行单生成、只读复核，以及已授权的纯文档 GitHub 操作。
- Codex 负责代码、本地命令、测试、构建、commit、push 和 PR 创建，并严格按任务单执行。
- Gemini 可用于 challenge、发现反例和风险，不批准规则。
- 纯文档任务优先由 ChatGPT 通过 GitHub 连接器执行；ChatGPT 受限时，Codex 只作为固定 patch 的机械执行 fallback。

## 2. 分支与环境门禁

- `main` 只对应 production。
- `develop` 只对应 development / preview。
- 默认从 `develop` 创建窄范围任务分支，并以 `develop` 为 PR 目标。
- 不允许从普通 `feature/*`、`fix/*`、`docs/*` 分支直接合入 `main`；明确批准的紧急 hotfix 除外。
- `develop -> main` 前必须做只读差异审计，并按 docs、business、database、config 分类。
- Vercel production 只能对应 `main`；preview / development 只能对应 `develop` 或短期任务分支。
- production 操作前必须重新确认 GitHub 分支、Vercel project、Supabase project ref、影响范围和 rollback。
- 分支与环境映射以 [`../governance/BRANCH_ENVIRONMENT_POLICY.md`](../governance/BRANCH_ENVIRONMENT_POLICY.md) 为准。

## 3. 必须单独确认的操作

以下操作必须由用户针对本次目标明确确认，不能从旧对话、历史授权或一般性同意中继承：

- PR merge，包括 `gh pr merge`。
- 任何 `main` 或 production 操作。
- database、Supabase、SQL、psql、RPC、RLS、migration apply。
- Vercel 写操作、env 修改、production deployment 或 rollback。
- `force push`、`reset --hard`、`git clean`、rebase、删除分支或其他历史改写。
- 修改本文件。

授权必须明确目标、环境、允许范围、验证、失败处理和 rollback。范围变化、环境变化或门禁失败时必须重新确认。

## 4. 任务隔离

- docs、business、database、config、release 应按风险拆分，不在同一 PR 混合。
- docs-only 任务不得顺手修改代码、构建配置、脚本、数据库、Supabase、Vercel、env 或 migration。
- 业务任务不得顺手修改治理规则。
- database migration 必须先在 development 验证；已执行 migration 的修正必须新增 patch migration。
- production 写库脚本不得放入可提交路径。
- 数据库任务必须先确认 dev / prod 环境和 Supabase project ref，并读取数据库安全文档和变更记录。

## 5. 指令冲突与需求门禁

- 用户即时指令与本文件、分支环境治理、数据库安全边界或当前任务范围冲突时，不得直接执行。
- 冲突出现时，必须列出：用户指令、冲突依据、冲突点、处理方案、风险和 rollback。
- 涉及产品规则、用户行为、数据库结构、权限边界或既有功能语义变化时，必须先确认事实源和决策层级。
- 仓库已有需求、决策、规划或技术实现文档时，应优先对齐；用户口头描述是补充上下文，不自动替代已确认决策。
- 未确认事项、历史规划和临时推测不得直接写入 `DECISIONS.md`、任务单或实现。
- 新增字段、枚举值、状态值或权限边界前，必须标记为待审核并取得用户确认。

## 6. 数据与凭据安全

- 不提交或传播 `.env*`、token、验证码、授权链接、keyring 信息、真实用户隐私数据或 production 凭据。
- 不提交 `tmp/**`、`supabase/.temp/**` 或 production 写库脚本。
- production、database 和批量数据任务不得因节省 token 而删除前值检查、事务数量检查、提交后回读、备份或 rollback 依据。
- 核心业务事实应可追溯、可重算；具体产品与技术口径以 `DECISIONS.md` 为准，不在本文件展开实现细节。

## 7. 规则治理

- Candidate Rule、Verified Pattern 和 Rule 必须分层处理。
- Candidate Rule 与复盘经验不能直接作为执行依据。
- Rule 只能由已验证事实、GitHub 证据和用户明确确认形成。
- 操作步骤写入 `WORKFLOWS.md`；复盘和候选线索写入 `LESSONS.md`；产品和技术 Final 决策写入 `DECISIONS.md`。
- 禁止为一次任务临时扩张本文件；普通流程优化优先修改 `WORKFLOWS.md`。