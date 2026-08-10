# Lessons

用途：记录项目协作中反复出现的经验、问题和改进线索。Lesson 不是强制规则，只是可复盘的经验记录。

## 记录格式

### Lesson: 标题

- 日期：
- 来源任务：
- 现象：
- 原因：
- 处理方式：
- 后续影响：
- Pattern Candidate：
- Rule Candidate：
- 状态：观察中 / 可复用 / 已转为 Rule Candidate / 已废弃

## 当前 Lessons

### Lesson: 验收清单必须由统一模板约束账号模块和可输入密码

- 日期：2026-08-03
- 来源任务：PR #118 建立验收门禁后的实际使用，以及 PR #120 积分等级视觉展示业务验收
- 现象：仓库已有验收字段要求和 `acceptance:check`，但没有唯一清单模板；PR #120 的本地清单曾使用统一账号表，并显示密码“已清除”，无法直接执行。修复后生成的长随机密码虽然实登成功，仍不适合负责人手工输入；沟通中还曾把“验收清单”要求误称为“验收报告”。
- 原因：旧校验器只通过全文关键词和首个账号 / 密码判断完整性，没有解析每个测试模块，也没有约束密码的人工可输入性；清单与报告虽在工作流中分开，缺少可直接复用的模板入口。
- 处理方式：新增统一验收清单模板，保留验收范围、已准备数据、最短验收流程、总通过标准、异常反馈格式、数据保留与清理和 Rollback；移除账号密码总表与放置规则模块。无需登录的公开场景使用不含凭据的匿名模块；每个账号使用独立的“一次登录”测试模块，模块内明确填写账号和 8 至 16 位英文字母数字简单密码；校验器逐模块检查并拒绝匿名模块凭据、统一密码、模块外凭据和复杂随机密码。
- 后续影响：负责人可以直接在当前测试模块取得可输入凭据并连续完成该账号的场景；清单继续只存在于 Git 忽略路径，报告只记录反馈和状态，不保存凭据。
- Pattern Candidate：采用“统一模板 → 每账号一个测试模块 → 模块内简单凭据 → 逐模块机械校验 → 清单执行 / 报告收口分离”的验收闭环。
- Rule Candidate：负责人已于 2026-08-03 明确模板要求；本次同步到 `WORKFLOWS.md`、模板和校验测试，不改变 `RULES.md` 的凭据安全边界。
- 状态：可复用

### Lesson: 用户可见功能必须在业务验收后再合并

- 日期：2026-07-30
- 来源任务：对 PR #110～#117 的数量、审查与验收跟随 PR 进行只读复盘
- 现象：最近八个已合并 PR 实际归属于任务清理流程、排行榜第一版和上月榜三个主要结果；#110～#113 围绕同一清理工具连续修补，#115 和 #117 分别是主 PR 合并后的单处验收反馈。每个 PR 都重复触发远端检查、合并回读和分支收尾。
- 原因：普通 `develop` PR 被设为 checks 通过后立即合并，而人工业务验收排在合并之后；用户可见问题只有在主 PR 已关闭后才反馈，被迫建立跟随 PR。同一工具也在主要场景尚未完整跑通前过早合并。
- 处理方式：用户可见功能以目标 PR 最新 head commit / Preview 为验收对象，负责人明确验收通过后才允许合并；反馈继续更新原 PR，只重验受影响流程。非用户可见 PR 仍可在 checks 通过后按任务授权合并，数据库、安全和 rollback 门禁不降低。
- 后续影响：一个用户可见业务结果能够在一个 PR 内完成实现、反馈和验收，减少重复 checks、全量验证、合并回读与分支清理；验收不再由自动测试或构建替代。
- Pattern Candidate：采用“实现与相称验证 → 一个 PR / Preview → 最新版本业务验收 → checks → 一次合并与收尾”的用户可见功能闭环。
- Rule Candidate：负责人已于 2026-07-30 批准，已同步到 `RULES.md`、`WORKFLOWS.md` 和 `AGENTS.md`。
- 状态：可复用

