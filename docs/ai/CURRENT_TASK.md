# 当前任务看板

> 最后更新：2026-07-21 22:07（北京时间）

## 当前任务

- 当前无活动任务。

## 当前进度

- 完成阶段：DB-4 管理员仲裁入库已在 development 完成自动验证和负责人业务验收，任务已收口。

## 通用边界

- `main`、production、database / Supabase / Vercel 写入、migration、env、PR merge、历史改写和分支删除仍需分别明确确认。
- DB-4 人工验收形成的贡献、积分和衣柜事实属于审计链，默认保留；development 测试账号清理属于新的数据库删除操作，不随任务收口自动执行。

## Rollback

- DB-4 如需回退，先停用仲裁入口，再以新 patch migration 恢复旧 RPC 定义与 execute grant；不改写 migration 历史，不删除贡献或积分事实，错误积分只追加等额反向流水。
