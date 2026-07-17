# 当前任务看板

> 最后更新：2026-07-17 13:21（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0、DB-1 已完成；DB-2 最小只读面已在 development 应用并通过自动角色矩阵，尚未合入 `develop`。

## 当前阶段

- development `tfwejruvdahonacyldrg` 已记录 migration `20260717050640_db2_create_read_surfaces`。
- `private_db2` 未暴露；public 只开放“登录用户读自己积分”和“贡献者安全公开前 3”两个不可写 view。
- DB-1 底表继续默认拒绝，现有 RPC、前端、历史数据和 production 均未修改。

## 最近完成

- 完成事务 rehearsal、migration apply、Data API 与 anon / 普通用户 / admin / super admin 角色矩阵。
- 普通用户正负流水汇总、管理员仅读自己积分、公开贡献稳定前 3、匿名名与账号删除展示均通过。
- fixture 已 rollback，两张事实表仍为 0 行；Advisor 无 DB-2 新风险，schema / types 已刷新。

## 下一步任务

1. 审核独立 DB-2 database PR 的 migration、生成物、角色矩阵和 rollback；确认后再单独授权 merge。
2. 合并后回读 `develop` 与 development migration / grants / Advisor；PR #82 需先刷新重叠看板和数据库记录再决定是否保留。
3. DB-2 收口前不进入 DB-3，不接入现有写入 RPC、前端或历史回填。

## 阻塞与待确认

- DB-2 database 变更尚未合入；development 已 apply，GitHub `develop` 仍需通过独立 PR 对齐。
- CLI dry-run 受连接池 EOF / DNS 失败影响；事务 rehearsal、连接器 apply 和 live catalog 已完成，失败记录保留。
- Advisor 中既有 `stages` / `suits`、旧函数和旧 policy 告警不属于 DB-2，不得混入修复。

## 通用边界

- 不操作 `main`、production、Vercel 配置或 env；DB-2 PR merge 仍需用户再次明确确认。

## Rollback

- DB-2 已应用时新增 rollback migration：先删除两个 public view，再删除 private helper；仅在无依赖时删除 `private_db2`。
- 不改写已应用 migration 历史，不变更 DB-1 表、数据、RLS 或 grants；发现依赖或 exposed schema 异常即停止。
