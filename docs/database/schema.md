# schema

当前文件是 development 项目 `tfwejruvdahonacyldrg` 的 public schema 摘要。

完整 public SQL 快照见：`supabase/schema.sql`，其 SHA-256 仍为 `91004C23062511813053A1462BC532FA5F41970C222187EC6268675BC5639D25`，但未包含 DB-8 / DB-9，不能作为这两期对象的当前事实。2026-07-28 已在 development 应用至 `20260728025707_db9_process_correction_requests`；DB-8 / DB-9 表、RPC、触发器、RLS、索引、约束、权限和事务回滚已通过 live catalog、Advisor 与生成类型回读。因全量 dump 仍遇到远端传输错误，没有覆盖既有快照；DB-8 / DB-9 以 migration、live catalog 和 `src/types/supabase.ts` 为当前权威。

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
| correction_requests | id | uuid | gen_random_uuid() | NO |
| correction_requests | clothes_id | character varying | null | NO |
| correction_requests | reported_by | uuid | null | YES |
| correction_requests | field_key | text | null | NO |
| correction_requests | reason | text | null | NO |
| correction_requests | proposed_patch | jsonb | null | NO |
| correction_requests | accepted_patch | jsonb | null | YES |
| correction_requests | clothes_snapshot | jsonb | null | NO |
| correction_requests | status | text | 'pending' | NO |
| correction_requests | reviewed_by | uuid | null | YES |
| correction_requests | resolution_note | text | null | YES |
| correction_requests | reviewed_at | timestamp with time zone | null | YES |
| correction_requests | source_pending_id | bigint | null | YES |
| correction_requests | re_review_item_id | uuid | null | YES |
| correction_requests | created_at | timestamp with time zone | now() | NO |
| correction_requests | updated_at | timestamp with time zone | now() | NO |
| jury_admin_decisions | id | uuid | gen_random_uuid() | NO |
| jury_admin_decisions | candidate_id | uuid | null | NO |
| jury_admin_decisions | re_review_item_id | uuid | null | NO |
| jury_admin_decisions | admin_user_id | uuid | null | YES |
| jury_admin_decisions | decision | text | null | NO |
| jury_admin_decisions | reason | text | null | NO |
| jury_admin_decisions | created_at | timestamp with time zone | now() | NO |
| jury_votes | id | uuid | gen_random_uuid() | NO |
| jury_votes | candidate_id | uuid | null | NO |
| jury_votes | user_id | uuid | null | YES |
| jury_votes | vote | text | null | NO |
| jury_votes | created_at | timestamp with time zone | now() | NO |
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
| pending_clothes | needs_suit_review | boolean | false | NO |
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
| points_ledger | re_review_candidate_id | uuid | null | YES |
| points_ledger | correction_request_id | uuid | null | YES |
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
| re_review_candidates | id | uuid | gen_random_uuid() | NO |
| re_review_candidates | re_review_item_id | uuid | null | NO |
| re_review_candidates | payload | jsonb | null | NO |
| re_review_candidates | submitted_by | uuid | null | YES |
| re_review_candidates | created_at | timestamp with time zone | now() | NO |
| re_review_candidates | status | text | 'voting' | NO |
| re_review_candidates | resolved_at | timestamp with time zone | null | YES |
| re_review_item_sources | re_review_item_id | uuid | null | NO |
| re_review_item_sources | source_pending_id | bigint | null | NO |
| re_review_item_sources | source_user_id | uuid | null | YES |
| re_review_item_sources | created_at | timestamp with time zone | now() | NO |
| re_review_items | id | uuid | gen_random_uuid() | NO |
| re_review_items | reason | text | null | NO |
| re_review_items | status | text | 'pending' | NO |
| re_review_items | source_pending_id | bigint | null | YES |
| re_review_items | clothes_id | character varying | null | YES |
| re_review_items | payload | jsonb | null | NO |
| re_review_items | submitted_by | uuid | null | YES |
| re_review_items | resolved_by | uuid | null | YES |
| re_review_items | created_at | timestamp with time zone | now() | NO |
| re_review_items | updated_at | timestamp with time zone | now() | NO |
| re_review_items | resolved_at | timestamp with time zone | null | YES |
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

## DB-6 社区重审池基础

