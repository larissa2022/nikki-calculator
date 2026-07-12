# 当前业务看板

> 最后核对：2026-07-12（北京时间）。

## 业务目标

保障衣柜录入、图鉴提交、审核入库和提交者衣柜写回等核心流程稳定，并围绕积分、贡献者、重审池和报错修正逐步建立可追溯的最小业务闭环。

## 技术目标

- 保持 seal100x production 同步结果可审计，不重复执行已完成批次。
- 贡献 / 积分 schema 继续前，先完成 Supabase 安全前置审查。
- database 变更从 `develop` 出发，先在 development 验证，再进入 production。

## 当前阶段

- seal100x production 数据同步与字段修正已完成，当前不处于数据写入阶段。
- 文档治理 Phase 1 / Phase 2 已同步到 `develop` 和 `main`。
- 当前候选主线：贡献 / 积分功能的数据库安全前置审查。

## 最近完成

1. 完成 1,572 件 clothes、12 个 suits 的 production 同步与 postcheck。
2. 完成 scores、stars、tags 等已审核字段修正，并保留 rollback 依据。
3. 完成衣柜重复编号提示优化及 AI / Codex 文档治理收口。

## 下一步任务

1. 只读审计 Supabase advisor、RLS、grants、`SECURITY DEFINER`、公开 view / RPC；不执行写操作。
2. 根据审计结果拆分安全修复任务，并明确 development 验证与 rollback。
3. 安全前置完成后，再决定 PR #17 及贡献 / 积分 schema 的拆分和产品口径。

## 阻塞与待确认

- Supabase 安全实时状态尚未重新审计。
- `source_pending_id`、贡献追溯和历史积分补录规则尚未确认。

## 通用边界

- 本看板展示当前业务状态和下一步，不构成执行授权。
- docs、business、database、config、release 不混入同一任务，除非用户明确授权。
- PR merge、`main`、production、database / Supabase / Vercel 写入、env、migration、分支删除和修改 `RULES.md` 均需单独确认。

## Rollback

- 本看板修改在 merge 前可关闭对应 PR；merge 后通过独立 revert PR 回滚。
- 业务、数据库或 production 任务必须在各自任务中单独定义 rollback；本看板不替代具体回滚方案。
