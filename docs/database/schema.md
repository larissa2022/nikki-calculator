# schema

当前文件是 development 项目 `tfwejruvdahonacyldrg` 的 public schema 摘要。

完整 public SQL 快照见：`supabase/schema.sql`，其 SHA-256 仍为 `91004C23062511813053A1462BC532FA5F41970C222187EC6268675BC5639D25`，但未包含 DB-8～DB-11，不能作为这些对象的当前事实。2026-07-29 已在 development 应用至 DB-11 图片权限加固补丁；相关表、RPC、Storage、RLS、索引、约束、权限和事务回滚已通过 live catalog、fixture 与生成类型回读。因本补丁不要求覆盖全量 dump，migration、live catalog、本摘要和 `src/types/supabase.ts` 为当前权威。

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
| correction_requests | evidence_image_path | text | null | YES |
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

## DB-13 积分排行榜第一版只读面

| 对象 | 对外字段 | 角色与约束 |
| --- | --- | --- |
| `public.points_leaderboard_total` | `leaderboard_rank`、`display_name`、`points`、`is_current_user` | 仅 authenticated SELECT；从全部 `awarded` 流水实时汇总 |
| `public.points_leaderboard_current_month` | `leaderboard_rank`、`display_name`、`points`、`is_current_user` | 仅 authenticated SELECT；按 `Asia/Shanghai` 月初（含）至下月月初（不含）实时汇总 |
| `private_db2.total_points_leaderboard()` | 内部 helper | `SECURITY DEFINER`、`STABLE`、空 `search_path`；仅 authenticated 可执行 |
| `private_db2.current_month_points_leaderboard()` | 内部 helper | `SECURITY DEFINER`、`STABLE`、空 `search_path`；仅 authenticated 可执行 |

两个 public view 均为 `security_invoker + security_barrier` 且不可写；同分使用 `dense_rank` 并列。公开结果不含 user ID、email 或积分流水；无 username 时只返回基于 UUID 哈希的不可逆化名。DB-13 不新增缓存、快照或索引，也不改变 `points_ledger` 的底表权限。

## DB-14 上月榜冻结

| 对象 | 当前契约 |
| --- | --- |
| `private_db2.points_leaderboard_months` | 以北京时间自然月首日为主键，记录冻结时间与行数；空月份同样保留标记 |
| `private_db2.points_leaderboard_monthly_snapshots` | 只保存目标月份、用户、冻结积分、dense rank 名次和冻结时间；用户删除时 `user_id` 置空 |
| `private_db2.freeze_points_leaderboard_month(date)` | 仅 postgres 执行；只接受已结束自然月，事务 advisory lock 与月份唯一标记保证只冻结一次 |
| `private_db2.freeze_previous_month_if_due(timestamptz)` | 仅 postgres 执行；每日 UTC 16:05 由 `pg_cron` 调用，只在北京时间每月 1 日冻结上月 |
| `private_db2.last_month_points_leaderboard()` | 仅 authenticated 执行；积分与名次读取快照，名称和注销状态读取当前 profile / 用户事实 |
| `public.points_leaderboard_last_month` | `security_invoker + security_barrier`；仅 authenticated SELECT，字段与 DB-13 榜单一致 |