### Lesson: 技术授权、业务验收与任务清理必须形成可理解闭环

- 日期：2026-07-29
- 来源任务：DB-6～DB-12 连续数据库修复、测试账号准备、人工验收和项目总结
- 现象：负责人反复复制 project ref、migration 文件名和 SHA-256，却无法据此判断业务风险；验收清单的账号分组和预期结果有效，但密码、过期 Preview、已完成场景和旧失败报告容易残留；合并后的任务分支和临时文件没有固定清理步骤。
- 原因：技术指纹被误当成用户授权内容；验收准备、反馈和任务关闭没有成为默认执行流；分支删除与所有高风险历史改写共用一个笼统门禁，导致安全可清理对象也长期堆积。
- 处理方式：采用三级授权，技术指纹由系统自动核对；development 无业务数据 migration 与专用验收数据使用常驻授权，production 和破坏性操作继续单独确认；验收包改为本地忽略文件并按账号一次登录；新增只读分支审计和精确 PR 清理工具。
- 后续影响：负责人只判断环境、目的、影响和 rollback；Codex 在验收前准备数据、交付最短流程，验收后清理凭据、任务分支和临时文件。未合并、来源不明和状态不确定对象仍必须暂停。
- Pattern Candidate：采用“自然语言授权卡 → 自动技术指纹 → 本地验收包 → 一次登录验收 → 精确清理 → 回读关闭”的完整任务闭环。
- Rule Candidate：负责人已于 2026-07-29 批准，已同步到 `RULES.md`、`WORKFLOWS.md` 和 `AGENTS.md`。
- 状态：可复用

### Lesson: 合体后切换为 Codex 单人开发模式

- 日期：2026-07-27
- 来源任务：对近期 DB-5、DB-6 开发耗时、长任务日志和现行治理规则进行只读诊断后实施流程改造
- 现象：业务实现完成后，重复审计、过程 push、PR 状态回读、Supabase 重连 / 重复前检和多份状态文档收口继续占用大量时间；旧规则仍假设 ChatGPT 规划、Codex 机械执行。
- 原因：原流程为多工具交接和环境恢复设计；合体后仍把 GitHub 当开发过程日志，把普通 `develop` merge 和同一 migration 的每个步骤拆成独立授权点，并在长对话里重复加载完整上下文。
- 处理方式：本地工作区作为开发中事实，GitHub 只承担共享 / PR / 合并 / 发布事实；Codex 对一个目标端到端负责；一次最终验证、一次远端交付；普通 `develop` PR 检查通过后按任务授权合并；固定 development migration 可一次授权完整闭环并复用现有 link；任务看板退出 Git，只保留可选的本机极简指针。
- 后续影响：保留 `main` / production、破坏性数据、env / 凭据、数据库环境与 rollback 门禁；取消旧 ChatGPT 预审批、逐命令确认、重复审计、Git 跟踪任务看板和纯状态提交。
- Pattern Candidate：采用“本地连续实现 → 一次相称验证 → 一次 GitHub 交付 → 普通 develop 自动收口”的单人开发闭环。
- Rule Candidate：负责人已于 2026-07-27 批准，已同步到 `RULES.md` 和 `WORKFLOWS.md`。
- 状态：可复用

### Lesson: DB-2 连续任务与合并收口协作复盘

