---
name: nikki-pr-audit
description: 用中文审核 Nikki Calculator 的 PR，按 docs、business、database、config、release 分类风险，并给出能否合并、缺失验证和回滚结论。用于合并前审核、docs-only 范围确认、develop 到 main 发布检查，或用户要求审核 PR、diff、合并风险时。
---

# Nikki PR 中文审核

只做只读检查。除非用户另外授权，不评论、不批准、不合并 PR。

## 检查步骤

1. 获取 PR 编号、base、head、状态、mergeable、提交和 changed files。
2. 必要时读取 PR diff，并核对当前分支和 `git status`。
3. 将每个文件归入：
   - `docs`：文档和规划。
   - `business`：`src/**`、界面、业务行为、认证、衣柜或审核逻辑。
   - `database`：`supabase/**`、migration、SQL、RPC、RLS、数据库脚本或生成类型。
   - `config`：`package*.json`、`vite.config.*`、CI、Vercel、env 示例和构建配置。
   - `release`：目标为 `main`、production、hotfix、rollback 或部署相关内容。
4. 检查是否混合风险类型、是否缺少验证、是否包含 secret、env 或 `tmp/**`。
5. 只用中文输出固定结论；没有证据时写“未确认”，不要猜测。

## 判断规则

- 纯文档 PR 到 `develop`，且不含 `RULES.md`、database、config 或 production：通常低风险。
- 业务代码到 `develop`：至少中风险，需要相关 build/test。
- 涉及 `main`、production、database、Supabase、Vercel、migration、merge、历史改写、分支删除或 `RULES.md`：高风险，必须单独确认。
- docs、business、database、config 混合时，默认建议拆分。
- `develop -> main` 必须检查完整 diff、验证证据和 rollback。
- “可以合并”只代表审核结论，不代表获得执行 merge 的授权。

## 固定输出

```text
审核结论：[可以合并 / 暂缓合并 / 必须拆分 / 仅完成只读检查]

改了什么：
- [按风险类型概括文件和行为变化]

影响什么：
- 用户行为：[无 / 有，说明]
- 数据库：[无 / 有，说明]
- production：[无 / 有，说明]

验证结果：
- [已通过的检查]
- [缺失或失败的检查]

风险：
- [风险等级和原因]

能否合并：
- [明确回答，并列出阻塞项]

回滚方式：
- [关闭 PR / revert commit / 数据库 rollback / 其他]

尚未确认：
- [只列需要用户决定的事项]
```
