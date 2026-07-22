begin;

create or replace function public.submit_clothing_contribution(
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null
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
  v_can_auto_approve boolean;
  v_pending_id bigint;
  v_matching_pending_ids bigint[] := '{}';
  v_matching_count integer := 0;
  v_effective_user_ids uuid[] := '{}';
  v_effective_pending_ids bigint[] := '{}';
  v_effective_created_ats timestamptz[] := '{}';
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
  v_index integer;
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

  v_can_auto_approve := p_suit_id is not null or v_normalized_temp_suit_name is not null;

  -- Serialize both the category/game-id business key and the existing name/category
  -- uniqueness key so concurrent fifth/sixth submissions cannot create two entries.
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
        return pg_catalog.jsonb_build_object(
          'auto_approved', true,
          'clothes_id', v_existing_clothes.id,
          'matched_pending_count', v_matching_count,
          'wardrobe_updated_count', v_matching_wardrobe_count
        );
      end if;
    end if;

    if exists (
      select 1
      from public.clothing_contributions as contribution
      where contribution.clothes_id = v_existing_clothes.id
        and contribution.contribution_type = 'auto_entry'
    ) then
      raise exception '自动入库正式服装已存在，但来源、贡献、积分或衣柜事实不完整；禁止静默补写';
    end if;

    raise exception '正式库已存在该服装，请刷新页面后使用现有图鉴条目';
  end if;

  select pending.id
    into v_pending_id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.submitted_by = v_user_id
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
    status
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
    'pending'
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
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$$;

revoke all on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text
) to authenticated, service_role;

comment on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text
) is 'DB-5：五位不同有效用户资料一致后自动入库；同事务保留并批准来源 pending、记录前 5 位贡献者、每人 10 分和衣柜写回，并支持重复请求幂等。';

commit;
