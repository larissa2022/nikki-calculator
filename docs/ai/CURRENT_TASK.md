# 当前任务看板

> 最后更新：2026-07-17 12:41（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0、DB-1 已完成；DB-2 最小只读面的设计与 development 只读预检已完成，尚未创建或应用 migration。

## 当前阶段

- PR #81 已于 2026-07-17 12:32 合入 `develop`，merge commit 为 `0d84d23`；DB-1 已正式收口。
- development `tfwejruvdahonacyldrg` 的 DB-1 两表仍为 0 行、RLS 默认拒绝、客户端无底表权限；14 条 migration 与项目状态正常。
- DB-2 审定为非 exposed `private_db2` helper + public `security_invoker / security_barrier` 只读 view，不放宽底表 grants 或 policy。

## 最近完成

- 完成 DB-2 同名对象、schema、Data API、默认 ACL、profile 展示前提、Advisor 与角色风险只读预检；未写数据库。
- 明确 `user_points_summary` 仅返回登录用户自己的总分；`clothing_contributors_public` 仅公开初始入库稳定前 3 的安全字段。
- 角色矩阵、失败处理、事务 fixture、Advisor 门禁和 rollback 顺序已写入开发、技术与数据库记录文档。

## 下一步任务

1. 单独授权 DB-2 database PR 与 development `tfwejruvdahonacyldrg` 写入后，创建且只应用一个 DB-2 migration；不进入 DB-3。
2. apply 前确认 Dashboard / Management API 的 exposed schemas 不含 `private_db2`；完成 rehearsal、dry-run、角色矩阵、事务 fixture rollback 和 Advisor 复查。
3. 验证通过后更新 schema / types / 记录并提交独立 database PR；PR merge 仍需再次明确确认。

## 阻塞与待确认

- DB-2 尚未取得 database / Supabase 写入授权；`private_db2` 未暴露的 Dashboard 配置也尚未确认。
- 既有 `stages` / `suits` RLS、旧函数、profiles / user_wardrobes policy 告警不属于 DB-2，不得混入修复。

## 通用边界

- 不操作 `main`、production、现有写入 RPC、业务数据、前端、历史回填、Vercel 配置或 env；database apply 与 PR merge 分别授权。

## Rollback

- DB-2 未应用时关闭 / revert database PR；已应用后新增 rollback migration，先删 public view，再删 private helper，仅在 schema 为空且无依赖时删 `private_db2`。
- 不改写已应用 migration 历史，不变更 DB-1 表、数据、RLS 或 grants；发现依赖或 exposed schema 异常即停止。
