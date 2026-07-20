# 当前任务看板

> 最后更新：2026-07-19 19:00（北京时间）

## 当前状态

- 当前无活动任务。
- DB-0、DB-1、DB-2 已在 development 完成并合入 `develop`；DB-2 合并后远程回读与长期规划文档均已收口。

## 通用边界

- 不预设下一条业务主线；新任务开始前重新确认目标、范围、验收、环境和 rollback。
- 不自动操作 `main`、production、database / Supabase、Vercel、env、PR merge、历史改写或分支删除。

## Rollback

- 本看板收口如需撤销，关闭对应 docs PR；合并后通过 revert 文档提交恢复。
- DB-2 数据库回退仍须新增 rollback migration，不改写已应用 migration 历史；具体顺序以数据库变更记录为准。