- 日期：2026-07-20
- 来源任务：DB-2 开发、PR #82 / #83 / #84 合并与合并后收口，以及 PR #95 前端缺陷批次收口
- 现象：
  - 同一工作对话先后经历实现、审计、三次 merge 单独确认、合并后回读、文档冲突处理和看板修正，用户多次看到“继续”“下一步”和确认提示。
  - PR #82 中的看板仍写着等待合并 PR #82；合并后该状态立即过期，因此又产生 PR #84 做纯状态修正。
  - PR #95 合并时看板再次保留“等待合并决定”和合并授权问题；由于纯状态 PR 已被禁止，只能在后续治理主 PR 中恢复稳定看板。
  - PR #83 已先修改部分相关文档，PR #82 后续收口时出现重叠基线，需要刷新分支并解决文档冲突。
  - GitHub / Supabase 查询曾出现 EOF、TLS 和连接器传输异常；长对话中还出现多次流式响应断开。
- 原因：
  - 用户指令侧：持续目标包含“更新看板并继续下一步”，但没有始终给出每一阶段的最终停止点；“执行下一步”在合并后可能同时指向远端回读或下一份文档收口，增加了选择空间。这是边界不够具体，不是三次 merge 确认本身的原因。
  - 治理门禁侧：每个 PR merge 都必须获得一次新的明确确认；PR #82、#83、#84 是不同敏感操作，不能用早先确认替代，相关重复属于必要控制。
  - 执行侧：PR #82 和 PR #95 的预合并审计都没有阻止看板短时状态进入合并；仅有文字检查而没有可执行门禁，导致同类问题复发。等待授权期间重复回读无变化状态、单个长对话承载过多独立阶段，也放大了重复沟通和断流影响。
  - 仓库与工具侧：并行 PR 修改重叠文档形成基线变化；远端连接失败的结果不确定，必须先回读远端事实，不能直接把报错等同于操作失败。
- 处理方式：
  - 五项执行单中的停止点改为可验证边界；“继续 / 下一步”存在歧义时，以看板第一条下一步为准，并在启动回执中声明选择。
  - 将看板合并后稳定性检查升级为可运行门禁：修改看板的 PR 在 commit、push、PR 创建和 merge 审核前检查短时 PR 状态与栏目条数。
  - 敏感操作只做一次最新审计后等待用户确认；异常后先查远端事实，再决定重试。
  - 一个阶段完成远端回读和文档收口后结束；独立目标使用新执行单，并优先返回本地文件链接。
- 后续影响：
  - 用户只需在敏感操作处确认，不应为同一未变化状态重复确认或接收重复盘点。
  - 看板应表达合并后仍成立的业务 / 技术状态，避免为 PR 状态变化再开纯状态 PR。
  - 长任务在阶段边界主动收口，可降低上下文膨胀、输出截断和网络断流后的恢复成本。
- Pattern Candidate：采用“明确停止点 → 一次最新审计 → 单独授权检查点 → 远端事实回读 → 合并后稳定看板 → 新目标短交接”的连续任务闭环。
- Rule Candidate：负责人已于 2026-07-22 批准“看板必须通过合并后稳定性门禁”，同步进入 `RULES.md`，具体检查保留在 `WORKFLOWS.md`。
- 状态：可复用
- 2026-07-27 更新：其中“每个 `develop` PR merge 单独确认”和多角色交接部分已被 Codex 单人开发模式替代；production、破坏性数据和环境边界仍保留。

### Lesson: Production Safari 图鉴全量加载卡住复盘

- 日期：2026-07-06
- 来源任务：production Safari 图鉴加载故障 hotfix 复盘
- 现象：
  - 问题用户可以登录，顶部已显示账号 / 个人中心 / 登出，但主内容停在“奇迹载入中”。
  - `?debug=1` 初始显示卡在“查询 clothes count”。
  - PR #30 修复 count 超时降级后，卡点推进到“正在下载 clothes：offset 15000/18000”。
  - 用户补录缺失部件后刷新，触发图鉴数据变化；本地缓存数量与云端 count 不一致，旧逻辑进入全量 clothes 重新下载。
