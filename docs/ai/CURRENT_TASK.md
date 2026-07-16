# 当前任务看板

> 最后更新：2026-07-16 23:38（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0 已完成；DB-1 两张基础事实表已在 development 落地并验证，不接入现有 RPC、public view、前端或历史回填。

## 当前阶段

- PR #79（DB-1 设计审定 docs）已合入 `develop`；独立 DB-1 database 分支已创建并仅写入 development `tfwejruvdahonacyldrg`。
- migration `20260716132522` 已应用：`clothing_contributions` 与 `points_ledger` 均为空表、RLS 默认拒绝，客户端角色无直接权限，`service_role` 仅可读写新增事实。
- 独立 database PR #80 的 migration、生成物与验证已完成，已转为 ready 且 Preview checks 通过；`main`、production、现有 RPC、业务数据和 Vercel 配置均未操作。

## 最近完成

- development 预检、回滚预演、单 migration dry-run 和安全 apply 完成；两表共 18 个字段、17 个约束和 11 个索引，约束矩阵回滚后仍为 0 行。
- 完整 schema dump 仅新增 131 行 DB-1 内容；Security / Performance Advisor 对 DB-1 仅有 4 项预期 INFO，无新增 WARN / ERROR。
- 生成类型、实时权限与既有 4 个业务函数回读、4 项测试和 Vite build 通过；数据库变更记录与 schema 摘要已更新。

## 下一步任务

1. 完成 PR #80 的最终只读审核；用户再次明确确认后才可 merge。
2. 合并后复查 `origin/develop`、migration history、两张空表和 Preview checks，再决定 DB-1 是否正式收口。
3. DB-1 合并后复查通过前，不进入 DB-2、只读查询面、RPC 接入、前端展示或历史回填。

## 阻塞与待确认

- 当前无 DB-1 技术阻塞；PR #80 merge 仍待用户单独确认。
- Advisor 中既有 `stages` / `suits` RLS、旧函数和旧 policy 告警不属于 DB-1；不得混入本 PR 修复。

## 通用边界

- 不操作 `main`、production、Supabase / Vercel 配置或 env；DB-1 仅限 development 和独立 PR，PR merge 仍需用户再次明确确认。

## Rollback

- DB-1 如需回退且两表为空、无下游依赖，新增 rollback migration，先删除 `points_ledger`，再删除 `clothing_contributions`；若已有数据或依赖则停止，不直接删表。
- 不改写已应用 migration 历史；development 保留 3 个隔离测试账号和全部测试记录，清理需另行授权。
