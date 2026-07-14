# 当前任务看板

> 最后更新：2026-07-14 12:52（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- 先只读审计 `clothing_contributions` + `points_ledger` 的最小数据模型和现有 RPC 接入点，形成可拆分、可验证、可回滚的数据库方案。

## 当前阶段

- 积分 / 贡献者当前 migration、生成类型和入库 / 补全 RPC 已完成只读审计；三项产品与技术边界已确认为 Final，并同步到决策、规划和业务验收手册。
- 旧 PR #17 不按原方案恢复，任何 database 实现仍需从 `develop` 重新授权和拆分。

## 最近完成

- 已确认自动入库保留来源 pending 并标记 `approved`，不可变快照不替代来源记录。
- 已确认同一次初始入库每个用户只奖励一次；后续独立有效行为可再次奖励，每个来源事件必须幂等。
- 已确认账号删除后保留贡献和积分流水，解除身份关联并统一显示“已注销用户”。

## 下一步任务

- 另行授权 development project ref `tfwejruvdahonacyldrg` 的只读前检，并在执行前确认 SQL 范围、输出、失败处理和 rollback。

## 阻塞与待确认

- development 只读前检尚未授权；SQL 范围、输出、失败处理和 rollback 仍需在执行前确认。
- PR #75 merge 尚未授权。

## 通用边界

- 当前仅允许 docs 规划；不操作 `main`、production、database、Supabase、Vercel、env 或 migration；开发 PR 不自动 merge。

## Rollback

- 规划 PR 可关闭或独立 revert；后续数据库工作按最小独立 PR 执行，development 验证失败时停止，不进入 production。
