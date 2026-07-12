# 当前任务看板

> 最后核对：2026-07-12（北京时间）。

## 业务目标

保持仓库轻量、可理解、可恢复：保留仍有运行、审计或回滚价值的文件，删除中间产物和空文档；清理已合并分支，同时保护 `main` 与 `develop` 并明确二者发布进度。

## 当前状态

- 已删除 13 个 seal100x 中间产物，共 1,319,798,714 字节。
- 保留 production 前备份、完整回滚 SQL、255 条分数备份和三份用户 before / after 历史。
- 已删除空的 `TASK_QUEUE.md`；历史证据、测试清单、决策和规则文档继续保留。
- 已删除本地废弃分支 39 个、远端废弃分支 40 个；`main`、`develop` 均未删除。
- PR #56～#58 已合并到 `develop`，三个临时分支已删除。
- PR #59 已合并到 `main`；`develop` 已完整进入 `main` 历史，两个保护分支文件树一致。

## 保留分支

- `main`、`develop`：永久保护。
- `db-contributions-points-schema`：保留最新 contributions / points 数据库草案；两个指向旧提交的重复分支已删除。

## 下一步

1. 本轮仓库清理和分支同步已完成，无开放 PR。
2. 后续 contributions / points 数据库草案必须作为独立 Strict Lane 任务重新审核。
3. 新任务继续从 `develop` 创建窄分支，不直接改写 `main` 或 `develop`。

## 当前边界

- `tmp/**` 只留本地并已加入忽略，不得提交。
- 不删除仍有明确用途且没有替代物的分支。
- 不直接 push `main` / `develop`，不 merge PR，不操作 production。
