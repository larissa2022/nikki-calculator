# 当前任务看板

> 最后更新：2026-07-14 13:08（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- 先只读审计 `clothing_contributions` + `points_ledger` 的最小数据模型和现有 RPC 接入点，形成可拆分、可验证、可回滚的数据库方案。

## 当前阶段

- development `tfwejruvdahonacyldrg` 只读前检已完成并保留记录；未执行任何写 SQL、migration 或配置修改。
- migration 与本地 12 条记录一致，目标基础表尚不存在，业务重复键为 0；但现有 RLS / RPC 权限门禁未通过。
- 旧 PR #17 不按原方案恢复，任何 database 实现仍需从 `develop` 重新授权和拆分。

## 最近完成

- `clothes(category, game_id)` 重复组、空编号和非数字编号均为 0；2 条 pending 无匿名或孤儿用户关联。
- 确认 `pending_clothes` 未启用 RLS，且 `add_clothes_to_submitter_wardrobes`、管理员仲裁和正式库补全 RPC 可由 `anon` 执行。
- Security Advisor 返回 4 个 ERROR、31 个 WARN；live types 比本地多出 `complete_existing_clothes_from_pending`。

## 下一步任务

- 另行授权 DB-0 development 安全修复方案与独立 database PR：补齐 `pending_clothes` RLS，收紧高权限 RPC grants，并完成角色矩阵和 Advisor 复查；通过前不进入 DB-1。

## 阻塞与待确认

- DB-0 安全修复尚未授权；Performance Advisor 因连续两次连接传输失败仍需复查。
- PR #75 merge 尚未授权。

## 通用边界

- 当前只读前检已停止；不操作 `main`、production、database 写入、Supabase 配置、Vercel、env 或 migration；开发 PR 不自动 merge。

## Rollback

- 本次无数据库写入，不需要数据 rollback；文档记录可独立 revert。后续修复按最小独立 PR 执行，development 验证失败时停止，不进入 production。
