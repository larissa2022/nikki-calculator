# 当前任务看板

> 最后更新：2026-07-19 12:27（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0、DB-1 已完成；DB-2 最小只读面已在 development 应用并合入 `develop`，正在完成合并后回读与文档收口。

## 当前阶段

- PR #83 已合入 `develop`，merge commit 为 `eec4e7e`；本地、`origin/develop` 与 GitHub 远端一致。
- development `tfwejruvdahonacyldrg` 已记录 migration `20260717050640_db2_create_read_surfaces`；合并前角色矩阵与 live catalog 已通过。
- `private_db2` 未暴露；public 仅开放两个不可写 view，DB-1 底表继续默认拒绝。

## 最近完成

- 完成 PR #83 合并前审核、merge 与远端 ancestry 验证；未操作 `main`、production、Vercel 配置或 env。
- 普通用户积分隔离、管理员仅读自己积分、公开贡献稳定前 3、匿名名与账号删除展示均已验证。
- PR #82 的长期 DB-2 设计文档已保留，重叠看板与数据库记录已按 `develop` 当前事实去重。

## 下一步任务

1. Supabase 连接器恢复后，回读 development migration、grants、两个 view / helper 与 Security / Performance Advisor，完成 DB-2 收口。
2. 只读审核刷新后的 PR #82；确认长期规划文档与已实施 DB-2 一致后，再单独决定是否 merge。
3. DB-2 收口前不进入 DB-3，不接入现有写入 RPC、前端或历史回填。

## 阻塞与待确认

- Supabase 连接器当前为传输层错误；CLI 只读回查仍受已知 TLS EOF 影响，均未产生数据库写入。
- PR #82 merge 尚未授权；Advisor 中既有 `stages` / `suits`、旧函数和旧 policy 告警不得混入修复。

## 通用边界

- 不操作 `main`、production、Vercel 配置或 env；任何新增 database / Supabase 写入和 PR merge 均需单独明确确认。

## Rollback

- DB-2 如需数据库回退，新增 rollback migration：先删除两个 public view，再删除 private helper；仅在无依赖时删除 `private_db2`。
- 不改写已应用 migration 历史，不变更 DB-1 表、数据、RLS 或 grants；发现依赖或 exposed schema 异常即停止。
