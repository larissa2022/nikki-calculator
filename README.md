# Nikki Calculator

奇迹暖暖搭配器与图鉴审核工具。项目使用 Vue 3 + Vite + Supabase。

## 快速开始

```sh
npm install
npm run dev
```

构建：

```sh
npm run build
```

## 文档入口

项目文档已整理到 [docs/README.md](docs/README.md)。

AI / Codex 开始任何任务前，必须先阅读：

- [AI 协作规则](docs/ai/RULES.md)
- [分支与环境治理规则](docs/governance/BRANCH_ENVIRONMENT_POLICY.md)

常用入口：

- [需求文档](docs/requirements/需求文档.md)
- [开发文档](docs/planning/开发文档.md)
- [技术实现文档](docs/planning/技术实现文档.md)
- [数据库开发安全方案](docs/database/数据库开发安全方案.md)
- [数据库变更记录](docs/database/数据库变更记录.md)
- [数据库环境信息](docs/database/环境信息.md)
- [分支与环境治理规则](docs/governance/BRANCH_ENVIRONMENT_POLICY.md)

## 数据库安全提醒

当前生产库和开发库尚未完全隔离时，不要直接对远程生产库执行数据库写操作。开始数据库开发前先阅读：

- [数据库开发安全方案](docs/database/数据库开发安全方案.md)
- [数据库变更记录](docs/database/数据库变更记录.md)

## Supabase 辅助命令

```sh
npm run db:dump
npm run db:types
```

说明：

- `npm run db:types` 默认生成 development 项目的类型。
- 生产类型必须显式执行 `npm run db:types:prod`。
- `npm run db:dump` 依赖当前 Supabase linked project，执行前先确认 `supabase status`。
