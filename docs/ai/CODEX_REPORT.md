# 项目状态盘点

## 1. 当前已完成

- 已建立文档入口：`README.md` 指向 `docs/README.md`，文档已按需求、规划、数据库、安全记录分类。
- 已建立 AI 协作工作区：最近提交 `ab31de7 文档：初始化 AI 协作工作区`，`docs/ai/` 已用于记录任务、队列、决策、报告和测试清单。
- 已隔离数据库运维脚本：最近提交 `3c5d1fe 整理：隔离数据库运维脚本`，生产写库脚本已从可提交路径移出，保留只读盘点脚本。
- 已修复“正式库已有但资料不全，补全后提交失败”路径：最近提交 `cbce674 修复：支持补全已存在正式库图鉴`。
- 已完成按 `分类 + 短编号` 录入衣柜能力：最近提交 `7e52399 新增：支持按分类短编号录入衣柜`。
- 已规范新增服装核心字段：最近提交 `0c6bc46 修复：规范新增服装录入核心字段`。
- 已处理衣柜大数据刷新后数量异常的核心风险：`bef4245` 增加云端保存保护，`269e23d` 分页加载完整图鉴。
- 已完成生产构建安全修复：`24c2ee8` 合并禁用生产构建中的 Vue DevTools。
- 缺陷文档中多项高频问题已有修复记录，包括短编号校验、提交者衣柜写回、套装刷新、提交超时提示、昵称展示等。

## 2. 文档可能过期的位置

- `docs/requirements/需求文档.md`：仍以完整规划为主，包含 `points_ledger`、`jury_votes`、`re_review_items`、`correction_requests` 等后续目标；当前实现只完成了部分审核、入库和衣柜同步闭环，需要标注“已实现 / 未实现 / 待确认”。
- `docs/planning/开发文档.md`：阶段一到阶段七仍是理想开发路线，和近期实际优先处理的生产缺陷、审核卡片文案、正式库补全路径存在偏差；建议补一节“当前实际阶段”。
- `docs/planning/技术实现文档.md`：RPC 和 migration 方案未反映近期新增的 `complete_existing_clothes_from_pending`、按分类短编号录入、衣柜合并保存保护等实现。
- `docs/planning/缺陷文档.md`：部分缺陷状态仍为“待验证 / 待观察”，但 git log 显示相关修复已合并；需要根据 Preview / production 验证结果更新状态。
- `docs/ai/DECISIONS.md`：目前只有用途说明，没有沉淀已确认决策；建议补录关键口径，例如积分权威来源、生产脚本隔离、管理员审核卡片文案口径、数据库操作门禁。
- `docs/ai/CURRENT_TASK.md`：当前工作区显示该文件有未提交修改，需确认是否保留或回滚，避免任务状态与真实工作不一致。

## 3. 当前未完成事项

1. 高优先级：确认 `BUG-20260628-014` 在 Preview / production 中是否彻底解决，尤其是几千件衣柜刷新后数量是否稳定。
2. 高优先级：验证“正式库已有但资料不全”的补全路径，确认 pending 状态、正式库字段、提交者衣柜写回都符合预期。
3. 高优先级：确认当前工作区只剩 `docs/ai/CURRENT_TASK.md` 未提交修改，决定保留还是回滚。
4. 中优先级：更新缺陷文档状态，把已修复但仍标记待验证的项目按实际测试结果收口。
5. 中优先级：补充 `docs/ai/DECISIONS.md`，沉淀已经确认的产品和技术口径。
6. 中优先级：为积分、贡献者、重审和陪审团投票建立正式开发前的确认清单。
7. 低优先级：刷新后保留当前页面、认证超时提示等体验类缺陷可后续统一处理。

## 4. 建议下一步

低风险任务：

- 补全 `docs/ai/DECISIONS.md`，只记录已确认决策，不改业务代码。

中风险任务：

- 做一次 Preview 环境人工回归：衣柜保存、分类短编号录入、管理员审核卡片、正式库已有补全、套装选择与刷新。

高价值任务：

- 设计并拆分“积分流水 + 贡献者记录 + 重审池”的最小可落地版本，先写开发计划和风险点，开发前逐项确认。

## 5. 不建议现在做的事

