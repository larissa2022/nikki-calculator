# Nikki Calculator Codex 执行入口

本文件是仓库中唯一自动生效的 Codex 入口。项目采用 Codex 单人开发模式：负责人给出业务目标和边界，Codex 负责调查、实现、验证、GitHub 交付和 development 收口。

## 1. 固定约定

- 使用北京时间（UTC+8）记录时间，使用中文 commit 信息和中文回传。
- 本地工作区是开发过程的当前事实；GitHub 是已共享、已推送和已合并状态的远程事实。未 push 的内容不算已发布，但不要求在开发中反复 push。
- `main` 对应 production，`develop` 对应 development / preview。
- 默认从最新 `develop` 创建一个窄范围 `codex/*`、`feature/*`、`fix/*` 或 `docs/*` 分支；一个业务结果默认只使用一个 PR。
- 普通任务在本地连续完成，最终验证后集中 commit、push 和创建 PR。不要为了同步过程状态单独提交或推送。
- 负责人负责产品取舍、production 和破坏性操作；Codex 负责已确认目标内的技术实现与相称验证。

## 2. 最小读取路由

所有任务只读取：

- 本文件。
- 用户明确指定的文件。
- 当前任务直接相关的代码或文档。

按任务补读：

| 条件 | 补读内容 |
| --- | --- |
| 用户说“继续”“下一步”或询问项目进度 | `docs/ai/CURRENT_TASK.md` |
| 需要修改文件或发布到 GitHub | `docs/ai/RULES.md` 和 `docs/ai/WORKFLOWS.md` 的对应章节 |
| 改变产品规则、用户行为或技术口径 | `docs/ai/DECISIONS.md`，再按需读取相关需求或规划章节 |
| 修复缺陷 | 缺陷索引中的目标条目和相关代码；涉及产品语义时追加 `DECISIONS.md` |
| database、Supabase、SQL、RPC、RLS 或 migration | `docs/database/环境信息.md`、数据库安全方案的相关章节、数据库变更索引中的目标条目和目标 migration |
| `main`、production、release 或 hotfix | `docs/governance/BRANCH_ENVIRONMENT_POLICY.md` |
| 修改治理规则或复盘流程 | `docs/ai/LESSONS.md` 的相关条目和 `docs/README.md` |

不要全文读取无关历史、归档、变更记录或长规划。记录型文档先查索引，只打开命中的目标章节；`docs/archive/**` 不参与当前任务执行。

## 3. 启动与连续执行

普通修改开始前，用一条简短回执说明：业务目标、允许范围、验证方式和停止点。database、production、权限、数据删除或规则修改再补充目标环境与 rollback。回执不需要等待重复确认。

用户说“实现”“修改”“修复”“继续执行”等明确动作时，默认授权同一目标内连续完成：

1. 一次本地与远端基线确认。
2. 创建或复用一个任务分支。
3. 连续完成代码和文档修改，开发中只运行针对性测试。
4. 在最终边界运行一次完整的相称验证。
5. 集中 commit、push、创建或更新一个目标 PR。
6. PR 检查通过后，普通 `develop` PR 可直接合并并回读；用户明确要求停在合并前时除外。

不要在分支创建、单文件修改、测试、commit、push 或 PR 创建之间逐步询问。不要在同一远端状态未变化时重复审计或轮询。

以下情况必须暂停：

- 出现未确认的产品语义或互斥业务选择。
- 文件范围、目标分支、数据库环境或 migration 集合发生变化。
- 验证失败且修复会扩大范围，或 rollback 不明确。
- 即将操作 `main`、production、真实数据删除 / 回填、env / 凭据、历史改写或分支删除。
- 工具返回不确定结果且只读回查仍无法确定实际状态。

development 数据库写入不由普通代码修改自动授权；但负责人可以在任务开始时一次性授权固定 project ref 和固定 migration 集合。目标与文件哈希未变化时，不为前检、apply、事务验证和后检重复索要授权。

## 4. 效率原则

- GitHub 只在任务开始刷新一次、最终交付一次、远端写入结果不确定时回读一次；不把远端当作开发过程日志。
- Supabase 工作区已链接到正确 development project 时直接复用，并在实际远端操作前运行固定 project-ref 检查；不要重复 link。
- 同一变更只做一次最终全量验证。编码阶段运行受影响测试，文档变更不触发无关构建或浏览器回归。
- `CURRENT_TASK.md`、数据库变更记录、需求和技术文档只在对应事实真正变化时于最终收口批次更新一次。
- 一个独立目标完成后结束任务；新的业务目标使用新任务，避免长期对话反复携带完整历史。

## 5. 安全边界

- 完整强规则以 `docs/ai/RULES.md` 为准，执行步骤以 `docs/ai/WORKFLOWS.md` 为准。
- 不提交 `tmp/**`、`.env*`、`supabase/.temp/**`、token、验证码、授权链接、keyring 信息、真实用户隐私数据或 production 写库脚本。
- database migration 先在 development 验证；已应用 migration 只能用新的 patch migration 修正。
- `main`、production、破坏性数据操作、env / 凭据、历史改写、分支删除和修改 `RULES.md` 必须针对本次目标明确授权。

## 6. 回传

最终回传只说明：业务结果、验证结论、当前阶段、唯一下一步，以及真正需要负责人决定的事项。默认隐藏命令流水和重复技术证据；数据库、权限、production、异常和 rollback 信息按需说明。

项目任务完成后附上本地 `docs/ai/CURRENT_TASK.md` 链接。只有业务状态或下一步确实变化时才更新看板，不为 PR 状态变化单独修改看板。
