# 当前任务看板

> 最后更新：2026-07-22 22:28（北京时间）

## 当前任务

- 完成 DB-5 自动入库贡献与积分闭环：第五位不同有效提交者触发入库时，保留来源 pending，并原子写入前 5 位贡献、每人 10 分和衣柜。

## 为什么做

- DB-3 / DB-4 已接入正式库补全和管理员仲裁，自动入库仍会删除来源 pending，尚未进入可追溯、可重算的积分审计链。

## 已经完成

- 已生成并向 development 应用窄范围 DB-5 migration，同时准备事务测试并创建 database Draft PR；RPC 参数与前端调用保持不变，未新增表、RLS 或前端功能。

## 当前进度

- 验证阶段：migration rehearsal 已成功 rollback，正式 apply 的响应虽在传输层中断，但 migration history 与 live RPC 回查确认 DB-5 已完整应用；owner、空 `search_path`、最小 grants、函数行为断言、Security Advisor、业务基线和无半完成事实已验证。development 全量 public schema dump 已生成并核验，TypeScript 类型重新生成无差异，本地 16 项测试与构建通过。事务 fixture、真实角色矩阵与双会话并发验证未获授权，尚未执行。

## 下一步

- 取得 development 事务 fixture 与双会话并发验证授权，完成 DB-5 行为验收。

## 需要负责人决定

- 是否授权仅在 development `tfwejruvdahonacyldrg` 执行合成 fixture、真实角色矩阵和第五 / 第六次双会话并发验证；fixture 必须在事务内 rollback。production、历史回填和 PR merge 仍不在范围内。

## 通用边界

- `main`、production、database / Supabase / Vercel 写入、migration、env、PR merge、历史改写、分支删除和 `RULES.md` 修改仍需分别明确确认。

## Rollback

- 应用后如需停用，新增 patch migration 将提交 RPC 切换为“只保留 pending、暂停自动入库”；不删除贡献或积分事实，错误积分只追加反向流水。