- 不建议直接在 production 执行批量 SQL 或临时修数据。
- 不建议继续手工处理大量 pending 数据来代替产品逻辑建设。
- 不建议同时开发积分、陪审团、重审、报错、排行榜等多个大模块。
- 不建议在未确认产品口径前修改 `points_ledger`、`jury_votes`、`re_review_items` 等数据库结构。
- 不建议在当前文档未收口前继续扩展管理员权限和普通管理员轮换。
- 不建议把 local-only 的生产写库脚本重新加入仓库。

## 6. 是否需要用户确认

- 是否把 `docs/ai/CURRENT_TASK.md` 当前未提交修改保留并提交。
- 管理员审核卡片文案口径是否已经最终确认，是否写入 `docs/ai/DECISIONS.md`。
- “正式库已有但资料不全”的补全行为是否允许覆盖正式库已有字段，还是只能补空字段。
- 缺套装但编号完整的数据是否继续允许进入正式库，以及待补套装状态第一版是否必须落库到 `re_review_items`。
- 积分发放是自动 `awarded`，还是先进入 `pending` 等管理员确认。
- 贡献者名单前 3 位排序规则：按提交时间、积分、信用等级，还是最终一致度。
- 低风险项 / 高风险项的判定规则。

## 人工回归结果

本次 Preview / production 人工回归测试 8 项全部通过：

1. 衣柜保存与刷新后数量稳定：通过
2. 按分类 + 短编号录入衣柜：通过
3. 管理员审核卡片文案：通过
4. 正式库已有但资料不全的补全路径：通过
5. pending 状态变化：通过
6. 提交者衣柜写回：通过
7. 套装选择与刷新：通过
8. 生产环境不显示 Vue DevTools：通过

## 缺陷文档收口结果

已根据人工回归结果更新 `docs/planning/缺陷文档.md`：

- `BUG-20260628-014` 衣柜刷新后数量异常：已关闭。
- `BUG-20260625-002` 套装选择异常：已关闭。
- `BUG-20260625-003` 短编号校验：已关闭。
- `BUG-20260627-006` 提交者衣柜写回：已关闭。
- `BUG-20260627-007` 套装典藏馆刷新：已关闭。
- `BUG-20260627-008` 所属套装下拉偶发数据缺失：已关闭。
- 管理员审核卡片文案、正式库已有资料补全、pending 状态变化、生产环境 Vue DevTools 已作为回归通过事项记录。

本轮仅更新文档，未修改业务代码、Supabase 文件或数据库文件。

## 需求文档收口结果

已根据 `docs/ai/CODEX_REPORT.md`、`docs/ai/DECISIONS.md`、`docs/ai/TEST_CHECKLIST.md`、`docs/planning/缺陷文档.md` 和最近 20 条 git log，在 `docs/requirements/需求文档.md` 中补充“当前实现状态”小节。

本次收口标注：

- 已实现：按分类 + 短编号录入衣柜、衣柜刷新后数量稳定、正式库已有但资料不全补全、提交者衣柜写回、管理员审核卡片文案口径、生产环境禁用 Vue DevTools。
- 未实现 / 暂缓：`points_ledger` 积分流水、`jury_votes` 陪审团投票、`re_review_items` 重审池、`correction_requests` 报错修正、排行榜、普通管理员轮换。
- 待确认：正式库已有资料补全覆盖规则、缺套装但编号完整的数据是否入库、积分发放状态、贡献者前 3 排序规则、低风险 / 高风险项判定规则。

本轮仅更新文档，未修改业务代码、Supabase 文件、数据库文件、开发文档或技术实现文档。

## 开发文档收口结果

已根据 `docs/ai/CODEX_REPORT.md`、`docs/ai/DECISIONS.md`、`docs/requirements/需求文档.md`、`docs/planning/缺陷文档.md` 和最近 20 条 git log，在 `docs/planning/开发文档.md` 前部补充“当前实际阶段”小节。

本次收口记录：

