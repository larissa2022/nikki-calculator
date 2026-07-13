# 当前任务看板

> 最后更新：2026-07-13 22:42（北京时间）

## 业务目标

- 避免缺失图鉴补录在刷新、网络波动或账号切换时丢失或误恢复其他用户的填写内容。

## 技术目标

- 按用户隔离 24 小时本地草稿，节流保存并在恢复时明确提示；提交成功后清理对应草稿。

## 当前阶段

- 已完成代码修改、本地单元测试和构建，等待 Preview 人工验收。

## 最近完成

- PR #72、#73 已合并到 `develop`；草稿存储 4 项单元测试和 Vite 构建通过。

## 下一步任务

- 创建 `develop` PR，并在 Preview 验证刷新恢复、失败保留和成功清理。

## 阻塞与待确认

- `points_ledger` / `clothing_contributions` 需另行确认 development project ref、migration 验证和 rollback 后启动。

## 通用边界

- 不操作 `main`、production、database、Supabase、Vercel、env 或 migration；开发 PR 不自动 merge。

## Rollback

- merge 前关闭开发 PR；merge 后通过独立 revert PR 回滚，旧版 v1 草稿键不删除。
