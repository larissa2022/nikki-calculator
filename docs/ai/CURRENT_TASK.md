# 当前任务看板

> 最后更新：2026-07-13 23:35（北京时间）

## 业务目标

- 避免缺失图鉴补录在刷新、网络波动或账号切换时丢失或误恢复其他用户的填写内容。

## 技术目标

- 按用户隔离 24 小时本地草稿，节流保存并在恢复时明确提示；提交成功后清理对应草稿。

## 当前阶段

- `BUG-20260625-004` 已完成本地、Preview 和 development 登录用户验收并关闭；PR #74 等待合并确认。

## 最近完成

- 草稿存储 4 项单元测试、Vite 构建、Preview 刷新恢复 / 清空、离线失败保留和在线成功清理均通过。
- development 保留 1 条授权测试记录：`pending_clothes.id = 23`，名称 `Codex草稿验收-20260713-231920`，状态 `pending`。

## 下一步任务

- 确认是否将 PR #74 合并到 `develop`；合并后再规划下一项业务目标。

## 阻塞与待确认

- PR #74 merge 尚未授权；积分 / 贡献者阶段仍需另行确认数据库门禁。

## 通用边界

- 不操作 `main`、production、database、Supabase、Vercel、env 或 migration；不再新增 development 测试写入；开发 PR 不自动 merge。

## Rollback

- merge 前关闭开发 PR；merge 后通过独立 revert PR 回滚，旧版 v1 草稿键不删除；授权保留的测试 pending 记录不删除。