- 当前已完成：AI 协作工作区、数据库运维脚本隔离、衣柜刷新数量稳定、分类 + 短编号录入衣柜、正式库已有但资料不全补全、提交者衣柜写回、管理员审核卡片文案优化、人工回归 8 项全部通过、缺陷文档已收口、需求文档已收口。
- 当前阶段重点：文档收口、回归确认，暂不直接开发积分、陪审团、重审、报错、排行榜等大模块。
- 下一步候选：收口技术实现文档、整理积分 / 贡献者 / 重审池最小开发计划、产品确认未决问题。

本轮仅更新文档，未修改业务代码、Supabase 文件、数据库文件、需求文档或技术实现文档。

## AIOS v1.1 初始化结果

已初始化轻量版 AIOS v1.1 文档骨架，仅更新 `docs/ai/` 范围内文件。

新增文件：

- `docs/ai/LESSONS.md`
- `docs/ai/RULES.md`
- `docs/ai/REJECTED_IDEAS.md`
- `docs/ai/WEEKLY_REVIEW.md`
- `docs/ai/PROMPTS/planning.md`
- `docs/ai/PROMPTS/review.md`
- `docs/ai/PROMPTS/challenge.md`
- `docs/ai/PROMPTS/weekly_review.md`

同步更新：

- `docs/ai/DECISIONS.md`：追加采用轻量版 AIOS v1.1、Rule 必须经用户本人审核、增加 Rejected Ideas 等决策。
- `docs/ai/CURRENT_TASK.md`：更新当前任务。

关键机制：

- 用户本人是最终决策者，也是正式 Rule 的唯一批准者。
- ChatGPT 只能提出 Lesson / Pattern / Rule Candidate，不能自行批准正式 Rule。
- Codex 负责按任务单和已批准规则执行。
- Gemini 用于 challenge 和发现风险，不批准规则。
- `RULES.md` 分为 Project Rules、Personal Rules、Rule Candidates。
- `LESSONS.md` 预留 Pattern Candidate 字段，暂不新增独立 `PATTERNS.md`。
- `REJECTED_IDEAS.md` 用于记录未采纳方案、拒绝原因和未来重新考虑条件。

本轮未修改业务代码、Supabase 文件、数据库文件、需求文档、开发文档、技术实现文档或数据库文档。

## Rule 审核结果

用户本人已审核并批准 Rule Candidate「AIOS 轻量协作边界」。

处理结果：

- 已从 `Rule Candidates` 移动到 `Personal Rules`。
- 类型：Personal Rule。
- 来源保留为：AIOS v1.1 初始化。
- 已明确职责边界：ChatGPT 负责整理任务、写任务单、判断下一步；Codex 负责按任务单执行；Gemini 负责 challenge、发现反例和风险；GitHub 是事实来源；用户本人负责最终审核、最终产品判断和正式 Rule 批准。

本轮仅更新 `docs/ai/RULES.md` 和 `docs/ai/CODEX_REPORT.md`，未修改业务代码。

## 技术实现文档收口结果

已根据 `docs/ai/CODEX_REPORT.md`、`docs/ai/DECISIONS.md`、`docs/ai/RULES.md`、`docs/requirements/需求文档.md`、`docs/planning/开发文档.md`、`docs/planning/缺陷文档.md` 和最近 30 条 git log，在 `docs/planning/技术实现文档.md` 前部补充“当前实现状态”小节。

本次收口标注：

- 已实现：`complete_existing_clothes_from_pending`、按分类 + 短编号录入衣柜、衣柜云端合并保存保护、`clothes` / `stages` 分页加载、提交者衣柜写回、生产构建禁用 Vue DevTools。
- 未实现 / 暂缓：`points_ledger` 积分流水、`jury_votes` 陪审团投票、`re_review_items` 重审池、`correction_requests` 报错修正、排行榜相关 RPC / view。
- 待确认技术点：正式库已有资料补全覆盖规则、积分发放状态机、重审池第一版是否落库、低风险 / 高风险自动判定字段。

本轮仅更新文档，未修改业务代码、Supabase 文件、数据库文件、需求文档、开发文档、缺陷文档或 `docs/ai/RULES.md`。

## 积分与重审阶段规划结果

已完成“积分 / 贡献者 / 重审池 / 报错修正”阶段包规划。本轮只更新文档，不实现功能、不修改业务代码、不修改数据库。

更新内容：

