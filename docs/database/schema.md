# schema

当前文件是 development 项目 `tfwejruvdahonacyldrg` 的 public schema 摘要。

完整 public SQL 快照见：`supabase/schema.sql`。2026-07-22 DB-5 已在 development 应用，目标 RPC definition、owner、空 `search_path` 与 grants 已回读；TypeScript 类型重新生成后与现文件一致。CLI 全量 dump 因数据库 TLS 连接中断未完成，因此 SQL 快照只定向同步本次目标 RPC，其他对象仍沿用 DB-4 后快照。非 exposed `private_db2` helper 仍以 DB-2 migration 为权威定义。

## 表结构摘要

| 表名 | 字段名 | 数据类型 | 默认值 | 能否为空 |
| --- | --- | --- | --- | --- |
| app_errors | id | uuid | gen_random_uuid() | NO |
| app_errors | created_at | timestamp with time zone | timezone('utc', now()) | NO |
| app_errors | user_id | uuid | null | YES |
| app_errors | action_name | text | null | YES |
| app_errors | error_message | text | null | YES |
| app_errors | error_stack | text | null | YES |
| app_errors | user_agent | text | null | YES |
| clothes | id | character varying | null | NO |
| clothes | created_at | timestamp with time zone | now() | NO |
| clothes | name | text | null | YES |
| clothes | category | text | null | YES |
| clothes | stars | text | null | YES |
| clothes | tags | text | null | YES |
| clothes | scores | jsonb | null | YES |
| clothes | game_id | text | null | YES |
| clothes | suit_id | uuid | null | YES |
| clothes | temp_suit_name | text | null | YES |
| clothing_contributions | id | uuid | gen_random_uuid() | NO |
| clothing_contributions | event_id | uuid | null | NO |
| clothing_contributions | clothes_id | character varying | null | NO |
| clothing_contributions | user_id | uuid | null | YES |
| clothing_contributions | source_pending_id | bigint | null | NO |
| clothing_contributions | contribution_type | text | null | NO |
| clothing_contributions | contribution_rank | smallint | null | NO |
| clothing_contributions | source_created_at | timestamp with time zone | null | NO |
| clothing_contributions | created_at | timestamp with time zone | now() | NO |
| pending_clothes | id | bigint | identity | NO |
| pending_clothes | created_at | timestamp with time zone | now() | NO |
| pending_clothes | name | text | null | YES |
| pending_clothes | category | text | null | YES |
| pending_clothes | stars | integer | null | YES |
| pending_clothes | scores | jsonb | null | YES |
| pending_clothes | tags | text | null | YES |
| pending_clothes | suit_name | text | null | YES |
| pending_clothes | game_id | text | null | YES |
| pending_clothes | status | text | 'pending' | YES |
| pending_clothes | submitted_by | uuid | null | YES |
| pending_clothes | suit_id | uuid | null | YES |
| pending_clothes | temp_suit_name | text | null | YES |
| pending_suits | id | uuid | gen_random_uuid() | NO |
| pending_suits | name | text | null | NO |
| pending_suits | submitted_by | uuid | null | YES |
| pending_suits | status | text | 'pending' | YES |
| pending_suits | created_at | timestamp with time zone | now() | YES |
| points_ledger | id | uuid | gen_random_uuid() | NO |
| points_ledger | user_id | uuid | null | YES |
| points_ledger | delta | integer | null | NO |
| points_ledger | status | text | 'awarded' | NO |
| points_ledger | source_type | text | null | NO |
| points_ledger | source_id | uuid | null | YES |
| points_ledger | reversal_of | uuid | null | YES |
| points_ledger | occurred_at | timestamp with time zone | now() | NO |
| points_ledger | created_at | timestamp with time zone | now() | NO |
| profiles | id | uuid | null | NO |
| profiles | email | text | null | YES |
| profiles | nickname | text | null | YES |
| profiles | role | text | 'user' | YES |
| profiles | quota | integer | 30 | YES |
| profiles | updated_at | timestamp with time zone | now() | YES |
| profiles | created_at | timestamp with time zone | timezone('utc', now()) | YES |
| profiles | username | text | null | YES |
| profiles | total_points | integer | 0 | YES |
| profiles | current_month_points | integer | 0 | YES |
| profiles | monthly_action_count | integer | 0 | YES |
| stages | id | bigint | identity | NO |
| stages | created_at | timestamp with time zone | now() | NO |
| stages | name | text | null | YES |
| stages | weights | jsonb | null | YES |
| suits | id | uuid | gen_random_uuid() | NO |
| suits | name | text | null | NO |
| suits | description | text | null | YES |
| suits | source | text | null | YES |
| suits | created_at | timestamp with time zone | now() | YES |
| user_quotas | user_id | uuid | null | NO |
| user_quotas | free_count | integer | 20 | YES |
| user_wardrobes | id | uuid | gen_random_uuid() | NO |
| user_wardrobes | created_at | timestamp with time zone | now() | NO |
| user_wardrobes | user_id | uuid | gen_random_uuid() | YES |
| user_wardrobes | owned_clothes | jsonb | null | YES |

