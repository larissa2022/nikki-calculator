# 当前任务看板

> 最后更新：2026-07-14 12:40（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- 先只读审计 `clothing_contributions` + `points_ledger` 的最小数据模型和现有 RPC 接入点，形成可拆分、可验证、可回滚的数据库方案。

## 当前阶段

- 积分 / 贡献者当前 migration、生成类型和入库 / 补全 RPC 已完成只读审计；第一阶段拆分、验证与业务验收手册已写入规划文档。
- 旧 PR #17 不按原方案恢复，任何 database 实现仍需从 `develop` 重新授权和拆分。

## 最近完成

- 已确认自动入库删除来源 pending、前 5 排名不稳定、管理员候选需服务端校验，以及本地 schema / types 落后等实施门禁。

## 下一步任务

- 用户确认“自动入库来源保留、跨来源重复计分、账号删除后审计保留”三项边界；确认后再授权 development 只读前检。

## 阻塞与待确认

- 待确认：自动入库保留 approved pending 或不可变快照；跨来源能否重复计分；账号删除后如何匿名化保留贡献 / 流水。
- development 前检仍需另行确认 project ref `tfwejruvdahonacyldrg`、只读 SQL 范围和输出；PR #75 merge 尚未授权。

## 通用边界

- 当前仅允许 docs 规划；不操作 `main`、production、database、Supabase、Vercel、env 或 migration；开发 PR 不自动 merge。

## Rollback

- 规划 PR 可关闭或独立 revert；后续数据库工作按最小独立 PR 执行，development 验证失败时停止，不进入 production。
