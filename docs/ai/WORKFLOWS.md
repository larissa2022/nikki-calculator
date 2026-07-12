# AI / Codex 工作流程

## 0. 用途与权威关系

本文档只记录可迭代的执行流程、命令顺序、检查清单和回传模板。

- 唯一自动启动入口：仓库根目录 `AGENTS.md`。
- 强规则与安全门禁：[`RULES.md`](RULES.md)。
- 当前任务事实：[`CURRENT_TASK.md`](CURRENT_TASK.md)。
- 产品与技术 Final 决策：[`DECISIONS.md`](DECISIONS.md)。
- 若本文与 `RULES.md` 冲突，以 `RULES.md` 为准。

本文不再维护另一套“默认必读清单”；读取路由只在 `AGENTS.md` 中定义。

## 1. 任务启动流程

### 1.1 分类

开始前将任务归类为一种主类型：

- `read-only`：只读盘点、审计、解释。
- `docs`：只修改文档。
- `business`：修改业务代码或用户行为。
- `database`：schema、SQL、RPC、RLS、migration 或远程数据状态。
- `config`：env、构建、CI、Vercel 或部署配置。
- `release`：`main`、production、hotfix、发布或 PR merge。

不得为了方便把多种风险类型混入同一 PR。

### 1.2 启动回执

任何修改开始前，先输出：

```text
当前分支：
任务类型：
自动入口：AGENTS.md
本任务额外读取：文件 + 原因
允许修改：
禁止事项：
验收：
停止点：
```

只读任务可在最终回传中合并说明，不需要额外等待。用户已经确认任务级授权时，在授权范围内连续执行；不要逐命令重复询问。

### 1.3 五项执行单

进入 Codex 前只传递当前有效内容：

1. 目标。
2. 允许修改。
3. 禁止事项。
4. 验收。
5. 停止点。

旧对话只保留仍然有效的事实和授权，不复制完整历史流水。

### 1.4 低 Token 原则

- 只读取 `AGENTS.md` 路由出的文件、用户指定文件和当前任务直接相关内容。
- 不默认加载全部治理、复盘、历史报告和长期规划。
- 超大 JSON、SQL 结果和日志只在本地处理；对话返回计数、分类、异常和最多 10 条样本。
- `CURRENT_TASK.md` 只保存当前目标、状态、边界、下一步和阻塞，不保存执行流水或累计统计。
- 一个独立目标验收后立即收口；新目标使用新执行单。
- 不得为了节省 token 删除 production 前值检查、事务数量检查、提交后回读、备份或 rollback。

## 2. 三档任务流

### 2.1 Fast Lane

适用于 `read-only` 或普通 `docs`，且不涉及：

- `main`、production、release。
- database、Supabase、Vercel、env、migration。
- PR merge、历史改写、删除分支。
- 修改 `RULES.md`。

流程：

1. 按 `AGENTS.md` 读取最小上下文。
2. 明确文件范围、验证和 rollback。
3. 在一次任务级授权内连续执行允许步骤。
4. 提交前检查 diff 只包含允许文件。
5. 创建 PR 到 `develop`；不自动 merge。

### 2.2 Standard Lane

适用于普通 `business` 或非生产 `config`，且不涉及 Strict Lane 条件。

流程：

1. 读取 `RULES.md` 和本任务相关章节。
2. 只读盘点分支、工作区和相关代码。
3. 明确需求依据、允许范围、禁止范围、测试和 rollback。
4. 修改并运行相称验证。
5. 提交前回传修改范围、验证、风险和未确认事项。
6. 推送窄分支并创建到 `develop` 的 PR；不自动 merge。

### 2.3 Strict Lane

以下任一条件即进入 Strict Lane：

- `main`、production、release、hotfix。
- database、Supabase、SQL、RPC、RLS、migration。
- Vercel、env、production deployment。
- PR merge。
- 历史改写或删除分支。
- 修改 `RULES.md`。

必须：

1. 读取 `RULES.md` 和对应治理、环境或数据库文档。
2. 明确目标环境、目标分支、影响范围、备份、验证和 rollback。
3. 由用户针对本任务单独确认。
4. 门禁失败、范围变化或进入新环境时暂停并重新确认。
5. `gh pr merge` 永远需要用户再次明确确认。

## 3. 通用状态盘点

本地执行时按需检查：

```bash
git status --short
git branch --show-current
git fetch origin
```

需要远端事实时，继续确认：

- base / head 分支。
- PR 状态和 changed files。
- 本地分支是否落后或偏离远端。
- 是否存在未提交或未 push 内容。

`git fetch` 和只读 GitHub 查询不修改远端；`git pull` 会修改本地分支，不应被描述为纯只读。

## 4. 需求到执行计划

涉及业务规则、产品口径、数据库结构、审核流程、用户权益或现有功能语义变化时：

1. 读取 `DECISIONS.md` 和相关需求、规划、技术文档。
2. 只把 Final 决策和用户本轮明确确认内容作为执行依据。
3. 列出字段缺失、规则冲突、待确认产品口径和数据风险。
4. 将已确认需求拆成阶段、暂停点、验收和可回滚的最小任务。
5. 标记影响范围：前端、RPC、RLS、migration、env、Vercel、Supabase、production。
6. 按 docs、business、database、config、release 分类。
7. 未确认事项不得直接进入实现。