## DB-2 只读面

| 对象 | 对外字段 | 角色与约束 |
| --- | --- | --- |
| `public.user_points_summary` | `total_points bigint` | 仅 `authenticated` SELECT；按 `auth.uid()` 汇总自己的 `awarded` 正负流水 |
| `public.clothing_contributors_public` | `clothes_id`、`contribution_rank`、`display_name`、`contributed_at` | `anon` / `authenticated` SELECT；每件服装仅公开初始入库稳定前 3 |
| `private_db2.current_user_points()` | 内部 helper | `SECURITY DEFINER`、`STABLE`、空 `search_path`；仅 authenticated 可执行 |
| `private_db2.public_initial_contributors()` | 内部 helper | `SECURITY DEFINER`、`STABLE`、空 `search_path`；anon / authenticated 可执行 |

两个 public view 均为 `security_invoker + security_barrier` 且不可写。Data API exposed schemas 实测仅 `public, graphql_public`；`private_db2` 返回 `PGRST106`，不能直接作为 API schema / RPC 面访问。

## DB-3 正式库补全写入闭环

| 对象 / 规则 | 当前契约 |
| --- | --- |
| `complete_existing_clothes_from_pending(...)` | `SECURITY DEFINER`、空 `search_path`、全限定对象；只授予 authenticated / service_role，函数内继续校验 admin / super_admin |
| 有效贡献者 | 与最终补全数据一致且有真实用户；按来源时间、pending ID、用户 ID 稳定排序，同一用户取最早一条，最多 5 人 |
| 原子写入 | 同一事务补全正式库、写贡献、每人 `+5`、写回同一批用户衣柜，并将选中 pending 保留为 `approved` |
| 幂等 | 事件 ID 由正式服装 ID 与排序后的 pending IDs 稳定派生；重试必须复用既有事实且不新增贡献、积分或衣柜项 |
| 默认拒绝 | `clothing_contributions`、`points_ledger` 仍无客户端底表权限和 RLS policy；只允许受控 RPC 写入 |

## DB-4 管理员仲裁写入闭环

| 对象 / 规则 | 当前契约 |
| --- | --- |
| `approve_pending_clothes_arbitration(...)` | `SECURITY DEFINER`、空 `search_path`、全限定对象；只授予 authenticated / service_role，函数内继续校验 admin / super_admin |
| 服务端一致性 | 所有选中 pending 的名称、分类、短编号、星级、属性、套装 / 临时套装和标签必须与最终入库候选一致，否则整个事务拒绝 |
| 有效贡献者 | 同一真实用户仅保留最早来源，再按来源时间、pending ID、用户 ID 稳定排序，最多 5 人；匿名来源不参与 |
| 原子写入 | 同一事务新建正式服装、写 `admin_arbitration` 贡献、每人 `+10`、写回同一批用户衣柜，并将全部选中 pending 保留为 `approved` |
| 幂等 | 事件 ID 由正式服装 ID 与排序后的 pending IDs 稳定派生；只有正式服装、贡献、积分、衣柜和 pending 事实完整一致时，重试才返回既有成功 |
| 默认拒绝 | 普通用户调用被函数内角色校验拒绝；`clothing_contributions`、`points_ledger` 的客户端底表权限和 RLS policy 均未放宽 |