- `docs/requirements/需求文档.md`：补充“下一阶段最小可落地范围”，明确四个模块的第一版产品边界和待确认问题。
- `docs/planning/开发文档.md`：补充“阶段包：积分、贡献者、重审池、报错修正最小开发计划”，逐模块整理第一版目标、不做范围、依赖、用户确认点、开发风险和建议开发顺序。
- `docs/planning/技术实现文档.md`：补充“最小技术落地计划”，将四个模块映射到建议表、RPC、现有依赖和阶段级技术顺序。
- `docs/ai/CURRENT_TASK.md`：更新为当前阶段包任务。
- `docs/ai/LESSONS.md`：追加阶段包规划经验，提醒大模块开发前先拆最小闭环和暂停确认点。

本阶段建议开发顺序：

1. `clothing_contributions` + `points_ledger`：先保证当前入库 / 补全流程的贡献和积分可审计。
2. `re_review_items`：承接缺套装、字段冲突、字段缺失和需要修正的数据。
3. `correction_requests`：建立正式库报错入口，并把高风险修正转入重审池。
4. `jury_votes`、排行榜相关 RPC / view、普通管理员轮换继续后置。

待用户确认重点：

- 报错修正的低风险 / 高风险字段划分，以及积分待定 / 扣回规则。

其中以下事项已在后续确认并同步：积分默认 `awarded`、前 5 有效提交者按提交时间排序、前 3 展示贡献者按提交时间排序、缺套装但编号完整允许入库并创建 `re_review_items`。

未修改范围：`src/`、`supabase/`、数据库文件、`docs/ai/RULES.md`、`docs/ai/DECISIONS.md`。

## 积分与贡献者决策同步结果

已根据用户确认结果，同步积分、贡献者、缺套装入库与重审池第一版决策。本轮只更新文档，不实现功能、不修改业务代码、不修改数据库。

已确认并写入文档：

- 积分状态：第一版默认 `awarded`。图鉴审核通过后，积分立即生效。
- 前 5 有效提交者：与最终入库数据一致的提交者，按提交时间排序，取前 5 个获得积分。
- 前 3 展示贡献者：从前 5 有效提交者中，按提交时间排序，取前 3 个用于页面展示。
- 缺套装但编号完整：允许正式入库，同时创建 `re_review_items`，状态为待补套装。

更新文件：

- `docs/ai/DECISIONS.md`：追加“积分与贡献者第一版决策”。
- `docs/requirements/需求文档.md`：将积分状态、前 5 有效提交者、前 3 展示贡献者、缺套装入库与重审池从待确认口径同步为已确认口径。
- `docs/planning/开发文档.md`：同步第一版开发口径，并保留仍需确认的积分值、扣回、匿名历史数据、重审修正版权限等问题。
- `docs/planning/技术实现文档.md`：同步第一版技术口径，不新增具体 SQL migration。
- `docs/ai/CURRENT_TASK.md`：更新当前任务。

新增仍需确认点：

- 匿名历史数据是否展示为“匿名历史数据”，以及是否参与前 5 / 前 3。
- 自动入库、管理员仲裁、正式库补全、重审修正、报错修正分别给多少分。
- 扣回积分是否只追加负数流水，不删除原流水。
- 重审项是否允许普通用户提交候选修正版，还是只允许管理员处理。

未修改范围：`src/`、`supabase/`、数据库文件、`docs/ai/RULES.md`。

## Rule Lock Phase 1 最终收尾

Rule Lock Phase 1 已完整完成。

本次新增并冻结到 `DECISIONS.md` Final 区的规则：
- 积分扣回采用追加负数流水机制，不允许修改或删除历史积分记录，所有积分变更必须可追溯。
- Lv4 权重仅用于排序与展示，不参与自动入库判断，不参与积分计算与重审流程。

同步处理：
- 已从 `User Decision Required` 中移除“积分扣回是否只追加负数流水，不删除原流水”。
- 已从 `User Decision Required` 中移除“Lv4 可信权重是否参与自动入库”。

剩余未决策项数量：21 条。

本轮未修改业务代码、未修改数据库结构、未修改 `src/`、未修改 `supabase/`。

## 积分分值配置第一版同步完成