| 对象 / 规则 | 当前契约 |
| --- | --- |
| `re_review_items` | 追踪 `missing_suit`、`field_conflict`、`field_missing`、`correction`；状态限定为 `pending / voting / approved / rejected / failed` |
| `re_review_item_sources` | 保留全部 pending 来源及来源用户；普通用户只能读取自己的来源标记，供 RLS 防自审使用 |
| `re_review_candidates` | 保存每一轮不可变候选快照；同一重审项最多一份 `voting` 候选，退回后保留旧轮次并允许提交新快照 |
| 社区读取 | 登录用户只能看到自己未提交、未作为主来源、也未作为任何来源参与的重审项 |
| 最小权限 | `PUBLIC` / `anon` 无权限；authenticated 不再直接写候选、投票或终审底表，只能调用受控 RPC；service_role 只保留必要底表权限 |
| 缺套装接入（development 已验证） | “所属套装待确认”以 `pending_clothes.needs_suit_review = true` 显式保存；自动入库、管理员仲裁与正式库已有补全同事务创建唯一 `missing_suit` 项及全部来源，绑定正式套装后自动关闭 |
| 当前边界 | 纯散件和历史空套装事实不进入重审池；`missing_suit`、`field_missing`、`field_conflict`、`correction` 已进入统一队列，正式图鉴报错由 DB-9 管理员核对后按字段现状直接补全或转入该队列 |

## DB-7 陪审团投票与独立终审

| 对象 / 规则 | 当前契约 |
| --- | --- |
| `submit_jury_candidate(...)` | 未参与原始数据的登录用户为统一重审项提交完整服装资料；只允许修改问题字段，退回后新内容形成新轮次，旧票和旧内容保留 |
| `get_jury_review_queue()` | 返回当前用户可参与的重审项、完整基础资料、全部问题字段与分歧值、当前待审核内容、票数、本人投票和可操作状态，不暴露底表写权限 |
| `cast_jury_vote(...)` | 一人一票且不可改票；同票重试幂等；候选提交者、原提交者和任一来源参与者均不得投票 |
| 通过 | 同意票 `>= 5` 且同意票多于反对票；同事务按冻结候选更新正式服装、关闭重审项，并向候选提交者写入 `+8` 积分流水 |
| 退回重审 | `反对票 - 同意票 >= 3`；候选轮次标记为 `returned`，重审项回到 `pending`，正式服装和积分均不修改 |
| 继续投票 | 未达到通过或退回门槛时保持 `voting` |
| `admin_reject_jury_candidate(...)` | 只有超级管理员可独立永久驳回；已参投、候选提交者、原提交者或来源参与者均不得终审，旧轮次不能覆盖当前候选 |
| 默认拒绝 | `jury_votes`、`jury_admin_decisions` 启用 RLS 且不给 authenticated 底表 policy / DML；四个公开 RPC 均为空 `search_path`、仅授权 authenticated / service_role，并在函数内复核身份和状态 |

## DB-8 / DB-9 正式图鉴报错闭环

