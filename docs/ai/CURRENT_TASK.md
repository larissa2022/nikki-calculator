# 当前任务

当前任务：seal100x clothes 数据同步盘点完成后，进入 development sample write 前的状态同步与门禁确认。

## 1. 核心目标

把 `https://seal100x.github.io/nikkiup2u3/` 对应的奇迹暖暖部件数据，同步更新到 Nikki Calculator 的数据库中。

当前同步对象优先限定为：

- `public.clothes`
- 与 clothes 同步直接相关的套装映射信息：`suit_id` / `temp_suit_name`

当前不把以下内容混入本任务：

- Supabase advisor / RLS 安全修复
- schema / migration 变更
- Vercel / CI 配置
- 业务代码改动
- 用户衣柜 `user_wardrobes` 数据迁移
- pending 审核流程改造

## 2. 已确认事实

- Repo：`larissa2022/nikki-calculator`。
- `main` = production。
- `develop` = development / preview。
- GitHub 是事实源；未 push = 不存在。
- production Supabase project ref：`fopyjewbsvusftpqbtml`。
- development Supabase project ref：`tfwejruvdahonacyldrg`。
- Vercel project：`nikki-calculator`，project id：`prj_hAcrSbYudnXvrdrbqhm816yDELKO`。
- PR #48 已新增 seal100x clothes diff 只读审计脚本。
- PR #49 已新增 production SELECT-only audit 模式。
- PR #50 已新增并合并 `docs/planning/seal100x-clothes-sync-plan.md`。
- PR #52 已合并，merge commit：`ae9d72767f91240723fe8add3f0c7f26eef92ab9`。
- PR #53 已合并，merge commit：`bedfb733a98cc687806f95be1900987810d0855f`。
- 当前 open PR：本轮只读查询为空。

## 3. 已确认决策

- seal100x 是 clothes 内容同步事实源。
- 如果 seal100x 部件内容与当前数据库内容冲突，以 seal100x 为准。
- seal100x 只作为服装内容事实源，不自动作为数据库 schema、RLS、用户数据、pending 审核流程或 Vercel 配置事实源。
- 纯文档任务由 ChatGPT 通过 GitHub 连接器直接完成，不默认交给 Codex。
- 涉及脚本、代码、本地命令、测试、数据库、Supabase、migration、Vercel、env 的任务，进入 Codex 或对应工具流程。
- 真实 development sample write 需要用户单独确认。
- production write 仍禁止，除非用户后续单独明确批准。

## 4. 当前已有产物

### 4.1 只读 audit 脚本

脚本：

```text
scripts/audit/seal100x-clothes-diff.mjs
```

npm script：

```text
npm run audit:seal100x-clothes
```

当前脚本性质：

- 可拉取 seal100x upstream `wardrobe.js`。
- 可展开压缩/编码后的 wardrobe 数据。
- 可读取 Supabase `public.clothes`。
- 可输出 exact key / normalized key 差异。
- 可输出 JSON 到 `tmp/` 或 `.cache/`。
- production 模式必须显式传 `--target production --confirm-production-readonly`。
- PR #52 后可生成更可决策的 finalized sync set draft，包括 changed 字段分布、normalized source-only 分布、normalized DB-only 全量列表、suit mapping review 与候选集合。
- 不写数据库。
- 不生成 migration。
- 不修改 schema。
- 不提交 tmp JSON。

### 4.2 同步计划文档

文档：

```text
docs/planning/seal100x-clothes-sync-plan.md
```

当前用途：

- 记录 production SELECT-only audit 结果。
- 记录 source-only / changed / DB-only 初步分类。
- 记录 tags、suit_id、temp_suit_name、identity key 的策略风险。
- 记录 future database/data-sync 前置门禁。

### 4.3 development sample apply dry-run 工具

PR #53 已新增 development-only sample apply dry-run 工具。

当前性质：

- 用于 development sample apply 之前生成样本计划。
- dry-run 已覆盖 5 条 scores-only 与 2 条 stars-only candidate。
- 输出包含 before / after values 与 rollback draft。
- 当前 PR 本身不写数据库。
- 真实 development write 需要后续用户单独确认。
- 不支持 production。
- 不生成 SQL。
- 不是 apply plan。

## 5. production SELECT-only audit 摘要

来自 PR #49 / PR #50 文档记录：

