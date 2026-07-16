# 当前任务看板

> 最后更新：2026-07-16 13:06（北京时间）

## 业务目标

- 在不破坏现有“提交 → 审核入库 → 提交者衣柜写回”主流程的前提下，让有效贡献者与积分奖励可追溯、可重算。

## 技术目标

- 先完成并验证现有提交、审核权限的安全收口；相关开发 PR 落入 `develop` 并复查前，不启动贡献与积分数据结构。

## 当前阶段

- DB-0 安全修复已应用到 development，独立 database draft PR #76 待最终审计与合并确认；未进入 production。
- `pending_clothes` 服装申请驳回入口已在独立 business draft PR #77 实现，三角色 development 业务链全部通过。
- DB-1 尚未启动；`main`、production 未操作。

## 最近完成

- 管理员完成首次驳回；普通用户重提后，最高站长看到全部 2 条申请并完成第二次驳回；普通用户再次提交后由管理员审核入库。
- 测试服装 `DB0验证服装-202607151910` 的 pending 历史为 `rejected / rejected / approved`；正式服装 ID 为 `custom_1784177220092`。
- 普通用户“我的衣柜”已显示测试服装；数据库复查 `ordinary_wardrobe_synced = true`。
- PR #77 本地 4 项测试、Vite build、Vercel Preview 和两项 PR checks 通过。
- DB-0 复查确认 `pending_clothes` RLS 与三项策略仍生效；内部衣柜写回 RPC 未开放给普通登录用户，两项管理员 RPC 保留函数内管理员守卫。

## 下一步任务

1. 分别完成 PR #76（database）与 PR #77（business）的最终只读审计，确认 diff、验证证据、Advisor 例外和 rollback。
2. 用户单独确认后，建议先合并 PR #76，再合并 PR #77；不自动 merge。
3. 合并后在 development 做一次窄范围冒烟复查；通过后再决定是否启动 DB-1。

## 阻塞与待确认

- PR #76、PR #77 merge 均未授权。
- Security Advisor 仍对两项管理员 `SECURITY DEFINER` RPC 报告 authenticated execute WARN；当前由函数内管理员守卫授权，需在 PR #76 最终审计中明确接受或调整。
- Performance Advisor 专用接口历史上存在传输失败；DB-0 相关 catalog 等价检查已保留。

## 通用边界

- 不操作 `main`、production、Supabase / Vercel 配置、env 或 DB-1；三个 PR 不混合范围，开发 PR 不自动 merge。

## Rollback

- PR #76 使用新 rollback migration 回退，不改写已应用历史；PR #77 与 docs PR #75 分别使用独立 revert。
- development 保留 3 个隔离测试账号和全部测试记录；账号密码已最终随机轮换并注销旧会话，清理需另行授权。
