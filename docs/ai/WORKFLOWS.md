# AI / Codex 工作流程

## 0. 用途与权威关系

本文档只记录可迭代的执行流程、检查清单、验证、rollback 和回传格式。

- 唯一自动启动入口：仓库根目录 `AGENTS.md`。
- 强规则与安全门禁：[`RULES.md`](RULES.md)。
- 当前业务看板：[`CURRENT_TASK.md`](CURRENT_TASK.md)。
- 产品与技术 Final 决策：[`DECISIONS.md`](DECISIONS.md)。
- 若本文与 `RULES.md` 冲突，以 `RULES.md` 为准。

读取路由只在 `AGENTS.md` 中定义，不在本文维护第二套默认必读清单。

## 1. CURRENT_TASK.md 的职责

`CURRENT_TASK.md` 是当前业务看板，不是 Git 操作日志，也不是新任务启动说明。

必须优先展示：

1. 业务目标。
2. 技术目标。
3. 当前阶段 / 状态。
4. 最近完成。
5. 下一步任务，按优先级排序。
6. 阻塞、风险或待确认事项。

不得把以下内容作为看板主体：

- 创建分支、commit、push、PR 的通用步骤。
- 每一次工具调用或审批流水。
- 已结束任务的长篇历史。
- “当前无任务，所以从 develop 开分支”之类的流程说明。

流程规则放在 `AGENTS.md` 和本文。看板只在业务状态、技术阶段或下一步任务发生实质变化时更新，不因 PR 从 open 变为 merged 单独创建状态 PR。

## 2. 任务启动与连续执行

### 2.1 分类

任务先归类为一种主类型：

- `read-only`：盘点、审计、解释。
- `docs`：只修改文档。
- `business`：业务代码或用户行为。
- `database`：schema、SQL、RPC、RLS、migration 或远程数据。
- `config`：env、构建、CI、Vercel 或部署配置。
- `release`：PR merge、`main`、production、hotfix 或发布。

不得为了方便把无关风险类型混入同一 PR。

### 2.2 启动回执

修改前输出一次：

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

只读任务可在最终回传中合并说明。用户已经确认任务级授权时，不得在同一授权范围内逐命令重复询问。

### 2.3 默认连续批次

一次授权默认覆盖当前任务允许的完整机械流程：

1. 只读盘点和事实核对。
2. 创建或切换窄范围分支。
3. 修改全部允许文件。
4. 运行相称验证。
5. 检查 diff 和工作区。
6. commit、push。
7. 创建目标 PR。
8. 输出完整结果和下一步。

不得把上述流程拆成“建分支一次确认、改一个文件一次确认、commit 一次确认、push 一次确认、建 PR 一次确认”。

对话中的进度更新只在以下节点出现：

- 已发现关键结论或根因。
- 进入新的风险阶段。
- 验证失败或范围变化。
- 已完成一个有意义的里程碑。

### 2.4 必须暂停的情况

- 即将进入 PR merge、`main`、production、database / Supabase 写入、Vercel 写入、migration、历史改写、分支删除或修改 `RULES.md`。
- 当前分支、目标分支、环境或文件范围与任务单不一致。
- 工具失败、验证失败、规则冲突或 rollback 不明确。
- 出现未确认的产品语义、权限边界或数据策略。

不得通过更换命令、连接器或把操作拆成小变体绕过暂停点。

### 2.5 低 Token 与低摩擦

- 只读取 `AGENTS.md` 路由出的文件、用户指定文件和当前任务直接相关内容。
- 超大 JSON、SQL 结果和日志在本地处理，只回传计数、分类、异常和最多 10 条样本。
- 一次授权内尽可能完成整个可执行批次，不为纯状态变化重复建 PR。
- 安全门禁不能因节省 token 被删除：production 前值检查、事务数量检查、提交后回读、备份和 rollback 依据必须保留。

## 3. 三档任务流

### 3.1 Fast Lane

适用于 `read-only` 或普通 `docs`，且不涉及：

- `main`、production、release。
- database、Supabase、Vercel、env、migration。
- PR merge、历史改写、分支删除。
- 修改 `RULES.md`。

流程：最小读取 → 明确范围与验收 → 一次性完成修改和验证 → 创建到 `develop` 的 PR。

### 3.2 Standard Lane

适用于普通 `business` 或非生产 `config`，且不涉及 Strict Lane 条件。

流程：

1. 读取 `RULES.md` 和相关代码 / 文档。
2. 盘点分支、工作区和真实调用链。
3. 明确需求依据、测试和 rollback。
4. 一次性完成修改与相称验证。
5. 推送窄分支并创建到 `develop` 的 PR。

### 3.3 Strict Lane

以下任一条件即进入 Strict Lane：

- `main`、production、release、hotfix、PR merge。
- database、Supabase、SQL、RPC、RLS、migration。
- Vercel、env、production deployment。
- 历史改写或分支删除。
- 修改 `RULES.md`。

必须：

1. 读取 `RULES.md` 和对应治理、环境或数据库文档。
2. 明确目标环境、目标分支、影响范围、验证和 rollback。
3. 获得用户针对该敏感阶段的明确确认。
4. 环境、范围或门禁变化时重新确认。

## 4. 通用状态盘点

本地按需检查：