- production `clothes` 总行数：`35241`。
- upstream expanded count：`36811`。
- `updated_at` 字段不存在。
- clothes 当前字段：`id, name, category, game_id, stars, tags, scores, suit_id, temp_suit_name, created_at`。

Exact key 差异：

| 类型 | 数量 |
| --- | ---: |
| source-only | 15472 |
| changed | 21324 |
| DB-only | 13902 |
| duplicate/conflict keys | 0 |

Normalized key 差异：

| 类型 | 数量 |
| --- | ---: |
| source-only | 1577 |
| changed | 35216 |
| DB-only | 7 |
| duplicate/conflict keys | 0 |

当前判断：

- 不能直接按 exact source-only `15472` 作为插入清单。
- normalized key 更接近“真实同步差异”的第一层分析依据，但仍未最终确认可作为正式匹配依据。
- changed 数量很大，必须按字段拆分，不能一批无差别覆盖。

## 6. enhanced audit / finalized sync set draft 摘要

PR #52 后，enhanced audit 已确认：

- tags format-only 占绝大多数 changed。
- semantic update candidates：
  - scores-only：`266`
  - stars-only：`2`
  - tags semantic：`15`
- normalized DB-only：`7`
- `requiresSeparateSuitMappingTask`：`true`

normalized DB-only 7 条当前建议保留并人工复核，不能自动删除：

| 分类 | game_id | 名称 | id |
| --- | ---: | --- | --- |
| 连衣裙 | 2071 | 画堂芳菲 | `custom_1778240984153` |
| 饰品 | 18356 | 素韵环缭 | `custom_1778241193278` |
| 妆容 | 154 | 幽夜之梦 | `custom_1778683634470` |
| 萤光之灵 | 4 | 云 | `custom_1778684283427` |
| 鞋子 | 8 | 童趣粉 | `custom_1779167369923` |
| 发型 | 35 | 蔷薇少女金 | `custom_1779167498004` |
| 饰品 | 18506 | 新途耀明 | `custom_1779168558277` |

suit mapping review 摘要：

| 指标 | 数量 / 状态 |
| --- | ---: |
| sourceRowsWithSuitCount | 33924 |
| sourceRowsWithoutSuitCount | 2887 |
| dbRowsWithSuitIdCount | 33372 |
| dbRowsWithTempSuitNameCount | 0 |
| requiresSeparateSuitMappingTask | true |

## 7. sample dry-run 摘要

PR #53 已将 sample dry-run tooling 合入 `develop`。

当前 dry-run candidate ids：

- scores-only：`20004`, `20015`, `20016`, `20035`, `20036`
- stars-only：`custom_1779156524128`, `custom_1779168845502`

下一步如进入真实 development sample write，只能处理上述 7 条样本：

- 5 条 scores-only
- 2 条 stars-only

禁止在同一步混入：

- tags semantic `15`
- source-only `1577` inserts
- normalized DB-only `7` cleanup
- suit mapping
- RLS security
- migration
- production apply

## 8. 当前风险

### 8.1 数据同步风险

- normalized key 是否作为正式匹配依据仍未最终确认。
- normalized source-only `1577` 是否全量插入、分批插入或先分类 review，未确认。
- scores-only `266` 与 stars-only `2` 是否可进入 development sample write，未确认。
- tags semantic `15` 是否批量处理，未确认。
- DB-only `7` 当前建议保留并人工复核，不能自动删除。
- `suit_id` / `temp_suit_name` 与 seal100x suit 的映射策略未确认，且 suit mapping 需要单独任务。
- development 数据量远小于 production，不能直接证明 production 全量同步安全。

### 8.2 数据库安全风险

Supabase advisor 已提示以下表 RLS disabled：

- `public.pending_clothes`
- `public.stages`
- `public.suits`

该风险必须另开 `database/security` 任务处理，不能混入 clothes data-sync 任务。

## 9. 职责划分

### 9.1 用户

用户负责：

- 最终确认产品口径。
- 最终确认同步策略。
- 批准是否进入 development write。
- 批准是否进入 production write。
- 批准是否 merge PR。
- 批准是否修改 main / production / Supabase / Vercel / migration。

### 9.2 ChatGPT

ChatGPT 负责：