- 原因：
  - count 查询不能阻塞首屏；失败或超时时应跳过缓存校验并继续加载。
  - 本地 `fullClothesData_v2` 数量与云端 clothes count 不一致时，旧逻辑会强制全量刷新图鉴。
  - production clothes 数据量为 1.8 万+，dev 小数据无法证明 production 大表加载链路安全。
  - 移动端 Safari 对全量大表下载、JSON 解析、IndexedDB 写入和长链路 pending 更敏感。
- 处理方式：
  - PR #30：对 clothes count 增加窄范围超时降级，count 失败或超时时跳过缓存校验。
  - PR #31：有本地 `fullClothesData_v2` + `stagesData` 缓存时，先使用本地缓存进入页面，再后台刷新图鉴。
  - PR #32：对 clothes/stages 分页下载增加单页 timeout + retry；单页最终失败时进入 `catch/finally`，避免永久 loading。
  - PR #33：从 main cherry-pick PR #31 和 PR #32 的业务修复，避免 develop 上的 docs 变更混入 production hotfix。
- 后续影响：
  - 不要让全量图鉴刷新阻塞首屏；有缓存时优先使用缓存。
  - 大表分页请求必须有 timeout / retry，失败后应释放 loading，而不是让 Promise 永久 pending。
  - dev 小数据不能证明 production 大数据链路安全；涉及大表、移动端 Safari、IndexedDB 时需要 production-like 数据量或诊断开关。
  - 用户设备问题优先加 debug 定位，不要盲猜 Auth、数据库或环境绑定。
  - production hotfix 应从 main cherry-pick 业务修复，避免 develop 混入 docs 或其他低风险变更。
- Pattern Candidate：大表首屏加载采用“缓存优先进入页面 + 后台刷新 + 分页 timeout/retry + debug 可见卡点”的组合，而不是阻塞式全量刷新。
- Rule Candidate：暂无。
- 状态：可复用

### Lesson: 空模板不长期保留

- 日期：2026-07-05
- 来源任务：docs-only 文档瘦身 Phase 1
- 现象：`docs/ai/WEEKLY_REVIEW.md` 和 `docs/ai/PROMPTS/**` 主要是初始化模板资产，引用审查显示只被历史报告或模板自身引用，未被当前入口和工作流强依赖。
- 原因：空模板和低使用 prompt 文件会扩大 `docs/ai` 目录维护面，让普通 docs-only 任务误以为需要额外读取。
- 处理方式：移除低使用模板文件；后续复盘模板和 prompt 线索统一收口到 `docs/ai/LESSONS.md`。
- 后续影响：如后续需要重新引入模板，应先确认实际使用频率和入口位置，避免新增长期空文件。
- Pattern Candidate：docs 模板只有被当前 workflow 稳定使用时才长期保留，否则并入复盘经验或任务指令。
- Rule Candidate：暂无。
- 状态：观察中

### Lesson: docs 入口需要文件职责地图

- 日期：2026-07-04
- 来源任务：docs-only 文件治理盘点
- 现象：`docs/README.md` 已有总入口，但 `docs/ai`、`docs/governance`、`docs/database` 中存在规则、流程、当前任务、报告和数据库环境说明交叉引用，新任务容易把历史报告或当前任务文件当作长期事实源。
- 原因：文档体系扩展后，入口索引只说明“有哪些文件”，但没有集中说明“每个文件不该承载什么”。
- 处理方式：新增 `docs/FILE_GOVERNANCE.md` 作为文件职责地图，并在 `docs/README.md`、`WORKFLOWS.md`、`CONVERSATION_HANDOFF.md` 中补充入口。
- 后续影响：后续 docs-only 收口优先更新入口和职责地图；如发现需要修改 `RULES.md`，应作为未确认事项暂停，不在普通文件治理任务中顺手修改。
- Pattern Candidate：docs 规模扩大后，采用“总入口 + 文件职责地图 + 当前任务状态”的组合，避免规则层、操作层和历史报告混用。
- Rule Candidate：暂无。
- 状态：观察中

### Lesson: docs-only 任务需要任务级预审批

