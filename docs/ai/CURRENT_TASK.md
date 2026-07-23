# 当前任务看板

> 最后更新：2026-07-23 22:30（北京时间）

## 当前任务

- 完成 DB-5 自动入库贡献与积分闭环：第五位不同有效提交者触发入库时，保留来源 pending，并原子写入前 5 位贡献、每人 10 分和衣柜。

## 为什么做

- DB-3 / DB-4 已接入正式库补全和管理员仲裁；DB-5 用于修复自动入库删除来源 pending、未进入可追溯积分审计链的旧行为。

## 已经完成

- 已生成并向 development 应用窄范围 DB-5 migration，完成事务 fixture、真实登录角色和第五 / 第六位用户并发验收，并创建 database Draft PR；RPC 参数与前端调用保持不变，未新增表、RLS 或前端功能。

## 当前进度

- 待发布阶段：DB-5 已在 development 完成 migration、权限、安全、事务 fixture 和真实双请求并发验收。第五 / 第六位用户同时提交时，两次调用返回同一正式服装；最终仅形成 1 件正式服装、5 条贡献和 50 分，来源 pending 全部保留。测试数据已精确清理，持久基线恢复为验证前状态；production、历史回填和 PR merge 均未操作。

## 下一步

- 对 DB-5 database Draft PR 进行独立合并前审计。

## 需要负责人决定

- 当前无需决定；独立审计通过后，PR merge 仍需负责人另行明确授权。production、`main` 和历史回填继续不在范围内。

## 通用边界

- `main`、production、database / Supabase / Vercel 写入、migration、env、PR merge、历史改写、分支删除和 `RULES.md` 修改仍需分别明确确认。

## Rollback

- 应用后如需停用，新增 patch migration 将提交 RPC 切换为“只保留 pending、暂停自动入库”；不删除贡献或积分事实，错误积分只追加反向流水。