两张私有表均启用并强制 RLS，不向 anon、authenticated 或 service_role 授予底表权限。快照不保存展示名称，改名后显示新名称，账号删除后显示“已注销用户”。首次启用补冻最近一个已结束自然月；冻结后的积分流水变化不追改快照，也不自动授予首页鸣谢、广告免除或 Lv4 体验。

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
| 当前边界 | 纯散件和历史空套装事实不进入重审池；`missing_suit`、`field_missing`、`field_conflict`、`correction` 进入统一队列；新正式图鉴报错直接挂到该服装唯一的活动审核项，管理员队列仅保留历史记录兼容与异常兜底 |

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
| `submit_correction_request(...)` | 登录用户对现有正式服装提交单字段报错并原子挂到唯一活动陪审项；相同内容重试幂等，同一活动报错不得改写，报错者不得自审 |
| `get_my_correction_requests()` | 只返回当前登录用户本人提交记录，不开放跨用户列表 |
| `get_correction_review_queue()` | 只向管理员返回补丁前遗留待处理报错，用于兼容与异常兜底，不开放底表读取 |
| `review_correction_request(...)` | 保留处理遗留报错的原子分流能力；禁止自审、过期覆盖和不一致重试，不作为新报错前置步骤 |
| 报错奖励 | 陪审最终资料精确采用报错建议后唯一 `+5`；仅提交、转陪审、退回或未采用均不奖励 |
| 当前业务边界 | 新报错直接进入社区陪审，不直接修改正式资料；报错者和其他来源参与者不得自审，独立终审不奖励 |
| 投票中新增问题 | 新报错带来当前事项尚未包含的字段时，复用同一活动事项，将当前候选标记为 `returned` 并回到 `pending`；合并旧问题与新字段，保留历史票和 `+1` 参与积分，不修改正式资料 |
| 默认拒绝 | `correction_requests` 启用 RLS 且不给 anon / authenticated 底表 policy 或 DML 权限，客户端只能通过受控 RPC 操作 |
| 最小权限 | service_role 仅保留 SELECT / INSERT / UPDATE；DELETE / TRUNCATE / REFERENCES / TRIGGER 已由前向 patch 撤销 |

## DB-11 报错图鉴图片与访问加固

