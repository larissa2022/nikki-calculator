begin;

create or replace function public.approve_pending_clothes_arbitration(
  p_id text,
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
  v_pending_ids bigint[] := coalesce(p_pending_ids, '{}');
  v_sorted_pending_ids bigint[] := '{}';
  v_requested_pending_count integer := 0;
  v_matched_pending_count integer := 0;
  v_pending_status_count integer := 0;
  v_approved_status_count integer := 0;
  v_approved_pending_count integer := 0;
  v_effective_user_ids uuid[] := '{}';
  v_effective_pending_ids bigint[] := '{}';
  v_effective_created_ats timestamptz[] := '{}';
  v_effective_contributor_count integer := 0;
  v_contribution_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_existing_event_count integer := 0;
  v_matching_contribution_count integer := 0;
  v_matching_points_count integer := 0;
  v_matching_wardrobe_count integer := 0;
  v_event_hash text;
  v_event_id uuid;
  v_contribution_id uuid;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_index integer;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有仲裁入库权限';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_id, '')), '') is null then
    raise exception '服装 ID 不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_game_id, '')), '') is null
    or pg_catalog.btrim(p_game_id) !~ '^[0-9]+$' then
    raise exception '短编号必须为数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(v_pending_ids) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_pending_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_pending_count = 0 then
    raise exception '待审核记录不能为空';
  end if;

  if v_requested_pending_count <> pg_catalog.cardinality(v_pending_ids) then
    raise exception '待审核记录包含空值或重复 ID';
  end if;

  v_event_hash := pg_catalog.md5(
    'admin_arbitration|'
    || p_id
    || '|'
    || pg_catalog.array_to_string(v_sorted_pending_ids, ',')
  );
  v_event_id := (
    pg_catalog.substr(v_event_hash, 1, 8) || '-'
    || pg_catalog.substr(v_event_hash, 9, 4) || '-'
    || pg_catalog.substr(v_event_hash, 13, 4) || '-'
    || pg_catalog.substr(v_event_hash, 17, 4) || '-'
    || pg_catalog.substr(v_event_hash, 21, 12)
  )::uuid;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (where pending.status = 'pending')::integer,
    pg_catalog.count(*) filter (where pending.status = 'approved')::integer,
    pg_catalog.count(*) filter (
      where pending.name is not distinct from p_name
        and pending.category is not distinct from p_category
        and nullif(pg_catalog.btrim(coalesce(pending.game_id, '')), '') is not null
        and pg_catalog.btrim(pending.game_id) = pg_catalog.btrim(p_game_id)
        and pending.stars is not distinct from p_stars
        and pending.scores is not distinct from p_scores
        and pending.suit_id is not distinct from p_suit_id
        and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '')
        and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_tags, '')), '')
    )::integer
    into
      v_requested_pending_count,
      v_pending_status_count,
      v_approved_status_count,
      v_matched_pending_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_pending_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '存在找不到的待审核记录';
  end if;

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '存在与本次管理员仲裁最终数据不一致的待审核记录，已拒绝入库';
  end if;

  with earliest_per_user as (
    select distinct on (pending.submitted_by)
      pending.submitted_by as user_id,
      pending.id as source_pending_id,
      pending.created_at as source_created_at
    from public.pending_clothes as pending
    where pending.id = any(v_sorted_pending_ids)
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

  select *
    into v_existing_clothes
  from public.clothes
  where id = p_id
  for update;

  v_clothes_exists := found;

  if v_pending_status_count = 0 and v_approved_status_count = v_requested_pending_count then
    if not v_clothes_exists
      or v_existing_clothes.name is distinct from p_name
      or v_existing_clothes.category is distinct from p_category
      or pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')) is distinct from pg_catalog.btrim(p_game_id)
      or pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')) is distinct from p_stars::text
      or v_existing_clothes.scores is distinct from p_scores
      or v_existing_clothes.suit_id is distinct from p_suit_id
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '')
        is distinct from nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '')
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '')
        is distinct from nullif(pg_catalog.btrim(coalesce(p_tags, '')), '') then
      raise exception '待审核记录已通过，但正式服装事实与本次仲裁不一致；禁止自动回填';
    end if;

    select pg_catalog.count(*)::integer
      into v_existing_event_count
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id;

    select pg_catalog.count(*)::integer
      into v_matching_contribution_count
    from pg_catalog.generate_subscripts(v_effective_user_ids, 1) as expected(array_index)
    join public.clothing_contributions as contribution
      on contribution.event_id = v_event_id
      and contribution.clothes_id = p_id
      and contribution.user_id = v_effective_user_ids[expected.array_index]
      and contribution.source_pending_id = v_effective_pending_ids[expected.array_index]
      and contribution.source_created_at = v_effective_created_ats[expected.array_index]
      and contribution.contribution_rank = expected.array_index::smallint
      and contribution.contribution_type = 'admin_arbitration';

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
        @> pg_catalog.jsonb_build_array(p_id);

    if v_existing_event_count <> v_effective_contributor_count
      or v_matching_contribution_count <> v_effective_contributor_count
      or v_matching_points_count <> v_effective_contributor_count
      or v_matching_wardrobe_count <> v_effective_contributor_count then
      raise exception '待审核记录已通过，但贡献、积分或衣柜事实不完整；禁止自动回填，请人工核对';
    end if;

    return pg_catalog.jsonb_build_object(
      'approved', true,
      'already_completed', true,
      'event_id', v_event_id,
      'clothes_id', p_id,
      'approved_pending_count', v_requested_pending_count,
      'submitter_count', v_effective_contributor_count,
      'contribution_count', v_matching_contribution_count,
      'points_awarded_count', v_matching_points_count,
      'points_awarded_total', v_matching_points_count * 10,
      'wardrobe_updated_count', v_matching_wardrobe_count
    );
  end if;

  if v_pending_status_count <> v_requested_pending_count or v_approved_status_count <> 0 then
    raise exception '待审核记录状态不一致，请刷新审核页后重试';
  end if;

  if v_clothes_exists then
    raise exception '正式库已存在该服装，请刷新后台后使用正式库补全或重审流程';
  end if;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_sorted_pending_ids)
  ) then
    raise exception '本次来源已存在贡献事实，但待审核状态未完成；请人工核对';
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
    p_id,
    p_name,
    pg_catalog.btrim(p_game_id),
    p_category,
    p_stars::text,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags
  );

  if v_effective_contributor_count > 0 then
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
        p_id,
        v_effective_user_ids[v_index],
        v_effective_pending_ids[v_index],
        'admin_arbitration',
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
  end if;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
    v_effective_user_ids,
    p_id
  );

  if v_contribution_count <> v_effective_contributor_count
    or v_points_count <> v_effective_contributor_count
    or v_wardrobe_count <> v_effective_contributor_count then
    raise exception '贡献、积分或衣柜写回数量异常，已回滚本次仲裁';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_sorted_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '待审核记录通过数量异常，已回滚本次仲裁';
  end if;

  return pg_catalog.jsonb_build_object(
    'approved', true,
    'already_completed', false,
    'event_id', v_event_id,
    'clothes_id', p_id,
    'approved_pending_count', v_approved_pending_count,
    'submitter_count', v_effective_contributor_count,
    'contribution_count', v_contribution_count,
    'points_awarded_count', v_points_count,
    'points_awarded_total', v_points_count * 10,
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$$;

revoke all on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) from public, anon, authenticated, service_role;

grant execute on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) to authenticated, service_role;

comment on function public.approve_pending_clothes_arbitration(
  text, text, text, text, integer, jsonb, uuid, text, text, bigint[]
) is 'DB-4：管理员仲裁入库，同事务记录前 5 位有效贡献者、每人 10 分、衣柜写回和 pending 通过；服务端核对候选且重复请求幂等。';

commit;
