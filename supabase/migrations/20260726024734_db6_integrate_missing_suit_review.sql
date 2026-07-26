begin;

alter table public.pending_clothes
  add column needs_suit_review boolean not null default false;

alter table public.pending_clothes
  add constraint pending_clothes_needs_suit_review_check
  check (
    not needs_suit_review
    or (
      suit_id is null
      and nullif(pg_catalog.btrim(coalesce(temp_suit_name, '')), '') is null
    )
  );

comment on column public.pending_clothes.needs_suit_review is
  'true 表示用户明确选择“所属套装待确认”；历史与默认 false 继续表示已有套装、申请新套装或纯散件。';

create function public.ensure_missing_suit_re_review_item(
  p_clothes_id text,
  p_pending_ids bigint[],
  p_allow_create boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_matching_count integer := 0;
  v_existing_item_count integer := 0;
  v_source_count integer := 0;
  v_primary_pending_id bigint;
  v_primary_user_id uuid;
  v_item_id uuid;
  v_existing_source_ids bigint[] := '{}'::bigint[];
  v_clothes public.clothes%rowtype;
  v_payload jsonb;
begin
  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception '待补套装来源不能为空，且不能包含空值或重复 ID';
  end if;

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = p_clothes_id
  for update;

  if not found then
    raise exception '待补套装正式服装不存在';
  end if;

  if v_clothes.suit_id is not null
    or nullif(pg_catalog.btrim(coalesce(v_clothes.temp_suit_name, '')), '') is not null then
    raise exception '已有套装信息的正式服装不能创建待补套装重审项';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (
      where pending.needs_suit_review
        and pending.status in ('pending', 'approved')
        and pending.name is not distinct from v_clothes.name
        and pending.category is not distinct from v_clothes.category
        and pg_catalog.btrim(coalesce(pending.game_id, ''))
          is not distinct from pg_catalog.btrim(coalesce(v_clothes.game_id, ''))
        and pg_catalog.btrim(coalesce(pending.stars::text, ''))
          is not distinct from pg_catalog.btrim(coalesce(v_clothes.stars, ''))
        and pending.scores is not distinct from v_clothes.scores
        and pending.suit_id is null
        and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '') is null
        and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(v_clothes.tags, '')), '')
    )::integer
    into v_requested_count, v_matching_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids)
    or v_matching_count <> v_requested_count then
    raise exception '待补套装来源与正式服装不一致，已拒绝创建重审项';
  end if;

  select pending.id, pending.submitted_by
    into v_primary_pending_id, v_primary_user_id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.created_at, pending.id, pending.submitted_by nulls last
  limit 1;

  v_payload := pg_catalog.to_jsonb(v_clothes)
    || pg_catalog.jsonb_build_object('needs_suit_review', true);

  select pg_catalog.count(*)::integer
    into v_existing_item_count
  from public.re_review_items as item
  where item.clothes_id = p_clothes_id
    and item.reason = 'missing_suit';

  if v_existing_item_count > 1 then
    raise exception '正式服装存在多个待补套装重审事实，禁止静默修复';
  end if;

  if v_existing_item_count = 1 then
    select item.id
      into v_item_id
    from public.re_review_items as item
    where item.clothes_id = p_clothes_id
      and item.reason = 'missing_suit'
    order by item.created_at, item.id
    limit 1;

    perform item.id
    from public.re_review_items as item
    where item.id = v_item_id
    for update;

    if not exists (
      select 1
      from public.re_review_items as item
      where item.id = v_item_id
        and item.status in ('pending', 'voting')
        and item.source_pending_id = v_primary_pending_id
        and item.payload is not distinct from v_payload
    ) then
      raise exception '既有待补套装重审事实与本次入库不一致，禁止静默补写';
    end if;

    select coalesce(
      pg_catalog.array_agg(source.source_pending_id order by source.source_pending_id),
      '{}'::bigint[]
    )
      into v_existing_source_ids
    from public.re_review_item_sources as source
    where source.re_review_item_id = v_item_id;

    if v_existing_source_ids is distinct from v_sorted_pending_ids then
      raise exception '既有待补套装来源事实不完整，禁止静默补写';
    end if;

    return v_item_id;
  end if;

  if not coalesce(p_allow_create, false) then
    raise exception '待补套装重审事实不存在，禁止在重试时静默补写';
  end if;

  insert into public.re_review_items (
    reason,
    status,
    source_pending_id,
    clothes_id,
    payload,
    submitted_by
  )
  values (
    'missing_suit',
    'pending',
    v_primary_pending_id,
    p_clothes_id,
    v_payload,
    v_primary_user_id
  )
  returning id into v_item_id;

  insert into public.re_review_item_sources (
    re_review_item_id,
    source_pending_id,
    source_user_id
  )
  select
    v_item_id,
    pending.id,
    pending.submitted_by
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id;

  get diagnostics v_source_count = row_count;

  if v_source_count <> v_requested_count then
    raise exception '待补套装来源写入数量异常，已回滚本次入库';
  end if;

  return v_item_id;
