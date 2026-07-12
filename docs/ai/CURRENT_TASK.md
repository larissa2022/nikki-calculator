# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 业务目标

保持仓库轻量、可理解、可恢复：保留仍有运行、审计或回滚价值的文件，删除中间产物和空文档；清理已合并分支，同时保护 `main` 与 `develop` 并明确二者发布进度。

## 当前状态

- 已删除 13 个 seal100x 中间产物，共 1,319,798,714 字节。
- 保留 production 前备份、完整回滚 SQL、255 条分数备份和三份用户 before / after 历史。
- 已删除空的 `TASK_QUEUE.md`；历史证据、测试清单、决策和规则文档继续保留。
- 已删除本地废弃分支 29 个、远端废弃分支 30 个；`main`、`develop` 均未删除。
- 本地 `main` 已同步到 `origin/main`；本地 `develop` 与 `origin/develop` 一致。
- 远端分支进度：`main` 独有 17 个提交，`develop` 独有 28 个提交，不能使用 fast-forward 直接互相覆盖。

## 保留分支

- `main`、`develop`：永久保护。
- 3 个 contributions / points 数据库草案分支：尚无合并证据，暂不删除。
- `docs/streamline-codex-approval-workflow`：尚无合并证据，暂不删除。
- `revert/pr-35-release`：尚无合并证据，暂不删除。

## 下一步

1. 将当前有用改动按 docs/config、审计工具、业务文案拆分验证，避免混入同一 PR。
2. 合并到 `develop` 后，重新执行 `develop → main` 发布审计。
3. `main` 同步必须走发布 PR；未经单独确认不 merge，不强制改写任何保护分支。

## 当前边界

- `tmp/**` 只留本地并已加入忽略，不得提交。
- 不删除没有合并证据的分支。
- 不直接 push `main` / `develop`，不 merge PR，不操作 production。
