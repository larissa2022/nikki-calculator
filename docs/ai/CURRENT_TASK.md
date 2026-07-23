# 当前任务看板

> 最后更新：2026-07-23 22:50（北京时间）

## 当前任务

- 完成 DB-5 自动入库贡献与积分闭环：第五位不同有效提交者触发入库时，保留来源 pending，并原子写入前 5 位贡献、每人 10 分和衣柜。

## 为什么做

- DB-3 / DB-4 已接入正式库补全和管理员仲裁；DB-5 用于修复自动入库删除来源 pending、未进入可追溯积分审计链的旧行为。

## 已经完成

- 已生成并向 development 应用窄范围 DB-5 migration，完成事务 fixture、真实登录角色和第五 / 第六位用户并发验收；PR #97 的独立合并前审计通过。RPC 参数与前端调用保持不变，未新增表、RLS 或前端功能。

## 当前进度

- 完成阶段：DB-5 已完成 development migration、权限、安全、事务 fixture、真实双请求并发验收和 database PR 收口。第五 / 第六位用户同时提交时，两次调用返回同一正式服装；最终仅形成 1 件正式服装、5 条贡献和 50 分，来源 pending 全部保留。测试数据已精确清理，持久基线恢复为验证前状态；production、`main` 和历史回填均未操作。

## 下一步

- 调查积分与前 3 位贡献者的前端展示入口，形成最小 business / frontend 实施范围。

## 需要负责人决定

- 当前无需决定；启动下一任务时需要负责人确认积分与贡献者的展示位置。production、`main` 和历史回填继续不在范围内。

## 通用边界

- `main`、production、database / Supabase / Vercel 写入、migration、env、PR merge、历史改写、分支删除和 `RULES.md` 修改仍需分别明确确认。

## Rollback

- 应用后如需停用，新增 patch migration 将提交 RPC 切换为“只保留 pending、暂停自动入库”；不删除贡献或积分事实，错误积分只追加反向流水。
