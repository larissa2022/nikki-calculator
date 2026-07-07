# 衣柜短编号录入缺陷修复收口报告

日期：2026-07-07

## 背景

录入衣柜功能中的“分类 + 短编号录入”在使用游戏内短编号时，错误地要求或依赖二级 / 三级分类。玩家实际录入时只需要选择一级分类，因为同一一级分类下 `game_id` 已确认唯一。

## 影响范围

- 影响功能：衣柜短编号录入。
- 主要影响分类：饰品、袜子等存在二级 / 三级细分的分类。
- 不影响范围：普通按名称录入、wardrobe 云端保存结构、Supabase schema、migration、env、Vercel 配置。

## 修复过程

1. 只读诊断确认：
   - `ImportZone.vue` 短编号模式使用 `FULL_CATEGORIES` 展示细分分类。
   - `handleCodeImport` 使用 `item.category === codeImportCategory` 精确过滤。
   - 保存路径仍只写入 item id。
2. PR #44：
   - 从 `develop` 创建修复分支。
   - 修改 `src/components/ImportZone.vue`。
   - Preview 验证通过。
   - merge 到 `develop`。
3. develop -> main 审计：
   - 发现 `develop` 相对 `main` 同时包含 `docs/ai/RULES.md` 和业务修复。
   - 为避免混合 docs / business 变更，未直接 merge `develop` 到 `main`。
4. PR #45：
   - 从 `main` 创建 hotfix 分支。
   - 只同步 PR #44 的 `src/components/ImportZone.vue` 修复。
   - 不带 `docs/ai/RULES.md`。
   - merge 到 `main`。
5. 用户确认 production 验证未发现明显问题。

## 最终状态

- PR #44 已进入 `develop`。
- PR #45 已进入 `main`。
- 当前缺陷修复完成。
- 未触碰 Supabase / SQL / migration / Vercel 写操作 / env。

## Rollback

如 production 后续发现问题，优先 revert PR #45 的 merge commit。

## 后续事项

- PR #43 的 docs 规则变更是否同步到 `main` 仍需单独处理。
- 后续 `develop -> main` 仍需先做只读差异审计。