| 对象 / 规则 | 当前契约 |
| --- | --- |
| `correction_requests` | 保存正式服装、单一问题字段、判断依据、建议值、提交时正式资料和处理状态；账号删除后匿名保留审计事实 |
| `submit_correction_request(...)` | 登录用户对现有正式服装提交单字段报错；相同内容重试幂等，同一活动报错不得改写 |
| `get_my_correction_requests()` | 只返回当前登录用户本人提交记录，不开放跨用户列表 |
| `get_correction_review_queue()` | 只向管理员返回待处理报错、正式资料、本人报错标记和允许分流，不开放底表读取 |
| `review_correction_request(...)` | 同事务执行不采纳、空字段直接补全或非空争议转全字段陪审；禁止自审、过期覆盖和不一致重试 |
| 报错奖励 | 直接补全即时唯一 `+5`；转陪审仅在最终资料采用核对结果后唯一 `+5`，未采用不奖励 |
| 当前业务边界 | 空字段可由管理员核实后补全；非空字段只能转全字段陪审；不采纳不修改正式资料，独立终审不奖励 |
| 默认拒绝 | RLS 已启用且无 policy；anon / authenticated 无底表权限，authenticated 只能调用四个空 `search_path` 受控 RPC |
| 最小权限 | service_role 仅保留 SELECT / INSERT / UPDATE；DELETE / TRUNCATE / REFERENCES / TRIGGER 已由前向 patch 撤销 |

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
| points_ledger_re_review_candidate_id_fkey | foreign key | points_ledger.re_review_candidate_id -> re_review_candidates.id，删除受限 |
| points_ledger_correction_request_id_fkey | foreign key | points_ledger.correction_request_id -> correction_requests.id，删除受限 |
| points_ledger_reversal_of_fkey | foreign key | points_ledger.reversal_of -> points_ledger.id，删除受限 |
| points_ledger_source_id_key | partial unique index | 一条贡献最多产生一条正向流水 |
| points_ledger_re_review_candidate_id_key | partial unique index | 每个通过的重审候选最多产生一条正向积分流水 |
| points_ledger_correction_request_id_key | partial unique index | 每条被采用的报错最多产生一条 `+5` 正向积分流水 |
| points_ledger_reversal_of_key | partial unique index | 一条原流水最多产生一条扣回流水 |
| points_ledger_user_occurred_at_idx | index | points_ledger.user_id, occurred_at desc |
| profiles_pkey | primary key | profiles.id |
| profiles_username_key | unique | profiles.username |
| re_review_items_pkey | primary key | re_review_items.id |
| re_review_items_source_pending_id_fkey | foreign key | re_review_items.source_pending_id -> pending_clothes.id，删除受限 |
| re_review_items_clothes_id_fkey | foreign key | re_review_items.clothes_id -> clothes.id，删除受限 |
| re_review_items_active_missing_suit_key | partial unique index | 同一正式服装最多一个活跃待补套装项 |
| re_review_items_active_pending_reason_key | partial unique index | 同一主 pending + reason 最多一个活跃重审项 |
| re_review_item_sources_pkey | primary key | re_review_item_sources.re_review_item_id, source_pending_id |
| re_review_item_sources_item_id_fkey | foreign key | re_review_item_sources.re_review_item_id -> re_review_items.id，删除受限 |
| re_review_item_sources_pending_id_fkey | foreign key | re_review_item_sources.source_pending_id -> pending_clothes.id，删除受限 |
| re_review_candidates_pkey | primary key | re_review_candidates.id |
| re_review_candidates_item_id_fkey | foreign key | re_review_candidates.re_review_item_id -> re_review_items.id，删除受限 |
| re_review_candidates_active_item_key | partial unique index | 每个重审项最多一份 `voting` 候选，历史轮次可保留 |
| jury_votes_pkey | primary key | jury_votes.id |
| jury_votes_candidate_id_fkey | foreign key | jury_votes.candidate_id -> re_review_candidates.id，删除受限 |
| jury_votes_user_id_fkey | foreign key | jury_votes.user_id -> auth.users.id，账号删除后置空 |
| correction_requests_pkey | primary key | correction_requests.id |
| correction_requests_clothes_id_fkey | foreign key | correction_requests.clothes_id -> clothes.id，删除受限 |
| correction_requests_reported_by_fkey | foreign key | correction_requests.reported_by -> auth.users.id，账号删除后置空 |
| correction_requests_reviewed_by_fkey | foreign key | correction_requests.reviewed_by -> auth.users.id，账号删除后置空 |
| correction_requests_source_pending_id_fkey | foreign key | correction_requests.source_pending_id -> pending_clothes.id，删除受限 |
| correction_requests_re_review_item_id_fkey | foreign key | correction_requests.re_review_item_id -> re_review_items.id，删除受限 |
| correction_requests_active_reporter_field_unique | partial unique index | 同一用户、正式服装和字段最多一个活动报错 |
| correction_requests_open_queue_idx | partial index | pending / reviewing 队列按创建时间读取 |
| correction_requests_source_pending_id_idx | index | 覆盖报错生成的 pending 来源外键 |
| correction_requests_re_review_item_id_idx | index | 覆盖报错关联的重审事项外键 |
| jury_votes_candidate_user_key | unique | 同一用户对同一候选轮次最多一票 |
| jury_votes_user_created_at_idx | partial index | 按用户和投票时间追溯非匿名投票 |
| jury_admin_decisions_pkey | primary key | jury_admin_decisions.id |
| jury_admin_decisions_candidate_id_fkey | foreign key | jury_admin_decisions.candidate_id -> re_review_candidates.id，删除受限 |
| jury_admin_decisions_item_id_fkey | foreign key | jury_admin_decisions.re_review_item_id -> re_review_items.id，删除受限 |
| jury_admin_decisions_admin_user_id_fkey | foreign key | jury_admin_decisions.admin_user_id -> auth.users.id，账号删除后置空 |
| jury_admin_decisions_candidate_key | unique | 每个候选轮次最多一条管理员终审记录 |
| jury_admin_decisions_item_created_at_idx | index | 按重审项和时间追溯终审记录 |
| jury_admin_decisions_admin_user_id_idx | partial index | 覆盖管理员用户外键，避免删除用户或按管理员追溯时扫描整表 |
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
| get_my_correction_requests() | RPC | DB-8 仅返回当前登录用户本人提交的正式服装报错和处理状态 |
| get_correction_review_queue() | RPC | DB-9 管理员报错队列；返回正式资料、建议、本人报错和可执行分流 |
| review_correction_request(...) | RPC | DB-9 原子执行不采纳、空字段补全或转全字段陪审，并结算直接采用奖励 |
| sync_correction_requests_from_re_review() | trigger function | DB-9 在关联陪审结束后按最终是否采用核对结果结案并幂等结算报错奖励 |
| deduct_user_quota(uuid) | function | 扣减用户 quota |
| handle_new_user() | trigger function | auth.users 新用户初始化 profiles |
| handle_new_user_quota() | trigger function | auth.users 新用户初始化 user_quotas |
| is_admin_or_super_admin() | function | 判断当前用户是否为管理员或最高站长 |
| is_super_admin() | function | 判断当前用户是否为 super_admin |
| normalize_known_clothing_tags(text) | function | 清洗已知服装标签 |
| submit_clothing_contribution(...) | RPC | DB-5 缺失项提交与 5 位不同用户一致后自动入库；保留来源 pending，原子写前 5 位贡献、每人 10 分和衣柜 |
| submit_correction_request(varchar, text, jsonb) | RPC | DB-8 登录用户提交单字段正式服装报错；数据库校验字段、长度、正式服装存在性、活动唯一性和幂等 |
| update_profile_username(text) | RPC | 登录用户更新自己的用户名 |
| trigger_auto_link_shadow_suits | trigger | suits insert 后执行 auto_link_shadow_suits() |
| sync_correction_requests_after_re_review | trigger | re_review_items 状态变化后同步关联报错的最终状态和奖励 |