已同步积分分值配置第一版到 `docs/ai/DECISIONS.md` Final：
- 自动入库：+10。
- 管理员仲裁入库：+10。
- 正式库空字段补全：+5。
- 重审修正通过：+8。
- 报错通过：+5。

同步处理：
- 已移除上述来源分值仍待后续确认的口径。
- `docs/ai/CURRENT_TASK.md` 已更新为继续确认报错修正低风险 / 高风险字段划分。

本轮只更新文档，未修改业务代码、未修改数据库、未修改 `src/`、未修改 `supabase/`、未修改 `docs/ai/RULES.md`。

## Rule Lock Phase 1 第二批用户决策同步

Rule Lock Phase 1 第二批用户决策同步完成。

本次写入 `DECISIONS.md` Final 的规则：
- 正式库空字段允许补全；正式库已有非空字段默认不允许覆盖，只有该字段被报错并审核通过后才允许修改。
- 积分分值按来源区分配置，不采用所有来源统一 +10；具体来源分值仍待后续确认。
- 待补套装状态在绑定正式套装后自动关闭，不需要管理员手动关闭。
- 管理员终审不写入 `jury_votes`；普通用户投票与管理员终审语义分离，管理员终审应单独建立终审记录。
- 编号字段不允许为空；缺编号数据不应通过提交 / 入库校验，因此不进入积分判断分支。

同步处理：
- 已将旧的统一 +10 积分口径替换为按来源配置。
- `DECISIONS.md` 当前为 Final Only 结构，不存在 `User Decision Required` 区；本轮无该区条目需要移动。

本轮只改文档，未改业务代码、数据库、`RULES.md`。

## Rule Pruning Phase

Rule Pruning Phase completed。

本次将 Rule System 从 v2 收敛为 v2.1：
- `RULES.md` 合并重复治理规则，形成 `Core Governance Layer`。
- `ChatGPT Constraint v2`、`Rule Gate`、`AIOS 协作边界` 已收敛为统一的 `Core Governance Rules`。
- Rule System 保留三层结构：Candidate Rule → Verified Pattern → Rule。
- Rule Gate 收敛为三个强制条件：GitHub 已 push、Codex 已执行、用户已确认。
- 重复行为验证保留为形成 Verified Pattern 的说明，不再作为独立强制门槛。
- `DECISIONS.md` 清理为 Final Only，只保留已确认的产品与技术决策。

本轮未修改业务代码、未修改数据库结构、未修改 `src/`、未修改 `supabase/`。

## 报错 / 修正审核路径规则同步完成

已同步报错 / 修正审核路径规则到 `docs/ai/DECISIONS.md` Final：
- 报错 / 修正审核分为管理员审核、审核库 + 陪审团制度两种路径。
- 正式库空字段补全走管理员审核，通过后允许补全。
- 正式库已有非空字段修正、多人提交冲突、字段争议、无法由管理员单人判断的修正进入审核库，并执行陪审团制度。
- 管理员终审单独建立终审记录，不写入 `jury_votes`。
- 第一版不使用“低风险 / 高风险字段分级表”作为执行规则，审核路径按“空字段补全 / 非空字段修正 / 争议修正”分流。

字段新增约束已写入 `docs/ai/RULES.md` 的 Project Rules。

`docs/ai/CURRENT_TASK.md` 已更新为继续确认陪审团制度第一版规则。

本轮只改文档，未改业务代码、数据库、`src/`、`supabase/`。

## Codex 执行协议与规则污染防护机制同步完成

- Rule Pollution Guard 已写入 `docs/ai/RULES.md`。
- Codex 自动 commit/push 协议已生效。
- 单任务原则已写入 `docs/ai/RULES.md`。
- `docs/ai/DECISIONS.md` 已标记本轮新增规则为“Rule Pollution Guard + Codex Execution Protocol 第一版”，仅记录变更来源，不新增业务规则。
- `docs/ai/CURRENT_TASK.md` 已更新为开始进入“陪审团系统数据库最小结构设计（需进入 DECISIONS.md，不进入 RULES.md）”。

本轮仅文档修改，无业务代码变更。

## 陪审团数据库最小结构第一版已完成

