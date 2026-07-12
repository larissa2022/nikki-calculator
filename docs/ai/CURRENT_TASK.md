# 当前业务看板

> 最后核对：2026-07-12（北京时间）。

## 业务目标

保持 Nikki Calculator 图鉴与衣柜数据准确、可追溯、可回滚；在稳定的数据基础上推进用户贡献与积分机制，确保用户录入、审核、贡献归属和后续争议处理都有可信数据依据。

## 技术目标

1. 将 seal100x 数据同步结果维持为可审计的 production 基线，不重复执行已完成批次。
2. 在继续贡献 / 积分 schema 前，先收口 Supabase 的 RLS、table / function grants、`SECURITY DEFINER` 和公开读取路径风险。
3. 后续 database 变更必须从 `develop` 出发，先在 development 项目验证，再拆分进入 production。
4. 贡献记录必须保留足够来源追溯能力，重点确认 `source_pending_id`、重复键、rollback 和历史 backfill 设计。

## 当前阶段

- seal100x clothes production 数据同步与字段修正已完成，当前不处于数据写入阶段。
- 文档入口、执行流程和历史归档已完成 Phase 1 / Phase 2，并已同步到 `main`。
- 当前业务阶段进入“贡献 / 积分功能的数据库安全前置审查”。
- 当前第一优先级任务：`database/security` 只读审计，尚未开始执行数据库写入。

## 最近完成

1. seal100x production 新增同步已完成：1,572 件 clothes、12 个 suits，postcheck 通过，外键异常为 0。
2. production 分数字段修正已完成：255 条纯数字 ID scores，以及 13 条系统 / 用户录入 scores / stars；完整复审后对应纯差异归零。
3. production tags 修正已完成：15 条 `custom_` 记录；另完成“赤色狂宴”单条 score 精确修正，均保留 before / after 与 rollback 依据。
4. 衣柜重复编号冲突提示已改为用户可理解的文案，不改变冲突检测和写入逻辑。
5. AI / Codex 文档治理已完成并同步到 `develop`、`main`：`AGENTS.md` 单一入口、核心流程收口、历史报告归档。

## 下一步任务

1. **Supabase 安全只读审计**：读取当前 production / development advisor、RLS、table grants、function grants、`SECURITY DEFINER` 和公开 view / RPC 状态；只输出事实、风险和分类，不执行 SQL、migration 或写操作。
2. **安全修复拆分方案**：根据审计结果按 RLS、grants、functions、views / RPC 分拆独立 database 任务，明确 development 验证、验收和 rollback。
3. **贡献 / 积分 schema 重新设计**：PR #17 保持 blocked；安全前置完成后，从 `develop` 重新拆分 duplicate-key precheck、base tables、RLS / grants、public views / RPC、write-path integration 和 backfill。
4. **产品口径确认**：决定 `clothing_contributions.source_pending_id` 是否为强制字段，以及贡献追溯、争议处理和历史积分补录规则。
5. **独立后续专项**：seal100x DB-only 与 suit mapping 若仍需继续，必须作为单独的 data-sync / mapping 任务，不与贡献积分或安全修复混合。

## 阻塞与待确认

- 当前 Supabase advisor、RLS 和 grants 的实时状态尚未重新审计，不能直接推进 PR #17。
- `source_pending_id` 是否强制保留仍需产品确认。
- 本看板不授权 database / Supabase 写入、migration、production 或 Vercel 操作。
- PR merge、`main`、production、database / Supabase 写入和修改 `RULES.md` 仍需用户单独明确确认。

## 相关入口

- [Supabase Review](../database/SUPABASE_REVIEW.md)
- [数据库变更记录](../database/数据库变更记录.md)
- [seal100x Clothes Data Sync Plan](../planning/seal100x-clothes-sync-plan.md)
- [AI / Codex 工作流程](WORKFLOWS.md)
