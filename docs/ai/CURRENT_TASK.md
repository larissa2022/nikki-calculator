# 当前任务

当前任务：seal100x clothes 数据同步盘点与执行前收口。

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
- 当前 open PR：开始本任务前 GitHub 只读查询为空。

## 3. 已确认决策

- seal100x 是 clothes 内容同步事实源。
- 如果 seal100x 部件内容与当前数据库内容冲突，以 seal100x 为准。
- seal100x 只作为服装内容事实源，不自动作为数据库 schema、RLS、用户数据、pending 审核流程或 Vercel 配置事实源。
- 纯文档任务由 ChatGPT 通过 GitHub 连接器直接完成，不默认交给 Codex。
- 涉及脚本、代码、本地命令、测试、数据库、Supabase、migration、Vercel、env 的任务，进入 Codex 或对应工具流程。

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

- 只读。
- 拉取 seal100x upstream `wardrobe.js`。
- 展开压缩/编码后的 wardrobe 数据。
- 读取 Supabase `public.clothes`。
- 输出 exact key / normalized key 差异。
- 可输出 JSON 到 `tmp/` 或 `.cache/`。
- 不写数据库。
- 不生成 migration。
- 不修改 schema。
- production 模式必须显式传 `--target production --confirm-production-readonly`。

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
- normalized key 更接近“真实同步差异”的第一层分析依据，但仍需生成 finalized sync set 草案后再决定。
- changed 数量很大，必须按字段拆分，不能一批无差别覆盖。

## 6. 当前风险

### 6.1 数据同步风险

- seal100x 数据结构与当前数据库字段不完全一致，需要映射。
- `tags` 差异可能影响筛选、展示和分类辅助逻辑。
- `suit_id` / `temp_suit_name` 与 seal100x suit 数据的映射策略未确认。
- DB-only 数据可能包含本地修正、历史遗留、玩家录入或源数据缺口，不能默认删除。
- development 数据量远小于 production，不能直接证明全量同步安全。

### 6.2 数据库安全风险

Supabase advisor 已提示以下表 RLS disabled：

- `public.pending_clothes`
- `public.stages`
- `public.suits`

该风险必须另开 `database/security` 任务处理，不能混入 clothes data-sync 任务。

## 7. 职责划分

### 7.1 用户

用户负责：

- 最终确认产品口径。
- 最终确认同步策略。
- 批准是否进入 development write。
- 批准是否进入 production write。
- 批准是否 merge PR。
- 批准是否修改 main / production / Supabase / Vercel / migration。

### 7.2 ChatGPT

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
- 执行 Supabase 写操作。
- 执行 Vercel 写操作。
- 自动 merge。
- 把未确认策略写成已确认决策。

### 7.3 Codex

Codex 负责：

- 本地读取仓库。
- 运行现有 audit 脚本。
- 修改脚本或新增工具。
- 生成 finalized sync set。
- 实现 development-only dry-run / sample apply 工具。
- 运行测试 / build。
- commit / push / 创建 PR。
- 回传分支、状态、修改文件、命令结果、风险、rollback 和未确认事项。

Codex 不负责：

- 自行扩大任务范围。
- 未经确认写 production。
- 未经确认执行 Supabase 写操作。
- 提交 tmp JSON、secret、key、token、验证码、授权链接或 keyring 信息。
- 在 data-sync 任务中顺手处理 RLS security。

## 8. 推荐下一步

下一步应进入 `database/data-sync planning`，但第一阶段仍然只读：

目标：生成 finalized sync set 草案。

需要回答：

1. normalized source-only `1577` 中哪些是真正新增部件。
2. changed `35216` 中各字段差异分布：`name` / `stars` / `scores` / `tags` / mixed。
3. `tags` 差异是否可以拆出安全子集。
4. normalized DB-only `7` 是哪些，是否保留。
5. `suit_id` / `temp_suit_name` 如何映射 seal100x suit。
6. 是否需要 source context report，但不新增 DB 字段。

允许：

- Codex 运行只读 audit。
- 生成本地 `tmp/` 或 `.cache/` 报告。
- 回传摘要。

禁止：

- 写数据库。
- migration。
- production apply。
- Vercel 写操作。
- main 操作。
- merge。
- 提交 tmp 报告。

## 9. 未确认事项

1. 是否以 normalized key 作为 finalized sync set 的主匹配依据。
2. source-only 是否全部插入，还是按分类 / 套装 / 批次拆分。
3. changed 中哪些字段允许以 seal100x 覆盖。
4. `tags` 是否允许批量覆盖。
5. `scores` 是否允许批量覆盖。
6. `stars` 是否允许批量覆盖。
7. `name` 是否允许批量覆盖。
8. `category` 是否只作为匹配 key，还是允许被 seal100x 覆盖。
9. DB-only 是否保留、标记、人工复核，还是未来清理。
10. `suit_id` / `temp_suit_name` 与 seal100x suit 的映射策略。
11. 是否先做 development sample write。
12. production backup、rollback、validation 方式。
13. RLS disabled 安全问题何时另开 `database/security` 任务。

## 10. 当前禁止事项

- 不直接写 production。
- 不直接写 development，除非用户单独确认 sample write。
- 不执行 migration。
- 不执行 Supabase 写操作。
- 不执行 Vercel 写操作。
- 不操作 main。
- 不 merge PR，除非用户单独确认。
- 不混合 docs / database/data-sync / database/security / config/ci / business 变更。