- 已在 `docs/ai/DECISIONS.md` 记录陪审团系统最小数据库结构第一版：`jury_votes`、`re_review_items`、`points_ledger`。
- 已在 `docs/ai/RULES.md` 补充跨项目“事实可重算”原则，不写入单项目具体实现细节。
- `docs/ai/CURRENT_TASK.md` 已更新为确认是否需要引入“自动重算积分机制”。

本轮仅文档设计，无代码与数据库变更。

## 积分可重算系统（Event Sourcing Lite）设计完成

- 已在 `docs/ai/DECISIONS.md` 记录积分系统升级为可重算模型（Event Sourcing Lite）。
- 已明确当前积分由 `points_ledger` 聚合计算，`points_ledger` 为积分唯一事实源。
- 已明确陪审团通过、重审通过、报错通过、系统奖励 / 扣减等业务行为必须写入 ledger。
- 已记录积分重算机制、时间回溯计算和 `snapshot_flag` 性能优化口径。
- 已在 `docs/ai/RULES.md` 补充跨项目事件记录、核心数据可重算、不得仅依赖最终状态的原则。
- `docs/ai/CURRENT_TASK.md` 已更新为确认是否将陪审团投票也纳入“完全事件化模型（jury_events）”。

本轮仅文档修改，无代码/数据库变更。

## 分支与环境治理恢复报告

本轮目标：恢复项目分支与环境治理，不开发业务功能，不运行数据库命令，不连接 production，不修改业务代码、migration、Vercel 配置或 Supabase 远程数据库。

已建立 / 更新的治理文档：
- `docs/governance/BRANCH_ENVIRONMENT_POLICY.md`：明确 `main = production`、`develop = development / preview`，以及 feature / fix / docs 分支默认从 `develop` 拉出并合回 `develop`。
- `docs/ai/RULES.md`：补充分支与环境治理入口，明确 Vercel production 只对应 `main`，Vercel preview / dev 只对应 `develop` 或短期 feature 分支，数据库任务必须先确认 Supabase project ref。
- `README.md` 与 `docs/README.md`：新增 AI / Codex 开始任务前必须先读 `docs/ai/RULES.md` 和环境治理文档的入口。
- `docs/database/环境信息.md`、`docs/database/数据库开发安全方案.md`、`docs/planning/工作流优化方案.md`：补充分支、Vercel、Supabase 环境对应关系和检查要求。

当前 GitHub / Git 状态盘点：
- 默认分支：本地远端引用显示 `origin/HEAD -> origin/main`，因此按当前本地可见状态判断默认分支为 `main`。`gh` CLI 在本环境不可用，GitHub repo metadata 只能部分通过连接器读取。
- `develop` 分支：远端存在 `origin/develop`，当前指向 `8233bd26`。
- PR #1：仍为 open，base=`develop`，head=`chore/dev-environment-and-bugfixes`，未合并；GitHub 连接器显示 mergeable=true。
- PR #2：已 closed 且 merged，base=`main`，head=`chore/dev-environment-and-bugfixes`，merge commit 为 `3853f5c9`。
- 当前分支 `feature/category-code-wardrobe-import` 已与远端 feature 分支整合；远端独有提交 `d3a3936` 已通过 rebase 纳入本地。
- 当前 feature 相对 `origin/main`：`origin/main` 侧有 1 个提交未在 feature 中，feature 侧有 32 个提交未在 `origin/main` 中。
- 当前 feature 相对 `origin/develop`：feature 侧有 62 个提交未在 `origin/develop` 中。
- `docs/ai`：`origin/main` 和 `origin/develop` 中均不存在；当前仅存在于 `origin/feature/category-code-wardrobe-import` 及本地 feature 分支。

当前发现的问题：
- 分支流向曾被打乱：`chore/dev-environment-and-bugfixes` 已通过 PR #2 直接进入 `main`，但 PR #1 仍打开且目标为 `develop`。
- `develop` 明显落后于 `main` 和当前 feature，无法承担 development / preview 集成分支职责。
- `feature/category-code-wardrobe-import` 混有多类内容：已进入 `main` 的业务修复历史、仍未进 `main` 的文档 / AIOS 治理、数据库设计文档、以及至少一个 migration / 业务相关差异。
- `docs/ai` 作为当前协作事实入口尚未进入 `develop` 或 `main`，导致治理规则还停留在 feature 分支。
- Vercel production / preview 与 Git 分支的实际绑定状态未在仓库中可验证，仍需用户到 Vercel Dashboard 确认。
- 本轮未运行 Supabase 命令，未检查远程 Supabase 当前 linked project，避免触碰 production。

