-- 生产 pending 只读盘点脚本
-- 用途：盘点 production 库 pending_clothes / pending_suits 积压，辅助判断自动回扫、人工仲裁、重审或驳回范围。
-- 安全说明：本文件只包含 SELECT，不包含 insert / update / delete / truncate / alter / drop。
-- 执行位置：Supabase production 项目 SQL Editor。
-- 执行时间请按北京时间 UTC+8 记录到 docs/database/数据库变更记录.md。

-- 0. 环境确认
select
  current_database() as database_name,
  current_schema() as schema_name,
  now() as executed_at_utc;

-- 1. pending_clothes 状态总览
select
  status,
  count(*) as row_count
from public.pending_clothes
group by status
order by status;

-- 2. pending_clothes 当前积压概况
select
  count(*) as pending_total,
  count(distinct submitted_by) as submitter_count,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending';

-- 3. pending_suits 状态总览
select
  status,
  count(*) as row_count
from public.pending_suits
group by status
order by status;

-- 4. 缺字段 / 脏数据数量
select
  count(*) filter (where nullif(trim(coalesce(name, '')), '') is null) as missing_name,
  count(*) filter (where nullif(trim(coalesce(game_id, '')), '') is null) as missing_game_id,
  count(*) filter (where game_id is not null and trim(game_id) !~ '^[0-9]+$') as invalid_game_id,
  count(*) filter (where nullif(trim(coalesce(category, '')), '') is null) as missing_category,
  count(*) filter (where stars is null) as missing_stars,
  count(*) filter (where scores is null) as missing_scores,
  count(*) filter (where suit_id is null and nullif(trim(coalesce(temp_suit_name, '')), '') is null) as no_suit_state
from public.pending_clothes
where status = 'pending';

-- 5. 按分类统计积压
select
  category,
  count(*) as row_count,
  count(distinct submitted_by) as submitter_count,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending'
group by category
order by row_count desc, category
limit 50;

-- 6. 已存在正式库的重复 pending
-- 这类通常不应再入库，应进一步判断是历史重复、用户重复提交，还是正式库已有但用户衣柜未同步。
select
  p.category,
  p.game_id,
  count(*) as pending_count,
  count(distinct p.submitted_by) as submitter_count,
  c.id as clothes_id,
  c.name as clothes_name
from public.pending_clothes p
join public.clothes c
  on c.category = p.category
 and c.game_id = p.game_id
where p.status = 'pending'
group by p.category, p.game_id, c.id, c.name
order by pending_count desc, submitter_count desc
limit 100;

-- 7. 完全一致候选：满足 5 个不同提交者
-- 这是最接近“5 次相同提交自动入库”的候选，但仍建议先检查是否已有正式库重复。
select
  category,
  game_id,
  name,
  stars,
  suit_id,
  temp_suit_name,
  tags,
  scores,
  count(*) as row_count,
  count(distinct submitted_by) as submitter_count,
  array_agg(id order by created_at asc) as pending_ids,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending'
group by category, game_id, name, stars, suit_id, temp_suit_name, tags, scores
having count(distinct submitted_by) >= 5
order by submitter_count desc, row_count desc, oldest_created_at asc
limit 100;

-- 8. 完全一致候选：满足 5 行，但提交者不足 5 人
-- 这类可能是同一用户重复提交，不能用于“5 次不同提交者”自动入库。
select
  category,
  game_id,
  name,
  stars,
  count(*) as row_count,
  count(distinct submitted_by) as submitter_count,
  array_agg(id order by created_at asc) as pending_ids,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending'
group by category, game_id, name, stars, suit_id, temp_suit_name, tags, scores
having count(*) >= 5
   and count(distinct submitted_by) < 5
order by row_count desc, submitter_count desc
limit 100;

-- 9. 同一 分类 + 短编号 的字段冲突候选
-- variant_count > 1 表示同一部件身份下存在多个字段版本，不能直接自动入库。
with variants as (
  select
    category,
    game_id,
    md5(concat_ws('|',
      coalesce(name, ''),
      coalesce(stars::text, ''),
      coalesce(suit_id::text, ''),
      coalesce(temp_suit_name, ''),
      coalesce(tags, ''),
      coalesce(scores::text, '')
    )) as variant_hash,
    count(*) as row_count,
    count(distinct submitted_by) as submitter_count
  from public.pending_clothes
  where status = 'pending'
  group by category, game_id, variant_hash
)
select
  category,
  game_id,
  sum(row_count) as row_count,
  sum(submitter_count) as summed_submitter_count,
  count(*) as variant_count
from variants
group by category, game_id
having count(*) > 1
order by row_count desc, variant_count desc
limit 100;

-- 10. 字段冲突明细
-- 先从第 9 段结果里挑 category/game_id，再替换下面两个条件查看具体版本。
-- 示例：where status = 'pending' and category = '发型' and game_id = '0004'
select
  id,
  created_at,
  submitted_by,
  name,
  category,
  game_id,
  stars,
  suit_id,
  temp_suit_name,
  tags,
  scores
from public.pending_clothes
where status = 'pending'
  -- and category = '<替换分类>'
  -- and game_id = '<替换短编号>'
order by category, game_id, created_at asc
limit 100;

-- 11. 纯散件 / 缺套装状态聚类
-- 根据当前规则，这类可能需要“允许入库但进入待补套装追踪”或人工确认。
select
  category,
  game_id,
  name,
  stars,
  count(*) as row_count,
  count(distinct submitted_by) as submitter_count,
  array_agg(id order by created_at asc) as pending_ids,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending'
  and suit_id is null
  and nullif(trim(coalesce(temp_suit_name, '')), '') is null
group by category, game_id, name, stars, tags, scores
order by submitter_count desc, row_count desc
limit 100;

-- 12. 新套装申请聚类
select
  name,
  status,
  count(*) as row_count,
  count(distinct submitted_by) as submitter_count,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_suits
group by name, status
order by status, submitter_count desc, row_count desc, oldest_created_at asc
limit 100;

-- 13. 高贡献提交者积压
-- 用于判断是否需要优先审核某些高频提交者的数据。
select
  submitted_by,
  count(*) as pending_count,
  count(distinct category || ':' || coalesce(game_id, '')) as distinct_item_keys,
  min(created_at) as oldest_created_at,
  max(created_at) as newest_created_at
from public.pending_clothes
where status = 'pending'
group by submitted_by
order by pending_count desc
limit 50;
