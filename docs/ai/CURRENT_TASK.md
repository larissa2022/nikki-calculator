# 当前任务看板

> 最后更新：2026-07-17 08:06（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0 与 DB-1 已完成；两张基础事实表已合入 `develop` 并通过 development 复查，尚未接入现有 RPC、public view、前端或历史回填。

## 当前阶段

- PR #80 已于 2026-07-17 07:52 合入 `develop`，merge commit 为 `4965c1d`；本地、`origin/develop` 与 GitHub 远程一致。
- development `tfwejruvdahonacyldrg` 中 migration `20260716132522` 已记录，两张事实表仍为空，RLS、grants、约束、索引与既有函数链复查通过。
- merge commit 对应的 Vercel Preview 因平台 GitHub 集成事件延迟后已于 08:04 `READY`，GitHub 的 Vercel 与 Preview Comments 检查均成功。

## 最近完成

- PR #80 合并后回读确认两表共 18 个字段、17 个约束、11 个索引，0 policy、0 trigger、0 行；客户端角色无直接表权限，`service_role` 仅 `SELECT / INSERT`。
- Security / Performance Advisor 对 DB-1 仍仅有 4 项预期 INFO，无新增 WARN / ERROR；既有 4 个相关函数保持存在。
- development 类型重新生成一致，4 / 4 测试和 Vite build 通过；`main`、production、业务数据、Vercel 配置和 env 均未操作。

## 下一步任务

1. 准备独立 DB-2 最小只读面的设计与只读预审：只评审“用户读自己的积分”和“贡献者公开展示候选”两个接口。
2. 明确 Data API 暴露、`security_invoker`、grants、anon / authenticated / admin / super admin 角色矩阵、失败处理和 rollback；取得数据库写入单独授权后再创建 migration。
3. DB-2 不修改现有写入 RPC，不接入前端，不做历史回填；上述范围之外另行拆分。

## 阻塞与待确认

- DB-1 无技术阻塞，已正式收口；DB-2 尚未取得 database / Supabase 写入授权。
- Advisor 中既有 `stages` / `suits` RLS、旧函数和旧 policy 告警不属于 DB-1 / DB-2 最小只读面，不得顺手混入。

## 通用边界

- 不操作 `main`、production、Vercel 配置或 env；任何 DB-2 migration / Supabase 写入和 PR merge 均需用户单独明确确认。

## Rollback

- DB-1 如需回退且两表为空、无下游依赖，新增 rollback migration，先删除 `points_ledger`，再删除 `clothing_contributions`；若已有数据或依赖则停止，不直接删表。
- 不改写已应用 migration 历史；development 保留 3 个隔离测试账号和全部测试记录，清理需另行授权。
