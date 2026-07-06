# 当前任务

当前任务：需求治理与执行入口文档整理。

## 本次任务边界

- 类型：docs-only。
- 目标分支：`develop`。
- 工作分支：`docs/requirements-governance`。
- 只允许修改：
  - `docs/README.md`
  - `docs/FILE_GOVERNANCE.md`
  - `docs/ai/WORKFLOWS.md`
  - `docs/ai/CURRENT_TASK.md`
  - `docs/planning/开发文档.md`
  - `docs/planning/技术实现文档.md`
- 不推进陪审团、重审、积分、贡献者、排行榜或其他业务开发。
- 不修改业务代码、数据库、Supabase、Vercel、env、migration、schema、production、`docs/ai/RULES.md` 或 `docs/ai/DECISIONS.md`。
- 不执行 Supabase / psql / SQL。
- 不操作 `main` / production。
- 不 merge PR。

## 本次目标

- 暂停业务开发后，先整理需求层、决策层、执行计划层、技术实现层和当前任务层的文档职责。
- 明确业务开发前的阅读顺序、需求治理入口和进入 Codex 修改阶段的门槛。
- 在 `WORKFLOWS.md` 中补充“需求到执行计划工作流”，但不升级为 `RULES.md` 强规则。
- 形成 docs-only PR 到 `develop`。

## 文档分层判断

- 需求层：`docs/requirements/产品设计书.md`、`docs/requirements/需求文档.md`。
- 决策层：`docs/ai/DECISIONS.md`，仅保存 Final 产品 / 技术决策。
- 执行计划层：`docs/planning/开发文档.md`。
- 技术实现层：`docs/planning/技术实现文档.md`。
- 当前任务层：`docs/ai/CURRENT_TASK.md`。
- 操作手册层：`docs/ai/WORKFLOWS.md`。

## 当前状态

- 本轮只做文档治理和入口整理。
- 业务开发暂停。
- 未执行 database / Supabase / SQL / Vercel 操作。
- 未触碰 production。
- 未修改 `docs/ai/RULES.md`。
- 未修改 `docs/ai/DECISIONS.md`。