- 日期：2026-07-04
- 来源任务：修正 ChatGPT 与 Codex 的 docs-only 审批流，减少不必要中断
- 现象：docs-only 任务中，`git fetch`、`gh pr view`、`git add`、`git commit`、`git push`、`gh pr create` 多次触发审批中断。
- 原因：审批被放在 Codex 执行中，而不是 ChatGPT 指令生成前。
- 处理方式：ChatGPT 在发送 Codex 指令前完成任务级预审批；Codex 在授权范围内连续执行；只有越权、失败或高风险升级才停止。
- 后续影响：docs-only 任务应在 ChatGPT 指令中一次性写清敏感命令、用途、授权边界和失败处理，减少反复确认。
- Pattern Candidate：docs-only 任务采用“ChatGPT 任务级预审批 + Codex 授权范围内连续执行”的协作模式。
- Rule Candidate：暂无。
- 状态：已废弃；已由 Codex 单人开发模式的一次任务授权和连续执行替代

### Lesson: 规则层与工作流层分离

- 日期：2026-07-03
- 来源任务：整理 `docs/ai` 与 `docs/governance` 规则和工作流，降低 `RULES.md` 膨胀风险
- 现象：`RULES.md` 同时承载强规则、具体命令、PR 检查步骤和回传模板，容易随着工具变化持续膨胀。
- 原因：工作流迭代频繁，直接写入 `RULES.md` 会污染强规则层，让真正不可轻易变动的门禁和边界变得不清晰。
- 处理方式：`RULES.md` 作为宪法层，保留强规则、角色边界、门禁和安全边界；`WORKFLOWS.md` 作为操作手册层，承载可迭代流程、命令清单、检查步骤和回传模板。
- 后续影响：后续新增操作步骤优先写入 `WORKFLOWS.md`；只有经过验证并由用户确认的稳定原则才进入 `RULES.md`。
- Pattern Candidate：采用“Rule 宪法层 + Workflow 操作手册层 + Lesson 复盘经验层”的文档分层，减少规则污染。
- Rule Candidate：暂无。
- 状态：可复用

### Lesson: GitHub CLI 纳入治理工作流

- 日期：2026-07-03
- 来源任务：安装并验证 GitHub CLI，更新 PR / workflow 状态确认工作流
- 现象：PR 状态、`mergeable`、changed files 和 workflow 状态经常需要在合并前重复确认。只依赖页面人工查看或连接器回传，容易增加操作成本，也容易漏掉本地命令可复核的证据。
- 原因：本地 `gh` 能提高 PR 状态、`mergeable`、changed files 和 workflow 查询效率，但 `gh auth` / token 泄露、把 `gh pr merge` 当成默认动作、以及网络不可用都会带来治理风险。
- 处理方式：
  - PR 和 workflow 只读确认优先使用 `gh`，包括 `gh pr view`、`gh pr diff`、`gh pr list`、`gh run list`、`gh run view`。
  - `gh` 不可用时，回退到 GitHub 页面或 ChatGPT GitHub 连接器。
  - `gh pr merge` 必须在用户明确确认后才能执行，不得因为工具可用就默认合并。
  - `gh auth` token、验证码、授权链接和 keyring 信息不得写入仓库、文档、日志或 commit。
  - production 相关 merge 前必须再次确认用户授权、环境映射和 rollback。
- 后续影响：后续 PR 治理可以把 `gh` 作为优先只读检查工具，但合并权限、production 边界和 GitHub 事实源原则保持不变。
- Pattern Candidate：PR 发布前采用“gh 优先查询 -> git diff / changed files 交叉确认 -> 用户授权后才执行写操作”的工作流。
- Rule Candidate：暂无。
- 状态：可复用
- 2026-07-27 更新：普通 `develop` merge 可由任务级授权覆盖；`main`、production 和 hotfix merge 仍需本次发布的明确授权。

### Lesson: AI + Codex + 双环境项目治理工作流复盘