```bash
git status --short
git branch --show-current
git fetch origin
```

远端继续确认：

- base / head 分支。
- PR 状态、changed files、commits、mergeability 和 checks。
- 分支是否落后或偏离。
- 是否存在未提交或未 push 内容。

`git fetch` 和 GitHub 只读查询不修改远端；`git pull` 会修改本地状态，不得描述为纯只读。

## 5. 需求与缺陷

涉及产品规则、数据库结构、权限、用户权益或现有语义变化时：

1. 读取 `DECISIONS.md` 和相关需求 / 规划 / 技术文档。
2. 只把 Final 决策和用户本轮明确确认作为执行依据。
3. 列出规则冲突、待确认口径和数据风险。
4. 拆成可验证、可回滚的阶段任务。
5. 标记影响范围并按风险分类。
6. 未确认事项不得直接实现。

缺陷分类：

- A 类：纯前端体验问题，窄范围修复并运行前端验证。
- B 类：数据库、权限或 RPC 问题，进入 Strict Lane，development 先验证。
- C 类：需求或产品口径不明，先列事实和方案，等待确认。

收口时检查：

- 工作区只剩明确暂缓内容。
- 修改和验证与任务目标一致。
- 数据库记录与实际环境一致。
- 缺陷状态与验证结果一致。
- `CURRENT_TASK.md` 的业务状态和下一步仍准确。

## 6. PR 工作流

### 6.1 合并前只读检查

1. 刷新远端状态。
2. 查看 base...head 差异和 PR changed files。
3. 按 docs、business、database、config 分类。
4. 检查是否包含 `src/**`、`supabase/**`、migration、`package*.json`、构建配置、`.env*` 或 production 脚本。
5. 核对 PR base、head、状态、mergeable、commits 和 checks。
6. 回传风险、rollback 和未确认事项。

连接器或 `gh pr view`、`gh pr diff`、`gh run list` 的结果必须与 changed files / diff 交叉确认。

### 6.2 纯文档 PR

1. 从 `develop` 创建 `docs/<topic>`。
2. 一次性修改任务单允许的全部文件。
3. 禁止顺手修改代码、数据库、构建配置、env 或运行脚本。
4. 提交前检查 diff、工作区和链接。
5. 使用中文 commit，push 后创建到 `develop` 的 PR。
6. PR body 写明概述、范围、验证、风险和 rollback。
7. merge 前取得用户单独确认。

修改 `RULES.md` 仍属于 Strict Lane。

### 6.3 状态文档原则

- 不为“PR 已创建”“PR 已合并”单独建立看板 PR。
- `CURRENT_TASK.md` 只记录稳定的业务事实和可执行下一步，不记录短时 PR 状态。
- 完成输出必须链接当前看板；发现看板已失真时，在当前允许的 docs 批次中一起修正。

## 7. develop 到 main 发布

1. 确认 `main = production`、`develop = development / preview`。
2. 执行 `develop -> main` 只读差异审计。
3. 分类全部 changed files；混入无关高风险内容时停止并拆分。
4. 确认 Vercel 和 Supabase 环境绑定。
5. 涉及数据库时确认 development 验证、备份、project ref 和 rollback。
6. production merge 前再次获得明确确认。
7. 合并后观察部署状态并回传，不得自动 rollback。

## 8. 数据库与 Supabase

开始前必须读取：

- `docs/database/环境信息.md`
- `docs/database/数据库开发安全方案.md`
- `docs/database/数据库变更记录.md`

按需读取 `docs/database/schema.md` 和相关 migration。

强制步骤：

1. 确认目标 project ref 和 dev / prod 环境。
2. 先在 development 验证 migration 或数据修复。
3. 已应用 migration 的修正必须新增 patch migration。
4. production 前确认备份、前值、预计行数、事务方案、后检和 rollback。
5. apply 后回读关键数据并更新数据库变更记录。

`psql` 即使只执行查询，也按高风险数据库入口处理，必须明确连接环境和 SQL 范围。

## 9. 敏感操作分类

| 类别 | 示例 | 要求 |
| --- | --- | --- |
| 远端读取 | `git fetch`、`gh pr view`、`gh pr diff` | 可连续执行；失败时停止 |
| 普通任务写入 | branch、修改、commit、push、PR create | 任务级授权内连续执行 |
| PR merge | `gh pr merge`、连接器 merge | 每个 PR 单独确认 |
| 历史改写 | reset、clean、rebase、force push、删分支 | 逐项确认影响和 rollback |
| 数据库 | Supabase write、migration、`psql` | Strict Lane，确认环境、备份和 rollback |
| Vercel / production | deploy、env、rollback | Strict Lane，确认 project、环境和流量影响 |

## 10. 最终回传模板

```text
完成内容：
修改文件：
验证结果：
commit / PR：
风险：
rollback：
尚未确认：
下一步任务：
当前任务看板：<链接>
```

当前任务看板固定链接：

[CURRENT_TASK.md](https://github.com/larissa2022/nikki-calculator/blob/develop/docs/ai/CURRENT_TASK.md)

成功时只返回结论、数量和异常；失败时只提供定位所需的关键错误。回传中的“下一步任务”必须和看板一致。无数据库、Vercel 或 production 变更时明确说明。