当前不能操作的内容：
- 不删除分支。
- 不关闭 PR。
- 不改 Vercel 配置。
- 不运行数据库命令。
- 不连接 production。
- 不修改 `src/`、`supabase/migrations/`、`supabase/schema.sql`、`supabase/seed.sql`、`package.json` 或业务逻辑代码。

分支治理建议：
- PR #1 建议用户确认后关闭，理由：它的 head 分支已通过 PR #2 合入 `main`，当前 PR #1 已成为历史遗留 PR；继续保留容易让 develop 修复流程和 production 合并历史混淆。关闭前建议先决定如何把 `main` 中已上线内容回填到 `develop`。
- `docs/ai` 和本轮治理文档建议先合入 `develop`，再由 `develop` 验证后通过 PR 合入 `main`；不建议从当前 feature 直接合入 `main`。
- `feature/category-code-wardrobe-import` 剩余内容建议拆分：
  - 治理文档 / AIOS 文档：单独 PR 到 `develop`。
  - 已验证且已进入 `main` 的业务修复历史：不再重复从 feature 合并，必要时只用 `main` 回填 `develop`。
  - 未实现的陪审团 / 积分数据库设计文档：保留为设计 PR，不包含 migration。
  - 任何 `src/` 或 `supabase/migrations/` 差异：另开实现分支，等治理完成后从 `develop` 重新拉出。
- 后续 PR 流程建议：
  - 常规：`develop` -> feature / fix / docs -> PR 回 `develop` -> 验证 -> PR `develop` 到 `main`。
  - 紧急：`main` -> hotfix -> PR 到 `main`，合并后再回填 `develop`。

建议用户确认的事项：
- 是否关闭 PR #1。
- 是否创建一次“main 回填 develop”的同步 PR，用于恢复 `develop` 为 development / preview 集成基线。
- 是否先把 `docs/ai` 与 `docs/governance` 作为纯文档 PR 合入 `develop`。
- Vercel Dashboard 中 production 是否仅绑定 `main`，preview 是否绑定 `develop` / feature。
- Supabase Dashboard 中 production ref 与 development ref 是否仍分别为 `fopyjewbsvusftpqbtml` 和 `tfwejruvdahonacyldrg`。

下一步最安全的操作顺序：
1. 用户确认 Vercel 和 Supabase 双环境绑定。
2. 用户确认 PR #1 处理方式。
3. 先恢复 `develop` 基线：用明确的同步 PR 将 `main` 当前已上线内容回填到 `develop`，或按用户指定方式重建 develop。
4. 将 `docs/ai` 与治理文档以纯文档 PR 合入 `develop`。
5. 验证 develop / preview 后，再由 `develop` 发 PR 到 `main`。
6. 治理稳定后，再从 `develop` 新建业务实现分支。

## 数据库约束已最小化定义

- 已在 `docs/ai/DECISIONS.md` 补充数据库约束规则（v1），覆盖 `jury_votes`、`points_ledger`、`re_review_items` 的最小约束口径。
- 已在 `docs/ai/RULES.md` 补充跨项目数据库一致性原则：核心业务数据必须具备数据库层约束，不可仅依赖应用层逻辑保证一致性。
- `docs/ai/CURRENT_TASK.md` 已更新为进入 Codex 实现阶段（开始对接 service layer）。

本轮仅文档修改，无代码/数据库变更。

## 数据库约束对照审计结果

审计范围：仅检查仓库内当前数据库设计文件，包括 `supabase/schema.sql`、`supabase/migrations/`、`docs/database/schema.md` 和 `docs/database/数据库变更记录.md`。本轮未连接或修改实际数据库，未修改业务代码。

