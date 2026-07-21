# 当前任务看板

> 最后更新：2026-07-21 17:14（北京时间）

## 当前任务

- 补齐管理员仲裁入库的贡献与积分链路：仲裁通过后只奖励与最终数据一致的前 5 名有效提交者，并让贡献、每人 +10 分、pending 状态和衣柜写回保持同一事务、可追溯且可重试。

## 为什么做

- 贡献 / 积分基础事实、只读查询和正式库空字段补全链路已经落地，但管理员仲裁仍未写入贡献与积分，也缺少服务端候选一致性校验；完成这一项后，才能继续自动入库接入和重审池。

## 已经完成

- 已建立 `clothing_contributions`、`points_ledger` 及默认拒绝权限，并提供用户本人积分与公开前 3 贡献者只读面。
- 用户中心已读取权威积分汇总，不再把历史 profile 字段当作当前积分事实。
- 正式库空字段补全已在 development 实现前 5 有效提交者、每人 +5 分、pending 保留、衣柜写回和重试幂等闭环。

## 当前进度

- 调查阶段：已对齐需求、Final 决策、开发顺序和 `origin/develop` 实现，唯一下一需求确定为 DB-4 管理员仲裁接入；尚未创建或应用 migration。

## 下一步

- 负责人确认是否授权在 development 项目 `tfwejruvdahonacyldrg` 启动 DB-4，并在一个 database 主 PR 内完成 migration、角色矩阵、事务幂等、Advisor、回归和 rollback 验证。

## 需要负责人决定

- 是否批准上述 development-only DB-4：只调整 `approve_pending_clothes_arbitration`，不包含自动入库、重审池、历史回填、前端改动、production 或 PR merge。

## 通用边界

- 数据库与 Supabase 写入、migration apply 必须在确认 development project ref、影响、验证和 rollback 后单独授权；production 保持不动。
- 后续数据库实现与直接支持文档使用同一个 database 主 PR；自动入库 DB-5 和重审池不提前混入。

## Rollback

- 如 DB-4 已在 development 应用，新增 patch migration 恢复旧函数定义与最小 grant；已产生的贡献事实不删除，错误积分追加等额负数流水，任一步证据不完整即停止。
