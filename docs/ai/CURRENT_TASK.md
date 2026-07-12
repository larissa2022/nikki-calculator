# 当前任务看板

> 最后更新：2026-07-13（北京时间）。

## 当前状态

- 当前无活动任务。
- 具体业务目标、技术目标、当前阶段、最近完成、下一步任务和阻塞，由下一个任务窗口根据本轮已确认需求填写。

## 通用边界

- 本看板不构成执行授权。
- docs、business、database、config、release 不混入同一任务，除非用户明确授权。
- PR merge、`main`、production、database / Supabase / Vercel 写入、env、migration、分支删除和修改 `RULES.md` 均需单独确认。

## Rollback

- 本看板修改在 merge 前可关闭对应 PR；merge 后通过独立 revert PR 回滚。
- 具体业务、数据库或 production 任务必须在各自任务中单独定义 rollback。