审计结论：
- `jury_votes`：未满足。
  - 当前 `supabase/schema.sql` 和 `supabase/migrations/` 中未发现 `jury_votes` 表定义。
  - 未发现 UNIQUE(user_id, audit_id)。
  - 未发现禁止 UPDATE vote 的约束、触发器、RLS 策略或等价机制。
  - 未发现 vote 只能为 approve / reject 的约束。
- `points_ledger`：未满足。
  - 当前 `supabase/schema.sql` 和 `supabase/migrations/` 中未发现 `points_ledger` 表定义。
  - 未发现 delta 结构。
  - 未发现禁止 UPDATE / DELETE、只允许 INSERT 的约束、触发器、RLS 策略或等价机制。
- `re_review_items`：未满足。
  - 当前 `supabase/schema.sql` 和 `supabase/migrations/` 中未发现 `re_review_items` 表定义。
  - 未发现 status CHECK 限制为 pending / voting / approved / rejected / failed。
  - 当前仓库内数据库设计尚未落地该表，因此也尚未具备防止非法状态写入的数据库层约束。

总体判断：DECISIONS.md 中的数据库约束规则（v1）目前仍是设计决策，尚未在仓库内当前数据库结构中实现。若进入实现阶段，需要新增对应 migration、约束、写入权限与不可变机制后再复审。

## 陪审团投票幂等性规则第一版完成

已补充陪审团投票幂等性规则到 `docs/ai/DECISIONS.md` Final：
- 同一用户同一审核项（user_id + audit_id）只能存在一条有效投票记录。
- 投票请求必须幂等，网络重试、前端重复点击、多端提交不得产生多条有效票。
- 相同内容重复提交应忽略；不同内容重复提交按“不允许改票”规则拒绝或返回错误。
- 后端写入为唯一真相，前端状态不可信。

已在 `docs/ai/RULES.md` 的 Project Rules 下新增陪审团制度小节，记录投票幂等性规则、防重复提交处理机制和后端写入优先原则。

`docs/ai/CURRENT_TASK.md` 已更新为确认是否需要数据库层唯一索引（user_id + audit_id）。

本轮仅文档修改，无代码 / 数据库变更。

## 陪审团投票记录与自动修改边界第一版同步完成

已同步陪审团投票记录与自动修改边界第一版到 `docs/ai/DECISIONS.md` Final：
- 陪审团投票记录应记录每个用户每次投票，不只记录最终统计结果。
- 同一用户同一审核项不允许改票，一票定稿；页面假死、误点、重复提交造成的异常先按异常处理。
- 陪审团达到通过门槛后，系统立即自动修改正式库，不再额外进入管理员终审后修改。
- 自动修改正式库时，必须记录变更前值和变更后值，并能追溯本次陪审团审核项、投票结果和修改时间。
- 自动修改失败时，重新进入陪审库，交由其他人继续审核，不静默失败，不直接标记完成。

同步处理：
- 保持“管理员终审不写入 `jury_votes`，单独建立终审记录”的规则不变。
- 保持“字段新增必须审核”的规则不变。
- 未新增未经确认的字段名、表字段、状态值。

`docs/ai/CURRENT_TASK.md` 已更新为继续确认陪审团异常处理与防刷规则。

本轮只改文档，未改业务代码、数据库、`src/`、`supabase/`。

## 陪审团制度第一版规则同步完成

已同步陪审团制度第一版规则到 `docs/ai/DECISIONS.md` Final：
- 触发条件：非空字段报错修正、多人提交冲突、字段争议。
- 通过门槛：同意票 >= 5，且同意票 > 反对票。
- 通过门槛后允许系统自动修改正式库，未达标不得修改正式库。
- 所有登录用户均可参与陪审团投票。
- Lv4 权重仅用于排序 / 展示，不影响票数，不参与自动入库判断。

同步修正：
- 已将“重审修正不得绕过审核直接改正式库”调整为“重审修正不得绕过陪审团通过门槛直接修改正式库；通过门槛后允许系统自动修改正式库。”
- 保持“管理员终审不写入 `jury_votes`，单独建立终审记录”的规则不变。
- 保持 `docs/ai/RULES.md` 不变。

`docs/ai/CURRENT_TASK.md` 已更新为继续确认陪审团投票记录与自动修改正式库的最小实现边界。

本轮只改文档，未改业务代码、数据库、`src/`、`supabase/`。