end;
$$;

revoke all on function public.ensure_missing_suit_re_review_item(text, bigint[], boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_missing_suit_re_review_item(text, bigint[], boolean)
  to service_role;

comment on function public.ensure_missing_suit_re_review_item(text, bigint[], boolean) is
  'DB-6 内部函数：在正式服装入库事务中创建并核验唯一待补套装重审项及全部 pending 来源；既有事实不完整时拒绝静默补写。';

alter function public.complete_existing_clothes_from_pending(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
)
rename to complete_existing_clothes_from_pending_db3_core;

revoke all on function public.complete_existing_clothes_from_pending_db3_core(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_existing_clothes_from_pending_db3_core(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
)
  to service_role;

create function public.complete_existing_clothes_from_pending(
  p_existing_id text,
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null,
  p_pending_ids bigint[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_missing_suit_count integer := 0;
  v_pending_count integer := 0;
  v_approved_count integer := 0;
  v_allow_create boolean := false;
  v_result jsonb;
  v_re_review_item_id uuid;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有补全正式库权限';
  end if;

  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception 'pending 来源不能为空，且不能包含空值或重复 ID';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (where pending.needs_suit_review)::integer,
    pg_catalog.count(*) filter (where pending.status = 'pending')::integer,
    pg_catalog.count(*) filter (where pending.status = 'approved')::integer
    into v_requested_count, v_missing_suit_count, v_pending_count, v_approved_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '部分 pending 来源不存在';
  end if;

  if v_missing_suit_count > 0
    and v_missing_suit_count <> v_requested_count then
    raise exception '纯散件与所属套装待确认来源不能混合补全';
  end if;

  if v_missing_suit_count = v_requested_count then
    if v_pending_count = v_requested_count then
      v_allow_create := true;
    elsif v_approved_count = v_requested_count then
      v_allow_create := false;
    else
      raise exception '所属套装待确认来源状态不一致，禁止静默补写';
    end if;
  end if;

  v_result := public.complete_existing_clothes_from_pending_db3_core(
    p_existing_id,
    p_name,
    p_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_sorted_pending_ids
  );

  if v_missing_suit_count = v_requested_count then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      p_existing_id,
      v_sorted_pending_ids,
      v_allow_create
    );

    v_result := v_result || pg_catalog.jsonb_build_object(
      're_review_item_id', v_re_review_item_id
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.complete_existing_clothes_from_pending(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
)
  from public, anon, authenticated, service_role;
grant execute on function public.complete_existing_clothes_from_pending(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
)
  to authenticated, service_role;

comment on function public.complete_existing_clothes_from_pending(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) is
  'DB-6 包装层：保持 DB-3 参数兼容；补全已有正式服装时，所属套装待确认来源必须同事务创建或核验唯一重审项。';

create function public.close_missing_suit_re_review_on_clothes_link()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.re_review_items
  set
    status = 'approved',
    resolved_by = (select auth.uid()),
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where clothes_id = new.id
    and reason = 'missing_suit'
    and status in ('pending', 'voting');

  return new;
end;
$$;

revoke all on function public.close_missing_suit_re_review_on_clothes_link()
  from public, anon, authenticated, service_role;
grant execute on function public.close_missing_suit_re_review_on_clothes_link()
  to service_role;

create trigger close_missing_suit_re_review_after_link
after update of suit_id on public.clothes
for each row
when (
  new.suit_id is not null
  and old.suit_id is distinct from new.suit_id
)
execute function public.close_missing_suit_re_review_on_clothes_link();

comment on function public.close_missing_suit_re_review_on_clothes_link() is
  'DB-6 内部触发器函数：正式服装绑定正式套装后自动关闭活跃的待补套装重审项。';

drop function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text
);

create function public.submit_clothing_contribution(
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null,
  p_needs_suit_review boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_game_id text := pg_catalog.btrim(coalesce(p_game_id, ''));
  v_normalized_temp_suit_name text := nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '');
  v_normalized_tags text := nullif(pg_catalog.btrim(coalesce(p_tags, '')), '');
  v_needs_suit_review boolean := coalesce(p_needs_suit_review, false);
  v_can_auto_approve boolean;
  v_pending_id bigint;
  v_matching_pending_ids bigint[] := '{}'::bigint[];
  v_matching_count integer := 0;
  v_effective_user_ids uuid[] := '{}'::uuid[];
  v_effective_pending_ids bigint[] := '{}'::bigint[];
  v_effective_created_ats timestamptz[] := '{}'::timestamptz[];
  v_effective_contributor_count integer := 0;
  v_clothes_id text;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_event_hash text;
  v_event_id uuid;
  v_contribution_id uuid;
  v_contribution_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_approved_pending_count integer := 0;
  v_existing_event_count integer := 0;
  v_matching_contribution_count integer := 0;
  v_matching_points_count integer := 0;
  v_matching_wardrobe_count integer := 0;
  v_re_review_item_id uuid;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交图鉴申请';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(v_game_id, '') is null then
    raise exception '短编号不能为空';
  end if;

  if v_game_id !~ '^[0-9]+$' then
    raise exception '短编号只允许填写数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  if v_needs_suit_review
    and (p_suit_id is not null or v_normalized_temp_suit_name is not null) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_can_auto_approve := p_suit_id is not null
    or v_normalized_temp_suit_name is not null
    or v_needs_suit_review;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|category_game|' || p_category || '|' || v_game_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|name_category|' || p_name || '|' || p_category, 0)
  );

  select clothes.*
    into v_existing_clothes
  from public.clothes as clothes
  where clothes.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id
  order by clothes.id
  limit 1
  for update;

  v_clothes_exists := found;

  if not v_clothes_exists then
    select clothes.*
      into v_existing_clothes
    from public.clothes as clothes
    where clothes.name is not distinct from p_name
      and clothes.category is not distinct from p_category
    order by clothes.id
    limit 1
    for update;

    v_clothes_exists := found;
  end if;

  if v_clothes_exists then
    if v_existing_clothes.name is distinct from p_name
      or v_existing_clothes.category is distinct from p_category
      or pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')) is distinct from v_game_id
      or pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')) is distinct from p_stars::text
      or v_existing_clothes.scores is distinct from p_scores
      or v_existing_clothes.suit_id is distinct from p_suit_id
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '')
        is distinct from v_normalized_temp_suit_name
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '')
        is distinct from v_normalized_tags then
      raise exception '正式库已存在同分类短编号或同名记录，但数据与本次提交不一致';
    end if;

    perform pending.id
    from public.pending_clothes as pending
    where pending.status = 'approved'
      and pending.needs_suit_review = v_needs_suit_review
      and pending.name is not distinct from p_name
      and pending.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
      and pending.stars is not distinct from p_stars
      and pending.scores is not distinct from p_scores
      and pending.suit_id is not distinct from p_suit_id
      and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
        is not distinct from v_normalized_temp_suit_name
      and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
        is not distinct from v_normalized_tags
    order by pending.id
    for update;

    select
      coalesce(pg_catalog.array_agg(pending.id order by pending.id), '{}'::bigint[]),
      pg_catalog.count(*)::integer
      into v_matching_pending_ids, v_matching_count
    from public.pending_clothes as pending
    where pending.status = 'approved'
      and pending.needs_suit_review = v_needs_suit_review
      and pending.name is not distinct from p_name
      and pending.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
      and pending.stars is not distinct from p_stars
      and pending.scores is not distinct from p_scores
      and pending.suit_id is not distinct from p_suit_id
      and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
        is not distinct from v_normalized_temp_suit_name
      and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
        is not distinct from v_normalized_tags;

    with earliest_per_user as (
      select distinct on (pending.submitted_by)
        pending.submitted_by as user_id,
        pending.id as source_pending_id,
        pending.created_at as source_created_at
      from public.pending_clothes as pending
      where pending.id = any(v_matching_pending_ids)
        and pending.submitted_by is not null
      order by pending.submitted_by, pending.created_at, pending.id
    ),
    effective_contributors as (
      select
        earliest.user_id,
        earliest.source_pending_id,
        earliest.source_created_at,
        pg_catalog.row_number() over (
          order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
        )::smallint as contribution_rank
      from earliest_per_user as earliest
      order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      limit 5
    )
    select
      coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
      coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
      coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
      into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
    from effective_contributors as effective;

    v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

    if v_effective_contributor_count = 5 then
      v_event_hash := pg_catalog.md5(
        'auto_entry|'
        || v_existing_clothes.id
        || '|'
        || pg_catalog.array_to_string(v_matching_pending_ids, ',')
      );
      v_event_id := (
        pg_catalog.substr(v_event_hash, 1, 8) || '-'
        || pg_catalog.substr(v_event_hash, 9, 4) || '-'
        || pg_catalog.substr(v_event_hash, 13, 4) || '-'
        || pg_catalog.substr(v_event_hash, 17, 4) || '-'
        || pg_catalog.substr(v_event_hash, 21, 12)
      )::uuid;

      select pg_catalog.count(*)::integer
        into v_existing_event_count
      from public.clothing_contributions as contribution
      where contribution.event_id = v_event_id;

      select pg_catalog.count(*)::integer
        into v_matching_contribution_count
      from pg_catalog.generate_subscripts(v_effective_user_ids, 1) as expected(array_index)
      join public.clothing_contributions as contribution
        on contribution.event_id = v_event_id
        and contribution.clothes_id = v_existing_clothes.id
        and contribution.user_id = v_effective_user_ids[expected.array_index]
        and contribution.source_pending_id = v_effective_pending_ids[expected.array_index]
        and contribution.source_created_at = v_effective_created_ats[expected.array_index]
        and contribution.contribution_rank = expected.array_index::smallint
        and contribution.contribution_type = 'auto_entry';

      select pg_catalog.count(*)::integer
        into v_matching_points_count
      from public.clothing_contributions as contribution
      join public.points_ledger as ledger
        on ledger.source_id = contribution.id
        and ledger.user_id = contribution.user_id
        and ledger.delta = 10
        and ledger.status = 'awarded'
        and ledger.source_type = 'clothing_contribution'
        and ledger.reversal_of is null
      where contribution.event_id = v_event_id;

      select pg_catalog.count(*)::integer
        into v_matching_wardrobe_count
      from pg_catalog.unnest(v_effective_user_ids) as expected(user_id)
      join public.user_wardrobes as wardrobe
        on wardrobe.user_id = expected.user_id
        and coalesce(wardrobe.owned_clothes, '[]'::jsonb)
          @> pg_catalog.jsonb_build_array(v_existing_clothes.id);

      if v_existing_event_count = v_effective_contributor_count
        and v_matching_contribution_count = v_effective_contributor_count
        and v_matching_points_count = v_effective_contributor_count
        and v_matching_wardrobe_count = v_effective_contributor_count then
        if v_needs_suit_review then
          v_re_review_item_id := public.ensure_missing_suit_re_review_item(
            v_existing_clothes.id,
            v_matching_pending_ids,
            false
          );
        end if;

        return pg_catalog.jsonb_build_object(
          'auto_approved', true,
          'clothes_id', v_existing_clothes.id,
          'matched_pending_count', v_matching_count,
          'wardrobe_updated_count', v_matching_wardrobe_count,
          're_review_item_id', v_re_review_item_id
        );
      end if;
    end if;

    if exists (
      select 1
      from public.clothing_contributions as contribution
      where contribution.clothes_id = v_existing_clothes.id
        and contribution.contribution_type = 'auto_entry'
    ) then
      raise exception '自动入库正式服装已存在，但来源、贡献、积分、衣柜或重审事实不完整；禁止静默补写';
    end if;

    raise exception '正式库已存在该服装，请刷新页面后使用现有图鉴条目';
  end if;

  select pending.id
    into v_pending_id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.submitted_by = v_user_id
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags
  order by pending.created_at, pending.id
  limit 1
  for update;

  if found then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  insert into public.pending_clothes (
    name,
    game_id,
    category,
    stars,
    scores,
    suit_id,
    temp_suit_name,
    tags,
    submitted_by,
    status,
    needs_suit_review
  )
  values (
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_user_id,
    'pending',
    v_needs_suit_review
  )
  returning id into v_pending_id;

  if p_suit_id is null and v_normalized_temp_suit_name is not null then
    insert into public.pending_suits (name, submitted_by, status)
    values (p_temp_suit_name, v_user_id, 'pending');
  end if;

  if not v_can_auto_approve then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags
  order by pending.id
  for update;

  select
    coalesce(pg_catalog.array_agg(pending.id order by pending.id), '{}'::bigint[]),
    pg_catalog.count(*)::integer
    into v_matching_pending_ids, v_matching_count
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags;

  with earliest_per_user as (
    select distinct on (pending.submitted_by)
      pending.submitted_by as user_id,
      pending.id as source_pending_id,
      pending.created_at as source_created_at
    from public.pending_clothes as pending
    where pending.id = any(v_matching_pending_ids)
      and pending.submitted_by is not null
    order by pending.submitted_by, pending.created_at, pending.id
  ),
  effective_contributors as (
    select
      earliest.user_id,
      earliest.source_pending_id,
      earliest.source_created_at,
      pg_catalog.row_number() over (
        order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      )::smallint as contribution_rank
    from earliest_per_user as earliest
    order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
    limit 5
  )
  select
    coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
    coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
    coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
    into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
  from effective_contributors as effective;

  v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

  if v_effective_contributor_count < 5 then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  v_clothes_id := 'custom_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
  v_event_hash := pg_catalog.md5(
    'auto_entry|'
    || v_clothes_id
    || '|'
    || pg_catalog.array_to_string(v_matching_pending_ids, ',')
  );
  v_event_id := (
    pg_catalog.substr(v_event_hash, 1, 8) || '-'
    || pg_catalog.substr(v_event_hash, 9, 4) || '-'
    || pg_catalog.substr(v_event_hash, 13, 4) || '-'
    || pg_catalog.substr(v_event_hash, 17, 4) || '-'
    || pg_catalog.substr(v_event_hash, 21, 12)
  )::uuid;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_matching_pending_ids)
  ) then
    raise exception '本次自动入库来源已存在贡献事实，但 pending 尚未完成；请人工核对';
  end if;

  insert into public.clothes (
    id,
    name,
    game_id,
    category,
    stars,
    scores,
    suit_id,
    temp_suit_name,
    tags
  )
  values (
    v_clothes_id,
    p_name,
    v_game_id,
    p_category,
    p_stars::text,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags
  );

  if v_needs_suit_review then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      v_clothes_id,
      v_matching_pending_ids,
      true
    );
  end if;

  for v_index in 1..v_effective_contributor_count loop
    insert into public.clothing_contributions (
      event_id,
      clothes_id,
      user_id,
      source_pending_id,
      contribution_type,
      contribution_rank,
      source_created_at
    )
    values (
      v_event_id,
      v_clothes_id,
      v_effective_user_ids[v_index],
      v_effective_pending_ids[v_index],
      'auto_entry',
      v_index::smallint,
      v_effective_created_ats[v_index]
    )
    returning id into v_contribution_id;

    v_contribution_count := v_contribution_count + 1;

    insert into public.points_ledger (
      user_id,
      delta,
      status,
      source_type,
      source_id
    )
    values (
      v_effective_user_ids[v_index],
      10,
      'awarded',
      'clothing_contribution',
      v_contribution_id
    );

    v_points_count := v_points_count + 1;
  end loop;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
    v_effective_user_ids,
    v_clothes_id
  );

  if v_contribution_count <> v_effective_contributor_count
    or v_points_count <> v_effective_contributor_count
    or v_wardrobe_count <> v_effective_contributor_count then
    raise exception '贡献、积分或衣柜写回数量异常，已回滚本次自动入库';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_matching_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_matching_count then
    raise exception 'pending 通过数量异常，已回滚本次自动入库';
  end if;

  return pg_catalog.jsonb_build_object(
    'auto_approved', true,
    'clothes_id', v_clothes_id,
    'matched_pending_count', v_approved_pending_count,
    'wardrobe_updated_count', v_wardrobe_count,
    're_review_item_id', v_re_review_item_id
  );