## 主要约束与索引

| 对象 | 类型 | 字段 / 说明 |
| --- | --- | --- |
| clothes_pkey | primary key | clothes.id |
| clothes_name_category_unique | unique | clothes.name, clothes.category |
| clothes_suit_id_fkey | foreign key | clothes.suit_id -> suits.id |
| clothing_contributions_pkey | primary key | clothing_contributions.id |
| clothing_contributions_clothes_id_fkey | foreign key | clothing_contributions.clothes_id -> clothes.id，删除受限 |
| clothing_contributions_user_id_fkey | foreign key | clothing_contributions.user_id -> auth.users.id，账号删除后置空 |
| clothing_contributions_source_pending_id_fkey | foreign key | clothing_contributions.source_pending_id -> pending_clothes.id，删除受限 |
| clothing_contributions_source_pending_id_key | unique | 每条来源 pending 最多形成一条贡献 |
| clothing_contributions_event_rank_key | unique | 同一事件的贡献排名唯一 |
| clothing_contributions_event_user_key | unique | 同一事件、同一真实用户只记录一次 |
| clothing_contributions_initial_reward_key | partial unique index | 自动入库 / 管理员仲裁共享初始奖励组 |
| clothing_contributions_clothes_id_idx | index | clothing_contributions.clothes_id |
| clothing_contributions_user_id_idx | index | clothing_contributions.user_id |
| pending_clothes_pkey | primary key | pending_clothes.id |
| pending_clothes_submitted_by_fkey | foreign key | pending_clothes.submitted_by -> auth.users.id |
| pending_clothes_suit_id_fkey | foreign key | pending_clothes.suit_id -> suits.id |
| pending_suits_pkey | primary key | pending_suits.id |
| pending_suits_submitted_by_fkey | foreign key | pending_suits.submitted_by -> auth.users.id |
| points_ledger_pkey | primary key | points_ledger.id |
| points_ledger_user_id_fkey | foreign key | points_ledger.user_id -> auth.users.id，账号删除后置空 |
| points_ledger_source_id_fkey | foreign key | points_ledger.source_id -> clothing_contributions.id，删除受限 |
| points_ledger_reversal_of_fkey | foreign key | points_ledger.reversal_of -> points_ledger.id，删除受限 |
| points_ledger_source_id_key | partial unique index | 一条贡献最多产生一条正向流水 |
| points_ledger_reversal_of_key | partial unique index | 一条原流水最多产生一条扣回流水 |
| points_ledger_user_occurred_at_idx | index | points_ledger.user_id, occurred_at desc |
| profiles_pkey | primary key | profiles.id |
| profiles_username_key | unique | profiles.username |
| suits_pkey | primary key | suits.id |
| suits_name_key | unique | suits.name |
| idx_clothes_suit_id | index | clothes.suit_id |
| idx_pending_clothes_submitted_by | index | pending_clothes.submitted_by，用于按提交人执行 RLS 查询 |
| idx_pending_clothes_status | index | pending_clothes.status |
| idx_pending_suits_status | index | pending_suits.status |
| idx_profiles_username | index | profiles.username |
| idx_suits_name | index | suits.name |