发现必须修改 `RULES.md` 或 `DECISIONS.md`，但用户没有单独授权时，立即停止。

## 5. 缺陷工作流

### A 类：纯前端体验问题

不改变数据库结构、权限、正式库写入或产品口径。登记缺陷，窄范围修复，运行相称前端验证，由用户完成必要人工验收。

### B 类：数据库、权限或 RPC 问题

进入 Strict Lane：先准备 migration 或可审计修复方案，在 development 验证，记录备份、前检、后检和 rollback；production 前再次确认。

### C 类：需求风险或产品口径不明

先记录事实和风险，提供一至两个方案，等待用户确认后再开发。

### 收口检查

- `git status --short` 只剩明确暂缓文件。
- 已验证功能拥有独立提交。
- 数据库变更记录与实际环境状态一致。
- 缺陷状态与人工或自动验证结果一致。
- 当前任务看板已更新。

## 6. ChatGPT 预审批与连续执行

ChatGPT 在执行前完成任务级预审批：

- 目标、允许修改、禁止范围。
- 敏感命令及用途。
- 是否涉及 `main`、production、database、Supabase、Vercel。
- 验证、失败处理和 rollback。

用户确认后，Codex 或 ChatGPT 连接器可在授权范围内连续执行。以下情况必须停止：

- 工具或审批层拒绝。
- 命令失败。
- 修改文件超出允许范围。
- 当前分支、目标分支或环境与任务单不一致。
- 出现未授权的敏感操作。
- rollback 不明确。

不得通过更换命令、页面、连接器或拆分变体绕过拒绝。

## 7. PR 只读检查

合并或发布前：

1. 刷新远端状态。
2. 查看 base...head 差异和 PR changed files。
3. 按 docs、business、database、config 分类。
4. 检查是否包含 `src/**`、`supabase/**`、migration、`package*.json`、构建配置、`.env*` 或 production 脚本。
5. 核对 PR base、head、状态、mergeable、commits 和 checks。
6. 回传风险、rollback 和未确认事项。

只读工具可使用 GitHub 连接器或：

```bash
gh pr view <number> --repo <owner/repo>
gh pr diff <number> --repo <owner/repo>
gh run list --repo <owner/repo>
```

工具查询必须和 changed files / diff 交叉确认。

## 8. 纯文档 PR

1. 从 `develop` 创建 `docs/<topic>`。
2. 只修改任务单允许的文件。
3. 禁止顺手修改代码、数据库、构建配置、env 或运行脚本。
4. 提交前检查：

```bash
git status --short
git diff --name-status
git diff
```

5. 使用中文 commit，推送任务分支。
6. 创建 PR 到 `develop`。
7. PR body 写明概述、范围、验证、风险和 rollback。
8. merge 前重新执行 PR 只读检查并取得用户确认。

修改 `RULES.md` 的 docs-only 任务仍属于 Strict Lane，必须有用户单独授权。

## 9. develop 到 main 发布

1. 确认 `main = production`、`develop = development / preview`。
2. 执行 `develop -> main` 只读差异审计。
3. 将变更按风险分类；混入无关高风险内容时停止并拆分。
4. 确认 Vercel 和 Supabase 环境绑定。
5. 涉及数据库时确认 development 验证、备份、project ref 和 rollback。
6. production merge 前再次获得用户明确确认。
7. 合并后只观察和回传；不得自动执行 rollback。

## 10. 数据库与 Supabase

开始前必须读取：

- `docs/database/环境信息.md`
- `docs/database/数据库开发安全方案.md`
- `docs/database/数据库变更记录.md`

按需读取 `docs/database/schema.md` 和相关 migration。

强制步骤：

1. 确认目标 project ref 和 dev / prod 环境。
2. 先在 development 验证 migration 或数据修复。
3. 已应用 migration 的修正新增 patch migration。
4. production 操作前确认备份、前值、预计行数、事务方案、后检和 rollback。
5. apply 后回读关键数据并更新数据库变更记录。

`psql` 即使只计划执行查询，也按高风险数据库入口处理，必须明确连接环境和 SQL 范围。

## 11. 敏感命令分类

| 类别 | 示例 | 要求 |
| --- | --- | --- |
| 远端读取 | `git fetch`、`gh pr view`、`gh pr diff` | 说明目的；失败即停止 |
| 本地写入 | `git add`、`git commit`、`git restore` | 明确路径和 rollback；破坏性恢复需单独确认 |
| 远端写入 | `git push`、`gh pr create`、`gh pr close` | 任务级预审批；`gh pr merge` 单独确认 |
| 历史改写 | `reset --hard`、`clean`、rebase、force push | 逐项确认影响和 rollback |
| 数据库 | `supabase db push`、migration、`psql` | Strict Lane，确认环境、备份和 rollback |
| Vercel / production | deploy、env、rollback | Strict Lane，确认 project、环境和流量影响 |

已授权的普通 docs-only 批次可以连续执行 branch、修改、diff、commit、push、PR create；不包含 merge、main、production 或分支删除。

## 12. 回传模板

```text
完成内容：
当前分支：
修改文件：
验证结果：
commit / PR：
风险：
rollback：
尚未确认：
建议下一步：
```

成功时只返回结论、数量和异常；失败时只提供定位所需的关键错误。无数据库、Vercel 或 production 变更时明确说明。