- 只读盘点 GitHub / Vercel / Supabase。
- 整理事实、决策、偏好、未确认事项。
- 直接完成纯文档任务。
- 判断任务类型和风险等级。
- 生成 Codex 可执行指令。
- 做 PR / diff / 文档 / 只读结果复核。
- 明确 rollback 和停止条件。

ChatGPT 不负责：

- 批准正式 Rule。
- 执行 production 写库。
- 未经用户单独确认执行 development 写库。
- 执行 Supabase 写操作。
- 执行 Vercel 写操作。
- 自动 merge。
- 把未确认策略写成已确认决策。

### 9.3 Codex

Codex 负责：

- 本地读取仓库。
- 运行现有 audit 脚本。
- 修改脚本或新增工具。
- 生成 finalized sync set。
- 实现 / 运行 development-only dry-run 或 sample apply 工具。
- 运行测试 / build。
- commit / push / 创建 PR。
- 回传分支、状态、修改文件、命令结果、风险、rollback 和未确认事项。

Codex 不负责：

- 自行扩大任务范围。
- 未经确认写 production。
- 未经确认执行 Supabase 写操作。
- 提交 tmp JSON、secret、key、token、验证码、授权链接或 keyring 信息。
- 在 data-sync 任务中顺手处理 RLS security。

## 10. 推荐下一步

### 10.1 当前第一步：docs-only 状态同步

任务类型：`docs-only`

目标：让当前任务文档反映 PR #52 / PR #53 已合并，以及进入 development sample write 前的门禁。

允许：

- 只改 `docs/ai/CURRENT_TASK.md`。
- 可在单独确认后补充更新 `docs/planning/seal100x-clothes-sync-plan.md`。

禁止：

- 修改 `docs/ai/RULES.md`。
- 修改 `src/**`。
- 修改 `scripts/**`。
- 修改 `package.json` / `package-lock.json`。
- 修改 `supabase/**`。
- 生成或修改 migration。
- 写入 env / key / token / tmp JSON。
- 执行 Supabase / Vercel 写操作。
- 操作 `main`。
- merge PR。

### 10.2 后续第二步：development sample write

任务类型：`database/data-sync development`

只能在用户单独确认后执行。

目标：对 PR #53 dry-run 中的 7 条样本执行真实 development write：

- 5 条 scores-only
- 2 条 stars-only

必须先完成：

1. 确认 target 是 `development`。
2. 确认 Supabase project ref 是 `tfwejruvdahonacyldrg`。
3. 确认不碰 production ref `fopyjewbsvusftpqbtml`。
4. 确认 rollback draft 可用。
5. 确认不会提交 tmp JSON。
6. 确认不生成 migration。
7. 确认不处理 tags semantic / source-only inserts / suit mapping / RLS security。

未确认前禁止：

- `--apply`
- Supabase write
- SQL
- migration
- production apply
- Vercel write
- main 操作
- merge

## 11. 未确认事项

1. normalized key 是否作为正式匹配依据。
2. source-only `1577` 是否全部插入，还是按分类 / 套装 / 批次拆分。
3. scores-only `266` 是否允许先做 development sample write。
4. stars-only `2` 是否允许先做 development sample write。
5. tags semantic `15` 是否允许批量处理。
6. `scores` 是否允许批量覆盖。
7. `stars` 是否允许批量覆盖。
8. `name` 是否允许批量覆盖。
9. `category` 是否只作为匹配 key，还是允许被 seal100x 覆盖。
10. DB-only `7` 是否保留、标记、人工复核，还是未来清理。
11. `suit_id` / `temp_suit_name` 与 seal100x suit 的映射策略。
12. 是否先做真实 development sample write。
13. production backup、rollback、validation 方式。
14. RLS disabled 安全问题何时另开 `database/security` 任务。

## 12. 当前禁止事项

- 不直接写 production。
- 不直接写 development，除非用户单独确认 sample write。
- 不执行 migration。
- 不生成 SQL apply plan。
- 不执行 Supabase 写操作。
- 不执行 Vercel 写操作。
- 不操作 main。
- 不 merge PR，除非用户单独确认。
- 不提交 tmp JSON。
- 不把 key / token / env / 验证码 / 授权链接写入仓库或对话。
- 不把 RLS security 混入 clothes data-sync。
- 不把 suit mapping 混入 scores/stars sample write。
- 不把未确认事项写成已确认决策。
