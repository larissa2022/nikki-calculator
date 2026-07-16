# 当前任务看板

> 最后更新：2026-07-16 14:22（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- DB-0 已完成，DB-1 基础事实表设计已审定；实现仍需单独 database 授权，不接入现有 RPC、public view 或历史回填。

## 当前阶段

- PR #76（database）、PR #77（business）和收口 PR #78（docs）已依次合入 `develop`，DB-0 权限与驳回业务链完成。
- 合并后 development 数据库、页面、衣柜、构建和部署状态冒烟通过。
- DB-1 字段、约束、RLS 默认拒绝、验证矩阵与 rollback 门禁已完成文档审定；migration 和 development 写入尚未启动，`main`、production 未操作。

## 最近完成

- PR #76 合并提交 `da7d6ce`、PR #77 合并提交 `5136818` 均已确认进入 `origin/develop`。
- PR #78 合并提交 `a4e53ee` 已确认进入 `origin/develop`，DB-0 合并后证据完成收口。
- `pending_clothes` RLS、3 条策略、migration、测试申请终态和衣柜写回复查通过；管理员 RPC 保留函数内角色守卫。
- 最新 `develop` 的 4 项测试、Vite build、Vercel deployment、页面数据加载及浏览器控制台检查通过。
- DB-1 明确只建立空的贡献 / 积分事实表；不复制积分字段，不混入 view、RPC、既有数据回填或 `clothes` 业务唯一索引。

## 下一步任务

1. 审核并合并 DB-1 设计审定文档 PR；不在文档 PR 中创建或应用 migration。
2. 文档口径进入 `develop` 且用户明确授权后，从最新 `develop` 创建独立 database PR，仅在 development `tfwejruvdahonacyldrg` 验证。
3. DB-1 通过结构、角色、约束、Advisor、回归和 rollback 门禁前，不进入只读查询面、RPC 接入、前端展示或历史回填。

## 阻塞与待确认

- DB-1 设计审定文档 PR 待审核 / 合并，database 实现尚未取得单独授权。
- 两项管理员 `SECURITY DEFINER` RPC 的 authenticated execute WARN 已在 DB-0 审计中接受；函数内管理员守卫继续作为门禁。
- Advisor 专用接口仍有传输失败；DB-0 catalog、角色矩阵和业务冒烟证据已保留。

## 通用边界

- 不操作 `main`、production、Supabase / Vercel 配置或 env；DB-1 migration / development 写入必须独立授权、独立 PR、development 先验证。

## Rollback

- PR #76 通过新的 rollback migration 回退，PR #77 通过独立 revert 回退；不改写已应用 migration 历史。
- DB-1 设计文档可独立 revert；未来 database PR 如已应用，只能用新的 rollback migration 回退。
- development 保留 3 个隔离测试账号和全部测试记录；清理需另行授权。
