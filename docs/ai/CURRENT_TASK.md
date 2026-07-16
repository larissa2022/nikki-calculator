# 当前任务看板

> 最后更新：2026-07-16 23:02（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0 已完成；DB-1 两张基础事实表已在 development 落地并验证，不接入现有 RPC、public view、前端或历史回填。

## 当前阶段

- PR #79（DB-1 设计审定 docs）已合入 `develop`；独立 DB-1 database 分支已创建并仅写入 development `tfwejruvdahonacyldrg`。
- migration `20260716132522` 已应用：`clothing_contributions` 与 `points_ledger` 均为空表、RLS 默认拒绝，客户端角色无直接权限，`service_role` 仅可读写新增事实。
- 独立 database 草稿 PR #80 已发布且当前可合并、检查通过；因生成物缺口仍保持草稿。`main`、production、现有 RPC、业务数据和 Vercel 配置均未操作。

## 最近完成

- PR #79 合并提交 `0b023d6` 已确认进入 `develop`，DB-1 的字段、约束、权限和 rollback 口径生效。
- development 预检、事务回滚预演、单 migration dry-run 和安全 apply 完成；首次连接 EOF 未产生远端状态后重试成功。
- 两表共 18 个字段、17 个约束和 11 个索引完成 live catalog 复查；6 个外键均有索引，约束矩阵执行后完整回滚，两表仍为 0 行。
- Security Advisor 仅有 2 项预期 INFO；生成类型、4 项测试和 Vite build 通过，数据库变更记录与 schema 摘要已更新。

## 下一步任务

1. 审核独立 DB-1 database 草稿 PR #80；因完整 `supabase/schema.sql` 尚未刷新，暂不转为 ready、暂不合并。
2. 按 Supabase 官方建议通过 session pooler 重新执行 schema dump；数据库密码只由用户在本机 shell 安全提供，不在对话、日志或仓库中传递，随后确认 dump 只反映已应用 migration。
3. DB-1 PR 通过完整生成物门禁并由用户另行确认合并前，不进入 DB-2、只读查询面、RPC 接入、前端展示或历史回填。

## 阻塞与待确认

- 本机代理 / DNS 将 Supabase database 与 pooler 主机解析到 `198.18.0.x` fake-IP；直连 `pg_dump` 被关闭，session pooler 可达但当前 shell 没有数据库密码。继续需要用户在本机安全提供 development 数据库密码，或在本机代理中恢复 Supabase 数据库主机的正常连接。
- 所有失败尝试仅写入 0 字节系统临时文件；仓库内 `supabase/schema.sql` 未被覆盖，未提交空文件或伪造生成结果。
- Performance Advisor 与个别回归查询也受同类传输失败影响；已保留 live catalog 外键索引证据和 migration 静态范围，但该缺口需在 PR 审核中明确。
- 两项既有管理员 `SECURITY DEFINER` RPC 的 authenticated execute WARN 已在 DB-0 审计中接受；DB-1 未修改这些函数。

## 通用边界

- 不操作 `main`、production、Supabase / Vercel 配置或 env；DB-1 仅限 development 和独立 PR，PR merge 仍需用户再次明确确认。

## Rollback

- DB-1 如需回退且两表为空、无下游依赖，新增 rollback migration，先删除 `points_ledger`，再删除 `clothing_contributions`；若已有数据或依赖则停止，不直接删表。
- 不改写已应用 migration 历史；development 保留 3 个隔离测试账号和全部测试记录，清理需另行授权。
