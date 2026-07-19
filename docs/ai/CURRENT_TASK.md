# 当前任务看板

> 最后更新：2026-07-19 13:01（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0、DB-1、DB-2 已在 development 完成；DB-2 最小只读面已合入 `develop` 并通过合并后远程回读。

## 当前阶段

- development `tfwejruvdahonacyldrg` 已记录 `20260717050640_db2_create_read_surfaces`，两个 private helper 与两个 public 只读 view 的定义、权限和安全选项均与 migration 一致。
- anon / authenticated 仅获得设计内的最小读取能力；DB-1 底表继续拒绝客户端直读，public view 不可写。
- Security / Performance Advisor 均无 DB-2 新增 WARN / ERROR；既有对象告警不混入本次修复。

## 最近完成

- PR #83 已合入 `develop` 并完成 GitHub ancestry 与 development 合并后回读；未操作 `main`、production、Vercel、env 或数据库写入。
- PR #82 已去除重叠记录，仅保留 DB-2 长期规划文档；当前仍停在单独 merge 确认前。

## 下一步任务

1. 等待用户单独决定是否 merge PR #82 的长期规划文档。
2. PR #82 处理完成前不进入 DB-3；新阶段需重新确认范围、development 验证和 rollback。

## 阻塞与待确认

- PR #82 merge 尚未授权。
- Advisor 中既有 `stages` / `suits`、旧 public 函数和旧 policy 告警不属于 DB-2，需另立任务处理。

## 通用边界

- 不操作 `main`、production、Vercel 配置或 env；任何 database / Supabase 写入和 PR merge 均需单独明确确认。

## Rollback

- DB-2 如需数据库回退，新增 rollback migration：先删除两个 public view，再删除 private helper；仅在无依赖时删除 `private_db2`。
- 不改写已应用 migration 历史，不变更 DB-1 表、数据、RLS 或 grants；发现依赖或 exposed schema 异常即停止。
