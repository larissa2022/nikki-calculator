# ChatGPT 到 Codex 中文执行单

用途：ChatGPT 负责中文讨论和需求收敛；Codex 只接收确认后的执行任务。

```text
目标：
- [这次必须完成什么]

允许修改：
- [明确文件或目录]

禁止事项：
- [不能修改的文件]
- [是否禁止 main / production / database / Supabase / Vercel / migration / env / merge]

验收：
- [必须运行的检查]
- [成功标准]

授权批次：
- [可连续执行的步骤，例如：备份 → 前检 → apply → 后检 → rollback 草案]
- [哪些情况才需要重新确认]

输出限制：
- 只返回结论、数量、异常和最多 10 条样本。
- 原始 JSON、SQL 和完整日志只保存在本地，不粘贴到对话。

停止点：
- 实际范围超出允许修改。
- 命令失败或出现未预期数据风险。
- 需要进入尚未授权的 main、production、database、Supabase、Vercel、migration、env 或 merge。
```

Codex 完成后只用中文回传：

```text
完成内容：
修改文件：
验证结果：
风险：
尚未确认：
建议下一步：
```

不默认创建 scheduled task；需要时另行确认只读范围、频率和输出。

任务验收通过后立即更新一屏看板并结束当前对话；新的独立任务使用新的执行单和新对话。
