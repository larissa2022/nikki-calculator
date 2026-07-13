# 当前任务看板

> 最后更新：2026-07-13 23:44（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- 先只读审计 `clothing_contributions` + `points_ledger` 的最小数据模型和现有 RPC 接入点，形成可拆分、可验证、可回滚的数据库方案。

## 当前阶段

- PR #74 已合并到 `develop`，草稿恢复缺陷已收口；积分 / 贡献者进入只读设计与数据库门禁准备阶段。
- 已关闭的 PR #17 不按原方案恢复，后续从 `develop` 重新拆分最小任务。

## 最近完成

- `BUG-20260625-004` 完成本地、Preview、development 登录用户验收并关闭；PR #74 合并提交为 `ffbc880`。

## 下一步任务

- 只读核对现有 migration、生成类型与入库 / 补全 RPC，输出积分 / 贡献者第一阶段说明文档、拆分顺序、验证步骤和 rollback；不创建或执行 migration。

## 阻塞与待确认

- 任何 database / Supabase / migration 实现均需另行确认 development project ref、影响范围、前后检查和 rollback。
- 设计需先收口 `source_pending_id`、幂等去重、RLS / grants、公开读取边界及 `game_id = N` 的计分唯一性。

## 通用边界

- 当前仅允许只读审计和 docs 规划；不操作 `main`、production、database、Supabase、Vercel、env 或 migration；开发 PR 不自动 merge。

## Rollback

- 规划 PR 可直接关闭；后续数据库工作按最小独立 PR 执行，development 验证失败时停止，不进入 production。