## RLS 摘要

已启用 RLS：

- app_errors
- clothes
- clothing_contributions（DB-1 默认拒绝，无 policy）
- correction_requests（DB-8 默认拒绝，无 policy）
- pending_clothes
- pending_suits
- points_ledger（DB-1 默认拒绝，无 policy）
- profiles
- re_review_candidates
- re_review_item_sources
- re_review_items
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
- DB-6 三张表及 DB-7 两张新增事实表当前均为 0 行；候选提交、一人一票、通过、退回重审、独立终审、审计字段防伪、防自审和匿名拒绝已在事务内验证，回滚后无测试数据残留。
- DB-7 Security Advisor 对 `jury_votes`、`jury_admin_decisions` 的 RLS 无 policy 仅报告预期 INFO；两表不给客户端底表权限，authenticated 只通过受控 RPC 操作。Performance Advisor 首次发现终审管理员外键缺索引，`20260727124555_db7_index_admin_user_fk` 生效后目标告警已消失。
- DB-8 增强 fixture 已在 development 通过并 rollback 至 0 行；live catalog 确认 3 个外键均有索引、两个 `SECURITY DEFINER` RPC 均为空 `search_path` 且 anon 无执行权限，service_role 仅保留 SELECT / INSERT / UPDATE。原生 Advisor 命令受直连传输错误影响未返回，已用相同 catalog 检查逐项回读。
- Security Advisor 对两张 DB-1 表仅报告预期 INFO：RLS 已启用但没有 policy；DB-2 helper 位于未暴露 schema 且没有新增 Advisor WARN / ERROR。
- Security Advisor 仍报告 `stages`、`suits` 未启用 RLS；不属于本次 DB-0 范围，必须在后续独立安全任务处理。
- 当前 `profiles` 仍保留 `total_points`、`current_month_points`、`monthly_action_count` 字段；根据需求文档，后续积分权威来源应迁移到 `points_ledger`，这些字段只能作为历史字段或缓存字段，不应作为权威总分。
- 当前 `profiles.role` 为 `text`，并使用 `user`、`admin`、`super_admin` 字符串区分角色；该设计存在非法值、拼写错误和权限判断不一致风险。后续数据库开发应评估迁移为数字角色等级，例如 `0` 普通用户、`1` 普通管理员、`2` 超级管理员，并由前端 option / 常量表做展示映射。
- `pending_suits` 和 `app_errors` 仍有 Advisor 提示的宽松 policy；不在 DB-0 范围，后续应单独审查。