## 函数与触发器

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| auto_link_shadow_suits() | trigger function | 新套装入库后自动关联临时套装名匹配的 clothes / pending_clothes |
| add_clothes_to_submitter_wardrobes(uuid[], text) | internal function | 审核入库后同步提交人衣柜，仅 `service_role` 可直接执行 |
| approve_pending_clothes_arbitration(...) | RPC | DB-4 管理员仲裁入库；服务端核对候选，原子写贡献、每人 10 分、衣柜和 pending，并支持重试幂等 |
| complete_existing_clothes_from_pending(...) | RPC | DB-3 正式库空字段补全；函数内校验管理员，原子写贡献、每人 5 分、衣柜和 pending，并支持重试幂等 |
| deduct_user_quota(uuid) | function | 扣减用户 quota |
| handle_new_user() | trigger function | auth.users 新用户初始化 profiles |
| handle_new_user_quota() | trigger function | auth.users 新用户初始化 user_quotas |
| is_admin_or_super_admin() | function | 判断当前用户是否为管理员或最高站长 |
| is_super_admin() | function | 判断当前用户是否为 super_admin |
| normalize_known_clothing_tags(text) | function | 清洗已知服装标签 |
| submit_clothing_contribution(...) | RPC | DB-5 缺失项提交与 5 位不同用户一致后自动入库；保留来源 pending，原子写前 5 位贡献、每人 10 分和衣柜 |
| update_profile_username(text) | RPC | 登录用户更新自己的用户名 |
| trigger_auto_link_shadow_suits | trigger | suits insert 后执行 auto_link_shadow_suits() |

## RLS 摘要

已启用 RLS：

- app_errors
- clothes
- clothing_contributions（DB-1 默认拒绝，无 policy）
- pending_clothes
- pending_suits
- points_ledger（DB-1 默认拒绝，无 policy）
- profiles
- user_quotas
- user_wardrobes

`pending_clothes` 当前策略：

- 匿名请求无表级访问权限。
- 普通登录用户只能提交状态为 `pending` 且 `submitted_by = auth.uid()` 的记录，并只能查看自己的记录。
- 管理员和最高站长可查看全部记录、更新审核状态；登录角色没有删除权限，也不能修改 `status` 以外的字段。
- 衣柜同步、额度扣减和用户初始化等内部函数只允许 `service_role` 直接执行。

当前注意事项：

- DB-1 两张基础事实表当前均为 0 行；anon、authenticated 仍无底表权限，admin / super_admin 通过相同的 authenticated 数据库角色也不能直接操作；`service_role` 仅保留 SELECT / INSERT。
- DB-2 只开放两个结果面：匿名用户不能读取积分，所有登录角色只能读取自己的积分；公开贡献者不返回 user_id、email、完整 UUID、pending 或积分流水。
- DB-3 已形成 1 条 development 人工验收贡献和 1 条 `+5` 积分流水；DB-4 事务 fixture 全部回滚，未新增持久贡献或积分数据。
- Security Advisor 对两张 DB-1 表仅报告预期 INFO：RLS 已启用但没有 policy；DB-2 helper 位于未暴露 schema 且没有新增 Advisor WARN / ERROR。
- Security Advisor 仍报告 `stages`、`suits` 未启用 RLS；不属于本次 DB-0 范围，必须在后续独立安全任务处理。
- 当前 `profiles` 仍保留 `total_points`、`current_month_points`、`monthly_action_count` 字段；根据需求文档，后续积分权威来源应迁移到 `points_ledger`，这些字段只能作为历史字段或缓存字段，不应作为权威总分。
- 当前 `profiles.role` 为 `text`，并使用 `user`、`admin`、`super_admin` 字符串区分角色；该设计存在非法值、拼写错误和权限判断不一致风险。后续数据库开发应评估迁移为数字角色等级，例如 `0` 普通用户、`1` 普通管理员、`2` 超级管理员，并由前端 option / 常量表做展示映射。
- `pending_suits` 和 `app_errors` 仍有 Advisor 提示的宽松 policy；不在 DB-0 范围，后续应单独审查。