| 对象 | 当前规则 |
| --- | --- |
| `correction-evidence` | 私有 Storage bucket；单文件最大 8 MB，只允许 JPEG、PNG、WebP |
| `correction_requests.evidence_image_path` | 保存私有图片路径；新专用 RPC 强制必填，历史记录允许为空；路径格式受约束且非空路径唯一 |
| `submit_correction_request_with_evidence(...)` | 校验登录身份、本人目录、Storage owner 和 MIME 后复用原报错事务；相同报错与图片重试幂等 |
| `get_jury_review_queue_with_evidence()` | 在原陪审队列上附加当前事项的报错图片路径，不扩大可参与事项范围 |
| Storage 读取 | 报错者本人或当前有资格参与对应审核事项的陪审员可读；匿名用户及其他登录用户不可读 |
| Storage 删除 | 仅上传者本人可删除尚未绑定任何报错记录的图片 |
| 权限加固 | 旧 `submit_correction_request(...)` 不再向 authenticated 开放；Storage 判断函数位于非公开 `private` schema，客户端不能通过 public API 调用 |

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
| get_jury_review_queue_with_evidence() | RPC | DB-11 返回当前用户可参与的陪审队列，并附加相关私有图鉴图片路径 |
| review_correction_request(...) | RPC | DB-9 原子执行不采纳、空字段补全或转全字段陪审，并结算直接采用奖励 |
| sync_correction_requests_from_re_review() | trigger function | DB-9 在关联陪审结束后按最终是否采用核对结果结案并幂等结算报错奖励 |
| deduct_user_quota(uuid) | function | 扣减用户 quota |
| handle_new_user() | trigger function | auth.users 新用户初始化 profiles |
| handle_new_user_quota() | trigger function | auth.users 新用户初始化 user_quotas |
| is_admin_or_super_admin() | function | 判断当前用户是否为管理员或最高站长 |
| is_super_admin() | function | 判断当前用户是否为 super_admin |
| normalize_known_clothing_tags(text) | function | 清洗已知服装标签 |
| submit_clothing_contribution(...) | RPC | DB-5 缺失项提交与 5 位不同用户一致后自动入库；保留来源 pending，原子写前 5 位贡献、每人 10 分和衣柜 |
| submit_correction_request(varchar, text, jsonb) | internal RPC | DB-11 后仅 service_role 可执行的兼容核心；authenticated 必须走带图片的专用入口 |
| submit_correction_request_with_evidence(varchar, jsonb, text) | RPC | DB-11 登录用户提交单字段正式图鉴报错；强制绑定本人上传的私有游戏内图鉴图片 |
| route_correction_request_to_jury(uuid) | internal function | 将报错来源挂到该服装唯一活动审核项，合并报错字段与正式资料其他缺失字段；不对客户端开放 |
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
- DB-13 新增总榜和北京时间当月榜两个登录后只读面；fixture 在 development 通过并 `ROLLBACK`，原有 22 条积分流水数量不变且 fixture 无残留。随后为人工验收单独保留 2 条各 `+10` 的 development 测试流水，当前合计 24 条；测试账号和依赖只用于 DB-13 验收。
- DB-14 新增上一完整北京时间自然月冻结榜；fixture 在 development 通过并 `ROLLBACK`，没有新增或改写积分流水。因 `2026-06` 无真实积分，development 为人工验收仅在派生快照中保留 `DB13验收甲`、`DB13验收乙` 两条 10 分并列第 1 的专用测试行，月标记与快照均为 2 行口径。
- DB-3 已形成 1 条 development 人工验收贡献和 1 条 `+5` 积分流水；DB-4 事务 fixture 全部回滚，未新增持久贡献或积分数据。
- DB-6 三张表及 DB-7 两张新增事实表当前均为 0 行；候选提交、一人一票、通过、退回重审、独立终审、审计字段防伪、防自审和匿名拒绝已在事务内验证，回滚后无测试数据残留。
- DB-7 Security Advisor 对 `jury_votes`、`jury_admin_decisions` 的 RLS 无 policy 仅报告预期 INFO；两表不给客户端底表权限，authenticated 只通过受控 RPC 操作。Performance Advisor 首次发现终审管理员外键缺索引，`20260727124555_db7_index_admin_user_fk` 生效后目标告警已消失。
- DB-8 增强 fixture 已在 development 通过并 rollback 至 0 行；live catalog 确认 3 个外键均有索引、两个 `SECURITY DEFINER` RPC 均为空 `search_path` 且 anon 无执行权限，service_role 仅保留 SELECT / INSERT / UPDATE。原生 Advisor 命令受直连传输错误影响未返回，已用相同 catalog 检查逐项回读。
- DB-11 fixture 已在 development 通过并 `ROLLBACK`；live catalog 确认私有 bucket、路径约束与索引、三条 Storage policy、专用提交和陪审队列 RPC、旧入口撤权及 `private` helper 的空 `search_path`。Performance Advisor 未发现 DB-11 新问题；Security Advisor 接口在补丁后连续传输失败，已保留为未取得的远端检查结果，未用 catalog 回读冒充 Advisor 通过。
- Security Advisor 对两张 DB-1 表仅报告预期 INFO：RLS 已启用但没有 policy；DB-2 helper 位于未暴露 schema 且没有新增 Advisor WARN / ERROR。
- Security Advisor 仍报告 `stages`、`suits` 未启用 RLS；不属于本次 DB-0 范围，必须在后续独立安全任务处理。
- 当前 `profiles` 仍保留 `total_points`、`current_month_points`、`monthly_action_count` 字段；根据需求文档，后续积分权威来源应迁移到 `points_ledger`，这些字段只能作为历史字段或缓存字段，不应作为权威总分。
- 当前 `profiles.role` 为 `text`，并使用 `user`、`admin`、`super_admin` 字符串区分角色；该设计存在非法值、拼写错误和权限判断不一致风险。后续数据库开发应评估迁移为数字角色等级，例如 `0` 普通用户、`1` 普通管理员、`2` 超级管理员，并由前端 option / 常量表做展示映射。
- `pending_suits` 和 `app_errors` 仍有 Advisor 提示的宽松 policy；不在 DB-0 范围，后续应单独审查。
## DB-15 普通管理员月度轮换

- `admin_terms`：普通管理员月度、手动和旧管理员过渡任期的唯一权限事实；按起止时间和状态实时复核。
- `private_db2.admin_rotation_candidates`：按服务月冻结候选积分、有效行为数、并列时间、顺序及跳过原因。
- `admin_candidate_exclusions`：超级管理员维护的带原因、起止时间和撤销事实的候选排除。
- `admin_review_decisions` / `admin_review_decision_sources`：不可由客户端修改或删除的低风险审核决定、采用资料和全部来源 pending 审计。
- 月度定时任务北京时间每月 1 日 00:10 执行；缺少 DB-14 上月冻结标记时失败关闭，部署当月不追授。
- 普通管理员只通过 `get_current_admin_capabilities()`、`list_low_risk_clothes_review_candidates()` 和 `review_low_risk_clothes_candidate(...)` 获取或执行受限能力；套装、补全、重审、报错、永久驳回和治理仍只属于超级管理员。
- `pending_clothes` 底表只允许用户读取本人申请、超级管理员读取全部并直接更新状态；普通管理员不再获得整表 RLS 能力。