- 日期：2026-07-03
- 来源任务：恢复分支与环境治理、拆分 develop -> main 发布、验证 Supabase development migration、Preview 管理员审核流程修复
- 现象：项目同时涉及 GitHub 分支、Vercel 部署、Supabase 双环境、数据库 migration、前端审核流程和 AI 协作规则。如果直接合并 develop 到 main，容易把未审计的业务代码、数据库变更或环境风险带入 production。
- 原因：`main = production`、`develop = development / preview` 的事实源曾被分支历史、PR 状态、Vercel / Supabase 绑定和文档状态打乱；同时 Codex 可能在没有明确边界时把文档、业务、数据库和配置变更混在一次提交中。
- 处理方式：
  - 先确立事实源：以 GitHub、Vercel、Supabase project ref 和 `docs/ai` / `docs/governance` 文档为准。
  - 角色分工：
    - 用户：最终决策者，确认生产操作、环境绑定、PR 合并和业务验收结果。
    - ChatGPT：整理任务、拆分风险、形成 Codex 指令和 PR 文案，不直接执行生产操作。
    - Codex：按任务边界执行文件修改、验证、commit / push，并回传 `git status`、命令结果、风险和 rollback。
  - AI / Codex 开始任务前先读 `docs/ai/RULES.md`、`docs/ai/CURRENT_TASK.md` 和 `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`。
  - 固定环境映射：`main = production`，`develop = development / preview`。
  - 只读盘点优先：任何治理、发布或数据库任务先做 `git status`、分支 / PR / 差异盘点，再决定是否修改。
  - develop -> main 前必须做差异分类：文档、业务代码、数据库 / Supabase、配置 / 构建。
  - 文档 / 业务 / 数据库 / 配置按风险拆 PR；高风险内容不得跟低风险文档治理混合发布。
  - migration 必须先在 development 验证，再考虑 production。
  - 已执行过的 migration 不原地改来期待远端重跑；如果需要修正，新增 patch migration。
  - 每一步必须回传：`git status`、关键命令结果、风险判断、rollback 方案和未确认事项。
- 后续影响：后续任何 develop -> main 发布都应先按此流程走，只在目标环境验证，发布前重新确认 Vercel / Supabase 绑定，并准备前端、migration 和数据一致性 rollback。
- Pattern Candidate：双环境项目发布前采用“事实源确认 -> 只读盘点 -> 分层审计 -> 环境内验证 -> 分风险 PR -> rollback 准备”的固定工作流。
- Rule Candidate：已同步到 `RULES.md` 的硬规则包括任务前阅读治理文档、develop -> main 只读审计、migration 先 dev 验证、已执行 migration 用 patch migration 修正、production 操作前确认环境绑定。
- 状态：可复用
- 2026-07-27 更新：ChatGPT / Codex 角色分工与“每一步回传”已废弃；双环境映射、development 先验证和 production rollback 门禁继续有效。

### Lesson: 大模块开发前先拆阶段包

- 日期：2026-06-30
- 来源任务：整理积分、贡献者、重审池、报错修正的最小开发计划
- 现象：积分、贡献者、重审池、报错修正、陪审团和排行榜之间依赖很多，如果直接进入数据库和功能开发，容易一次性改动过大。
- 原因：这些模块同时影响正式库、pending 状态、用户衣柜、积分权益和管理员审核，产品口径仍有多项待确认。
- 处理方式：先把第一版目标、不做范围、依赖对象、用户确认点、开发风险和建议顺序写入需求、开发和技术实现文档。
- 后续影响：下一阶段可优先开发贡献者记录和积分流水，再逐步接入重审池和报错修正，陪审团和排行榜后置。
- Pattern Candidate：大型功能进入开发前，先做“阶段包任务”，把最小闭环、后置范围和暂停确认点写清楚。
- Rule Candidate：暂无。
- 状态：可复用
