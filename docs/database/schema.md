# schema

当前文件是 development 项目 `tfwejruvdahonacyldrg` 的 public schema 摘要。

完整 SQL dump 见：`supabase/schema.sql`

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

## 主要约束与索引

| 对象 | 类型 | 字段 / 说明 |
| --- | --- | --- |
| clothes_pkey | primary key | clothes.id |
| clothes_name_category_unique | unique | clothes.name, clothes.category |
| clothes_suit_id_fkey | foreign key | clothes.suit_id -> suits.id |
| pending_clothes_pkey | primary key | pending_clothes.id |
| pending_clothes_submitted_by_fkey | foreign key | pending_clothes.submitted_by -> auth.users.id |
| pending_clothes_suit_id_fkey | foreign key | pending_clothes.suit_id -> suits.id |
| pending_suits_pkey | primary key | pending_suits.id |
| pending_suits_submitted_by_fkey | foreign key | pending_suits.submitted_by -> auth.users.id |
| profiles_pkey | primary key | profiles.id |
| profiles_username_key | unique | profiles.username |
| suits_pkey | primary key | suits.id |
| suits_name_key | unique | suits.name |
| idx_clothes_suit_id | index | clothes.suit_id |
| idx_pending_clothes_status | index | pending_clothes.status |
| idx_pending_suits_status | index | pending_suits.status |
| idx_profiles_username | index | profiles.username |
| idx_suits_name | index | suits.name |

## 函数与触发器

| 名称 | 类型 | 说明 |
| --- | --- | --- |
| auto_link_shadow_suits() | trigger function | 新套装入库后自动关联临时套装名匹配的 clothes / pending_clothes |
| deduct_user_quota(uuid) | function | 扣减用户 quota |
| handle_new_user() | trigger function | auth.users 新用户初始化 profiles |
| handle_new_user_quota() | trigger function | auth.users 新用户初始化 user_quotas |
| is_super_admin() | function | 判断当前用户是否为 super_admin |
| normalize_known_clothing_tags(text) | function | 清洗已知服装标签 |
| submit_clothing_contribution(...) | RPC | 缺失项提交与 5 次一致自动入库 |
| trigger_auto_link_shadow_suits | trigger | suits insert 后执行 auto_link_shadow_suits() |

## RLS 摘要

已启用 RLS：

- app_errors
- clothes
- pending_suits
- profiles
- user_quotas
- user_wardrobes

当前注意事项：

- `pending_clothes` 当前有 insert policy，但 schema dump 中未显示启用 RLS。后续实现审核闭环前需要重新审查。
- 当前 `profiles` 仍保留 `total_points`、`current_month_points`、`monthly_action_count` 字段；根据需求文档，后续积分权威来源应迁移到 `points_ledger`，这些字段只能作为历史字段或缓存字段，不应作为权威总分。
- 当前 `profiles.role` 为 `text`，并使用 `user`、`admin`、`super_admin` 字符串区分角色；该设计存在非法值、拼写错误和权限判断不一致风险。后续数据库开发应评估迁移为数字角色等级，例如 `0` 普通用户、`1` 普通管理员、`2` 超级管理员，并由前端 option / 常量表做展示映射。
- 当前部分 grant 较宽，后续新增积分、重审、陪审团前需要做 RLS 收紧审查。