end;
$$;

revoke all on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) from public, anon, authenticated, service_role;

grant execute on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) to authenticated, service_role;

comment on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) is 'DB-6：兼容原提交参数；五位不同用户提交“所属套装待确认”的一致完整资料后，同事务自动入库、创建待补套装重审来源链并完成贡献、积分和衣柜写回。';

alter function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) rename to approve_pending_clothes_arbitration_db4_core;

revoke all on function public.approve_pending_clothes_arbitration_db4_core(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) from public, anon, authenticated, service_role;

grant execute on function public.approve_pending_clothes_arbitration_db4_core(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) to service_role;

comment on function public.approve_pending_clothes_arbitration_db4_core(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) is 'DB-6 内部兼容核心：保留 DB-4 管理员仲裁、贡献、积分、衣柜和 pending 原子写入，由公开包装函数补充待补套装重审链。';

create function public.approve_pending_clothes_arbitration(
  p_id text,
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null,
  p_pending_ids bigint[] default '{}',
  p_needs_suit_review boolean default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_distinct_review_values integer := 0;
  v_needs_suit_review boolean := false;
  v_result jsonb;
  v_re_review_item_id uuid;
begin
  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception '待审核记录不能为空，且不能包含空值或重复 ID';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(distinct pending.needs_suit_review)::integer,
    coalesce(pg_catalog.bool_or(pending.needs_suit_review), false)
    into v_requested_count, v_distinct_review_values, v_needs_suit_review
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '存在找不到的待审核记录';
  end if;

  if v_distinct_review_values <> 1 then
    raise exception '纯散件与所属套装待确认不能合并为同一次仲裁';
  end if;

  if p_needs_suit_review is not null
    and p_needs_suit_review is distinct from v_needs_suit_review then
    raise exception '审核表单的套装状态与来源记录不一致，请刷新后重试';
  end if;

  if v_needs_suit_review
    and (
      p_suit_id is not null
      or nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '') is not null
    ) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_result := public.approve_pending_clothes_arbitration_db4_core(
    p_id,
    p_name,
    p_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_sorted_pending_ids
  );

  if v_needs_suit_review then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      p_id,
      v_sorted_pending_ids,
      coalesce((v_result->>'already_completed')::boolean, false) = false
    );

    v_result := v_result || pg_catalog.jsonb_build_object(
      're_review_item_id',
      v_re_review_item_id
    );
  end if;

  return v_result;
end;
$$;

revoke all on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[], boolean
) from public, anon, authenticated, service_role;

grant execute on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[], boolean
) to authenticated, service_role;

comment on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[], boolean
) is 'DB-6：管理员仲裁保持 DB-4 原子闭环；所属套装待确认的来源同时创建并核验重审项，纯散件不进入重审池。';

commit;
