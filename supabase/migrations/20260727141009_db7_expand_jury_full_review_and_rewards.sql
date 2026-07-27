begin;

alter table public.re_review_items
  add column identity_key text;

update public.re_review_items
set identity_key = case
  when clothes_id is not null then 'clothes|' || clothes_id
  else 'pending|' || source_pending_id::text
end
where identity_key is null;

create unique index re_review_items_active_identity_key
  on public.re_review_items (identity_key)
  where identity_key is not null
    and status in ('pending', 'voting', 'failed');

alter table public.points_ledger
  add column jury_vote_id uuid;

alter table public.points_ledger
  add constraint points_ledger_jury_vote_id_fkey
  foreign key (jury_vote_id)
  references public.jury_votes (id)
  on delete restrict;

alter table public.points_ledger
  drop constraint points_ledger_source_type_check,
  drop constraint points_ledger_entry_shape_check;

alter table public.points_ledger
  add constraint points_ledger_source_type_check
    check (source_type in ('clothing_contribution', 're_review_candidate', 'jury_vote', 'reversal')),
  add constraint points_ledger_entry_shape_check
    check (
      (
        source_type = 'clothing_contribution'
        and source_id is not null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and reversal_of is null
        and delta > 0
      )
      or
      (
        source_type = 're_review_candidate'
        and source_id is null
        and re_review_candidate_id is not null
        and jury_vote_id is null
        and reversal_of is null
        and delta > 0
      )
      or
      (
        source_type = 'jury_vote'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is not null
        and reversal_of is null
        and delta = 1
      )
      or
      (
        source_type = 'reversal'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and reversal_of is not null
        and delta < 0
      )
    );

create unique index points_ledger_jury_vote_id_key
  on public.points_ledger (jury_vote_id)
  where jury_vote_id is not null;

insert into public.points_ledger (
  user_id,
  delta,
  status,
  source_type,
  source_id,
  re_review_candidate_id,
  jury_vote_id,
  reversal_of,
  occurred_at
)
select
  vote.user_id,
  1,
  'awarded',
  'jury_vote',
  null,
  null,
  vote.id,
  null,
  vote.created_at
from public.jury_votes as vote
where vote.user_id is not null
on conflict (jury_vote_id) where jury_vote_id is not null do nothing;

alter table public.clothing_contributions
  drop constraint clothing_contributions_type_check;

alter table public.clothing_contributions
  add constraint clothing_contributions_type_check
  check (
    contribution_type in (
      'auto_entry',
      'admin_arbitration',
      'existing_field_completion',
      'jury_resolution'
    )
  );

create or replace function public.jury_record_payload(
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid,
  p_temp_suit_name text,
  p_tags text,
  p_needs_suit_review boolean
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_build_object(
    'name', nullif(pg_catalog.btrim(coalesce(p_name, '')), ''),
    'game_id', nullif(pg_catalog.btrim(coalesce(p_game_id, '')), ''),
    'category', nullif(pg_catalog.btrim(coalesce(p_category, '')), ''),
    'stars', p_stars,
    'scores', coalesce(p_scores, '{}'::jsonb),
    'suit_id', case when p_suit_id is null then null else p_suit_id::text end,
    'temp_suit_name', nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), ''),
    'tags', nullif(pg_catalog.btrim(coalesce(p_tags, '')), ''),
    'needs_suit_review', coalesce(p_needs_suit_review, false)
  );
$$;

create or replace function public.jury_pending_payload(p_pending_id bigint)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select public.jury_record_payload(
    pending.name,
    pending.game_id,
    pending.category,
    pending.stars,
    pending.scores,
    pending.suit_id,
    pending.temp_suit_name,
    pending.tags,
    pending.needs_suit_review
  )
  from public.pending_clothes as pending
  where pending.id = p_pending_id;
$$;

create or replace function public.jury_clothes_payload(p_clothes_id text)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select public.jury_record_payload(
    clothes.name,
    clothes.game_id,
    clothes.category,
    case
      when nullif(pg_catalog.btrim(coalesce(clothes.stars, '')), '') ~ '^[0-9]+$'
        then clothes.stars::integer
      else null
    end,
    clothes.scores,
    clothes.suit_id,
    clothes.temp_suit_name,
    clothes.tags,
    false
  )
  from public.clothes as clothes
  where clothes.id = p_clothes_id;
$$;

create or replace function public.jury_payload_field_value(
  p_payload jsonb,
  p_field text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_field
    when 'pair1' then pg_catalog.jsonb_build_object(
      'simple', p_payload->'scores'->'simple',
      'gorgeous', p_payload->'scores'->'gorgeous'
    )
    when 'pair2' then pg_catalog.jsonb_build_object(
      'active', p_payload->'scores'->'active',
      'elegant', p_payload->'scores'->'elegant'
    )
    when 'pair3' then pg_catalog.jsonb_build_object(
      'cute', p_payload->'scores'->'cute',
      'mature', p_payload->'scores'->'mature'
    )
    when 'pair4' then pg_catalog.jsonb_build_object(
      'pure', p_payload->'scores'->'pure',
      'sexy', p_payload->'scores'->'sexy'
    )
    when 'pair5' then pg_catalog.jsonb_build_object(
      'cool', p_payload->'scores'->'cool',
      'warm', p_payload->'scores'->'warm'
    )
    when 'suit' then pg_catalog.jsonb_build_object(
      'suit_id', p_payload->'suit_id',
      'temp_suit_name', p_payload->'temp_suit_name',
      'needs_suit_review', p_payload->'needs_suit_review'
    )
    else coalesce(p_payload->p_field, 'null'::jsonb)
  end;
$$;

create or replace function public.jury_field_value_is_missing(
  p_payload jsonb,
  p_field text
)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_left_field text;
  v_right_field text;
  v_left numeric;
  v_right numeric;
begin
  if p_field = 'tags' then
    return false;
  end if;

  if p_field = 'suit' then
    return coalesce(
      case
        when pg_catalog.jsonb_typeof(p_payload->'needs_suit_review') = 'boolean'
          then (p_payload->>'needs_suit_review')::boolean
        else true
      end,
      true
    ) or nullif(pg_catalog.btrim(coalesce(p_payload->>'temp_suit_name', '')), '') is not null;
  end if;

  case p_field
    when 'pair1' then v_left_field := 'simple'; v_right_field := 'gorgeous';
    when 'pair2' then v_left_field := 'active'; v_right_field := 'elegant';
    when 'pair3' then v_left_field := 'cute'; v_right_field := 'mature';
    when 'pair4' then v_left_field := 'pure'; v_right_field := 'sexy';
    when 'pair5' then v_left_field := 'cool'; v_right_field := 'warm';
    else
      return coalesce(p_payload->p_field = 'null'::jsonb, true);
  end case;

  if pg_catalog.jsonb_typeof(p_payload->'scores'->v_left_field) <> 'number'
    or pg_catalog.jsonb_typeof(p_payload->'scores'->v_right_field) <> 'number' then
    return true;
  end if;

  v_left := (p_payload->'scores'->>v_left_field)::numeric;
  v_right := (p_payload->'scores'->>v_right_field)::numeric;
  return not (
    (v_left > 0 and v_right = 0)
    or (v_right > 0 and v_left = 0)
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return true;
end;
$$;

create or replace function public.build_jury_review_payload(
  p_pending_ids bigint[],
  p_clothes_id text default null
)
returns jsonb
language plpgsql
stable
set search_path = ''
as $$
declare
  v_fields text[] := array[
    'name', 'game_id', 'category', 'stars',
    'pair1', 'pair2', 'pair3', 'pair4', 'pair5',
    'suit', 'tags'
  ];
  v_field text;
  v_base jsonb;
  v_values jsonb;
  v_distinct_count integer;
  v_has_null boolean;
  v_issues jsonb := '[]'::jsonb;
  v_options jsonb := '{}'::jsonb;
begin
  if p_clothes_id is not null then
    v_base := public.jury_clothes_payload(p_clothes_id);
  else
    select public.jury_pending_payload(pending.id)
      into v_base
    from public.pending_clothes as pending
    where pending.id = any(coalesce(p_pending_ids, '{}'::bigint[]))
    order by pending.created_at, pending.id
    limit 1;
  end if;

  if v_base is null then
    raise exception '无法读取审核事项的基础资料';
  end if;

  foreach v_field in array v_fields loop
    with field_values as (
      select
        public.jury_payload_field_value(
          public.jury_pending_payload(pending.id),
          v_field
        ) as value,
        public.jury_field_value_is_missing(
          public.jury_pending_payload(pending.id),
          v_field
        ) as is_missing
      from public.pending_clothes as pending
      where pending.id = any(coalesce(p_pending_ids, '{}'::bigint[]))

      union all

      select
        public.jury_payload_field_value(v_base, v_field),
        public.jury_field_value_is_missing(v_base, v_field)
      where p_clothes_id is not null
    ), distinct_values as (
      select distinct value
      from field_values
    )
    select
      coalesce(pg_catalog.jsonb_agg(value order by value::text), '[]'::jsonb),
      pg_catalog.count(*)::integer,
      coalesce((select pg_catalog.bool_or(is_missing) from field_values), false)
      into v_values, v_distinct_count, v_has_null
    from distinct_values;

    if v_distinct_count > 1 or (v_has_null and v_field <> 'tags') then
      v_issues := v_issues || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'field', v_field,
          'kind', case when v_has_null then 'missing' else 'conflict' end
        )
      );
      v_options := v_options || pg_catalog.jsonb_build_object(v_field, v_values);
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'base_record', v_base,
    'base_version', pg_catalog.md5(v_base::text),
    'issues', v_issues,
    'field_options', v_options
  );
end;
$$;

revoke all on function public.jury_record_payload(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) from public, anon, authenticated, service_role;
revoke all on function public.jury_pending_payload(bigint)
  from public, anon, authenticated, service_role;
revoke all on function public.jury_clothes_payload(text)
  from public, anon, authenticated, service_role;
revoke all on function public.jury_payload_field_value(jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.jury_field_value_is_missing(jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.build_jury_review_payload(bigint[], text)
  from public, anon, authenticated, service_role;

grant execute on function public.jury_record_payload(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) to service_role;
grant execute on function public.jury_pending_payload(bigint) to service_role;
grant execute on function public.jury_clothes_payload(text) to service_role;
grant execute on function public.jury_payload_field_value(jsonb, text) to service_role;
grant execute on function public.jury_field_value_is_missing(jsonb, text) to service_role;
grant execute on function public.build_jury_review_payload(bigint[], text) to service_role;

create or replace function public.ensure_full_jury_review_item(
  p_pending_id bigint,
  p_clothes_id text default null,
  p_require_five_sources boolean default true
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_pending public.pending_clothes%rowtype;
  v_identity_key text;
  v_item_id uuid;
  v_source_ids bigint[] := '{}'::bigint[];
  v_source_user_count integer := 0;
  v_primary_pending_id bigint;
  v_primary_user_id uuid;
  v_payload jsonb;
  v_reason text;
begin
  select pending.*
    into v_pending
  from public.pending_clothes as pending
  where pending.id = p_pending_id
  for update;

  if not found then
    raise exception '审核来源不存在';
  end if;

  if p_clothes_id is not null then
    v_identity_key := 'clothes|' || p_clothes_id;
  elsif exists (
    select 1
    from public.pending_clothes as same_name
    where same_name.status = 'pending'
      and same_name.name is not distinct from v_pending.name
      and same_name.category is not distinct from v_pending.category
      and pg_catalog.btrim(coalesce(same_name.game_id, ''))
        is distinct from pg_catalog.btrim(coalesce(v_pending.game_id, ''))
  ) then
    v_identity_key := 'entry|name|'
      || coalesce(v_pending.category, '') || '|'
      || pg_catalog.lower(pg_catalog.btrim(coalesce(v_pending.name, '')));
  else
    v_identity_key := 'entry|game|'
      || coalesce(v_pending.category, '') || '|'
      || pg_catalog.btrim(coalesce(v_pending.game_id, ''));
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db7-review|' || v_identity_key, 0)
  );

  select item.id
    into v_item_id
  from public.re_review_items as item
  where item.identity_key = v_identity_key
    and item.status in ('pending', 'voting', 'failed')
  order by item.created_at, item.id
  limit 1
  for update;

  select
    coalesce(pg_catalog.array_agg(source.id order by source.created_at, source.id), '{}'::bigint[]),
    pg_catalog.count(distinct source.submitted_by) filter (where source.submitted_by is not null)::integer
    into v_source_ids, v_source_user_count
  from public.pending_clothes as source
  where source.status = 'pending'
    and (
      (
        source.category is not distinct from v_pending.category
        and pg_catalog.btrim(coalesce(source.game_id, ''))
          = pg_catalog.btrim(coalesce(v_pending.game_id, ''))
      )
      or
      (
        source.name is not distinct from v_pending.name
        and source.category is not distinct from v_pending.category
      )
    );

  if v_item_id is null
    and coalesce(p_require_five_sources, true)
    and v_source_user_count < 5 then
    return null;
  end if;

  if pg_catalog.cardinality(v_source_ids) = 0 then
    raise exception '审核来源集合为空';
  end if;

  v_payload := public.build_jury_review_payload(v_source_ids, p_clothes_id);

  if pg_catalog.jsonb_array_length(coalesce(v_payload->'issues', '[]'::jsonb)) = 0 then
    return null;
  end if;

  v_reason := case
    when p_clothes_id is not null then 'correction'
    when exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_payload->'issues') as issue(value)
      where issue.value->>'kind' = 'missing'
    ) then 'field_missing'
    else 'field_conflict'
  end;

  select source.id, source.submitted_by
    into v_primary_pending_id, v_primary_user_id
  from public.pending_clothes as source
  where source.id = any(v_source_ids)
  order by source.created_at, source.id
  limit 1;

  if v_item_id is null then
    insert into public.re_review_items (
      reason,
      status,
      source_pending_id,
      clothes_id,
      payload,
      submitted_by,
      identity_key
    )
    values (
      v_reason,
      'pending',
      v_primary_pending_id,
      p_clothes_id,
      v_payload,
      v_primary_user_id,
      v_identity_key
    )
    returning id into v_item_id;
  else
    update public.re_review_items
    set
      payload = case when status in ('pending', 'failed') then v_payload else payload end,
      updated_at = pg_catalog.now()
    where id = v_item_id;
  end if;

  insert into public.re_review_item_sources (
    re_review_item_id,
    source_pending_id,
    source_user_id
  )
  select
    v_item_id,
    source.id,
    source.submitted_by
  from public.pending_clothes as source
  where source.id = any(v_source_ids)
  on conflict (re_review_item_id, source_pending_id) do nothing;

  return v_item_id;
end;
$$;

revoke all on function public.ensure_full_jury_review_item(bigint, text, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.ensure_full_jury_review_item(bigint, text, boolean)
  to service_role;

alter function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) rename to submit_clothing_contribution_db7_core;

revoke all on function public.submit_clothing_contribution_db7_core(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.submit_clothing_contribution_db7_core(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) to service_role;

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
  v_temp_suit_name text := nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '');
  v_tags text := nullif(pg_catalog.btrim(coalesce(p_tags, '')), '');
  v_needs_suit_review boolean := coalesce(p_needs_suit_review, false);
  v_input_payload jsonb;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_pending_id bigint;
  v_existing_item_id uuid;
  v_re_review_item_id uuid;
  v_existing_user_in_cohort boolean := false;
  v_distinct_user_count integer := 0;
  v_distinct_payload_count integer := 0;
  v_route_to_review boolean := false;
  v_result jsonb;
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
  if p_scores is null or pg_catalog.jsonb_typeof(p_scores) <> 'object' then
    raise exception '属性分值不能为空';
  end if;
  if v_needs_suit_review and (p_suit_id is not null or v_temp_suit_name is not null) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_input_payload := public.jury_record_payload(
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    v_temp_suit_name,
    v_tags,
    v_needs_suit_review
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|category_game|' || p_category || '|' || v_game_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|name_category|' || p_name || '|' || p_category, 0)
  );

  select pending.id
    into v_pending_id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.submitted_by = v_user_id
    and public.jury_pending_payload(pending.id) is not distinct from v_input_payload
  order by pending.created_at, pending.id
  limit 1
  for update;

  if found then
    select item.id
      into v_existing_item_id
    from public.re_review_item_sources as source
    join public.re_review_items as item
      on item.id = source.re_review_item_id
      and item.status in ('pending', 'voting', 'failed')
    where source.source_pending_id = v_pending_id
    order by item.created_at, item.id
    limit 1;

    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id,
      'review_required', v_existing_item_id is not null,
      're_review_item_id', v_existing_item_id
    );
  end if;

  select clothes.*
    into v_existing_clothes
  from public.clothes as clothes
  where (
      clothes.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id
    )
    or (
      clothes.name is not distinct from p_name
      and clothes.category is not distinct from p_category
    )
  order by
    case
      when clothes.category is not distinct from p_category
        and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id then 0
      else 1
    end,
    clothes.id
  limit 1
  for update;

  v_clothes_exists := found;

  if v_clothes_exists
    and (
      public.jury_clothes_payload(v_existing_clothes.id)
      || pg_catalog.jsonb_build_object('needs_suit_review', v_needs_suit_review)
    ) is distinct from v_input_payload then
    v_route_to_review := true;
  end if;

  select item.id
    into v_existing_item_id
  from public.re_review_items as item
  where item.status in ('pending', 'voting', 'failed')
    and (
      (v_clothes_exists and item.identity_key = 'clothes|' || v_existing_clothes.id)
      or item.identity_key = 'entry|game|' || p_category || '|' || v_game_id
      or item.identity_key = 'entry|name|' || p_category || '|'
        || pg_catalog.lower(pg_catalog.btrim(p_name))
    )
  order by item.created_at, item.id
  limit 1
  for update;

  if v_existing_item_id is not null then
    v_route_to_review := true;
  end if;

  if not v_clothes_exists and not v_route_to_review then
    with earliest_per_user as (
      select distinct on (pending.submitted_by)
        pending.submitted_by,
        public.jury_pending_payload(pending.id) as payload
      from public.pending_clothes as pending
      where pending.status = 'pending'
        and pending.submitted_by is not null
        and (
          (
            pending.category is not distinct from p_category
            and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
          )
          or (
            pending.name is not distinct from p_name
            and pending.category is not distinct from p_category
          )
        )
      order by pending.submitted_by, pending.created_at, pending.id
    ), cohort as (
      select earliest.submitted_by, earliest.payload
      from earliest_per_user as earliest

      union all

      select v_user_id, v_input_payload
      where not exists (
        select 1
        from earliest_per_user as earliest
        where earliest.submitted_by = v_user_id
      )
    )
    select
      pg_catalog.count(*)::integer,
      pg_catalog.count(distinct cohort.payload::text)::integer,
      exists (
        select 1
        from earliest_per_user as earliest
        where earliest.submitted_by = v_user_id
      )
      into v_distinct_user_count, v_distinct_payload_count, v_existing_user_in_cohort
    from cohort;

    if v_distinct_user_count >= 5 and v_distinct_payload_count > 1 then
      v_route_to_review := true;
    end if;
  end if;

  if v_route_to_review then
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
      v_temp_suit_name,
      v_tags,
      v_user_id,
      'pending',
      v_needs_suit_review
    )
    returning id into v_pending_id;

    if p_suit_id is null and v_temp_suit_name is not null then
      insert into public.pending_suits (name, submitted_by, status)
      values (v_temp_suit_name, v_user_id, 'pending');
    end if;

    v_re_review_item_id := public.ensure_full_jury_review_item(
      v_pending_id,
      case when v_clothes_exists then v_existing_clothes.id else null end,
      not v_clothes_exists
    );

    if v_re_review_item_id is null then
      raise exception '审核事项创建失败，已回滚本次提交';
    end if;

    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id,
      'review_required', true,
      're_review_item_id', v_re_review_item_id
    );
  end if;

  v_result := public.submit_clothing_contribution_db7_core(
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    v_temp_suit_name,
    v_tags,
    v_needs_suit_review
  );

  return v_result || pg_catalog.jsonb_build_object(
    'review_required', (v_result->>'re_review_item_id') is not null,
    're_review_item_id', v_result->'re_review_item_id'
  );
end;
$$;

revoke all on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) from public, anon, authenticated, service_role;
grant execute on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) to authenticated, service_role;

create or replace function public.jury_scores_are_complete(p_scores jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_left_fields constant text[] := array['simple', 'active', 'cute', 'pure', 'cool'];
  v_right_fields constant text[] := array['gorgeous', 'elegant', 'mature', 'sexy', 'warm'];
  v_index integer;
  v_left numeric;
  v_right numeric;
begin
  if p_scores is null
    or pg_catalog.jsonb_typeof(p_scores) <> 'object'
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_scores)) <> 10
    or not (p_scores ?& array[
      'simple', 'gorgeous', 'active', 'elegant', 'cute',
      'mature', 'pure', 'sexy', 'cool', 'warm'
    ]) then
    return false;
  end if;

  for v_index in 1..5 loop
    if pg_catalog.jsonb_typeof(p_scores->v_left_fields[v_index]) <> 'number'
      or pg_catalog.jsonb_typeof(p_scores->v_right_fields[v_index]) <> 'number' then
      return false;
    end if;

    v_left := (p_scores->>v_left_fields[v_index])::numeric;
    v_right := (p_scores->>v_right_fields[v_index])::numeric;
    if not (
      (v_left > 0 and v_right = 0)
      or (v_right > 0 and v_left = 0)
    ) then
      return false;
    end if;
  end loop;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

revoke all on function public.jury_scores_are_complete(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.jury_scores_are_complete(jsonb) to service_role;

create or replace function public.jury_payload_is_complete(p_payload jsonb)
returns boolean
language plpgsql
immutable
set search_path = ''
as $$
declare
  v_stars numeric;
begin
  if p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) <> 9
    or not (p_payload ?& array[
      'name', 'game_id', 'category', 'stars', 'scores',
      'suit_id', 'temp_suit_name', 'tags', 'needs_suit_review'
    ])
    or pg_catalog.jsonb_typeof(p_payload->'name') <> 'string'
    or nullif(pg_catalog.btrim(p_payload->>'name'), '') is null
    or pg_catalog.jsonb_typeof(p_payload->'game_id') <> 'string'
    or pg_catalog.btrim(p_payload->>'game_id') !~ '^[0-9]+$'
    or pg_catalog.jsonb_typeof(p_payload->'category') <> 'string'
    or nullif(pg_catalog.btrim(p_payload->>'category'), '') is null
    or pg_catalog.jsonb_typeof(p_payload->'stars') <> 'number'
    or not public.jury_scores_are_complete(p_payload->'scores')
    or pg_catalog.jsonb_typeof(p_payload->'needs_suit_review') <> 'boolean'
    or (p_payload->>'needs_suit_review')::boolean
    or p_payload->'temp_suit_name' <> 'null'::jsonb
    or not (
      p_payload->'tags' = 'null'::jsonb
      or pg_catalog.jsonb_typeof(p_payload->'tags') = 'string'
    )
    or not (
      p_payload->'suit_id' = 'null'::jsonb
      or pg_catalog.jsonb_typeof(p_payload->'suit_id') = 'string'
    ) then
    return false;
  end if;

  v_stars := (p_payload->>'stars')::numeric;
  return v_stars = pg_catalog.trunc(v_stars) and v_stars between 1 and 6;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

revoke all on function public.jury_payload_is_complete(jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.jury_payload_is_complete(jsonb) to service_role;

create or replace function public.submit_jury_candidate(
  p_re_review_item_id uuid,
  p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_item public.re_review_items%rowtype;
  v_candidate public.re_review_candidates%rowtype;
  v_base_payload jsonb;
  v_issues jsonb;
  v_candidate_payload jsonb;
  v_field text;
  v_suit_id uuid;
  v_is_legacy_missing_suit boolean := false;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交补充内容';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = p_re_review_item_id
  for update;

  if not found then
    raise exception '审核事项不存在';
  end if;

  if v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能处理自己提交或参与过的数据';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = v_item.id
    and candidate.status = 'voting'
  order by candidate.created_at desc, candidate.id
  limit 1
  for update;

  if found then
    if v_candidate.submitted_by is not distinct from v_user_id
      and (
        v_candidate.payload is not distinct from p_payload
        or (
          v_item.reason = 'missing_suit'
          and pg_catalog.jsonb_typeof(p_payload) = 'object'
          and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) = 1
          and p_payload ? 'suit_id'
          and v_candidate.payload->'suit_id' is not distinct from p_payload->'suit_id'
        )
      ) then
      return pg_catalog.jsonb_build_object(
        're_review_item_id', v_item.id,
        'candidate_id', v_candidate.id,
        'candidate_status', v_candidate.status,
        'item_status', v_item.status,
        'idempotent', true
      );
    end if;
    raise exception '该事项已经有待审核内容';
  end if;

  if v_item.status not in ('pending', 'failed') then
    raise exception '当前事项不能提交新的补充内容';
  end if;

  if v_item.payload ? 'base_record' then
    v_base_payload := v_item.payload->'base_record';
    v_issues := coalesce(v_item.payload->'issues', '[]'::jsonb);
  else
    v_base_payload := public.jury_clothes_payload(v_item.clothes_id);
    v_issues := case
      when v_item.reason = 'missing_suit' then
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
        )
      else '[]'::jsonb
    end;
  end if;

  if v_base_payload is null or pg_catalog.jsonb_array_length(v_issues) = 0 then
    raise exception '该事项没有可补充或需要核对的字段';
  end if;

  v_is_legacy_missing_suit := v_item.reason = 'missing_suit'
    and pg_catalog.jsonb_typeof(p_payload) = 'object'
    and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) = 1
    and p_payload ? 'suit_id';

  v_candidate_payload := case
    when v_is_legacy_missing_suit
      then v_base_payload || p_payload || pg_catalog.jsonb_build_object(
        'temp_suit_name', null,
        'needs_suit_review', false
      )
    else p_payload
  end;

  if not v_is_legacy_missing_suit
    and not public.jury_payload_is_complete(v_candidate_payload) then
    raise exception '请补充完整的服装资料后再提交';
  end if;

  if v_candidate_payload->'suit_id' <> 'null'::jsonb then
    begin
      v_suit_id := (v_candidate_payload->>'suit_id')::uuid;
    exception when invalid_text_representation then
      raise exception '所属套装格式无效';
    end;

    if not exists (select 1 from public.suits as suit where suit.id = v_suit_id) then
      raise exception '所选套装不存在，请刷新后重试';
    end if;
  end if;

  foreach v_field in array array[
    'name', 'game_id', 'category', 'stars',
    'pair1', 'pair2', 'pair3', 'pair4', 'pair5',
    'suit', 'tags'
  ] loop
    if not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_issues) as issue(value)
      where issue.value->>'field' = v_field
    ) and public.jury_payload_field_value(v_candidate_payload, v_field)
      is distinct from public.jury_payload_field_value(v_base_payload, v_field) then
      raise exception '只能修改页面列出的缺失或冲突字段';
    end if;
  end loop;

  insert into public.re_review_candidates (
    re_review_item_id,
    payload,
    submitted_by,
    status
  )
  values (
    v_item.id,
    case when v_is_legacy_missing_suit then p_payload else v_candidate_payload end,
    v_user_id,
    'voting'
  )
  returning * into v_candidate;

  update public.re_review_items
  set
    status = 'voting',
    updated_at = pg_catalog.now(),
    resolved_by = null,
    resolved_at = null
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    're_review_item_id', v_item.id,
    'candidate_id', v_candidate.id,
    'candidate_status', v_candidate.status,
    'item_status', 'voting',
    'idempotent', false
  );
end;
$$;

create or replace function public.get_jury_review_queue()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_is_super_admin boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  v_is_super_admin := public.is_super_admin();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        're_review_item_id', item.id,
        'reason', item.reason,
        'item_status', item.status,
        'clothes_id', item.clothes_id,
        'clothes_name', coalesce(base.payload->>'name', '未命名服装'),
        'category', coalesce(base.payload->>'category', ''),
        'game_id', coalesce(base.payload->>'game_id', ''),
        'base_payload', base.payload,
        'base_suit_name', (
          select suit.name
          from public.suits as suit
          where suit.id::text = base.payload->>'suit_id'
        ),
        'issues', issue_data.issues,
        'field_options', issue_data.field_options,
        'candidate_id', candidate.id,
        'candidate_payload', case
          when candidate.id is null then null
          when (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(candidate.payload)) = 1
            and candidate.payload ? 'suit_id'
            then base.payload || candidate.payload || pg_catalog.jsonb_build_object(
              'temp_suit_name', null,
              'needs_suit_review', false
            )
          else candidate.payload
        end,
        'candidate_status', candidate.status,
        'candidate_suit_name', (
          select suit.name
          from public.suits as suit
          where suit.id::text = candidate.payload->>'suit_id'
        ),
        'candidate_created_at', candidate.created_at,
        'approve_count', coalesce(vote_count.approve_count, 0),
        'reject_count', coalesce(vote_count.reject_count, 0),
        'my_vote', my_vote.vote,
        'can_submit_candidate', candidate.id is null and item.status in ('pending', 'failed'),
        'can_vote', candidate.id is not null
          and item.status = 'voting'
          and candidate.submitted_by is distinct from v_user_id
          and my_vote.vote is null,
        'is_candidate_author', candidate.submitted_by is not distinct from v_user_id,
        'can_admin_reject', v_is_super_admin
          and candidate.id is not null
          and candidate.submitted_by is distinct from v_user_id
          and my_vote.vote is null
      )
      order by item.created_at, item.id
    ),
    '[]'::jsonb
  )
    into v_result
  from public.re_review_items as item
  left join lateral (
    select coalesce(
      case
        when item.payload ? 'base_record' then item.payload->'base_record'
        else public.jury_clothes_payload(item.clothes_id)
      end,
      '{}'::jsonb
    ) as payload
  ) as base on true
  left join lateral (
    select
      case
        when item.payload ? 'issues' then item.payload->'issues'
        when item.reason = 'missing_suit' then pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
        )
        else '[]'::jsonb
      end as issues,
      coalesce(item.payload->'field_options', '{}'::jsonb) as field_options
  ) as issue_data on true
  left join lateral (
    select current_candidate.*
    from public.re_review_candidates as current_candidate
    where current_candidate.re_review_item_id = item.id
      and current_candidate.status = 'voting'
    order by current_candidate.created_at desc, current_candidate.id
    limit 1
  ) as candidate on true
  left join lateral (
    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer as approve_count,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer as reject_count
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
  ) as vote_count on true
  left join lateral (
    select vote.vote
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
      and vote.user_id = v_user_id
    limit 1
  ) as my_vote on true
  where item.reason in ('missing_suit', 'field_conflict', 'field_missing', 'correction')
    and item.status in ('pending', 'voting', 'failed')
    and item.submitted_by is distinct from v_user_id
    and not exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    and not exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = item.id
        and source.source_user_id = v_user_id
    );

  return v_result;
end;
$$;

create or replace function public.apply_approved_jury_candidate(
  p_re_review_item_id uuid,
  p_candidate_id uuid,
  p_resolved_by uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_item public.re_review_items%rowtype;
  v_candidate public.re_review_candidates%rowtype;
  v_base_payload jsonb;
  v_final_payload jsonb;
  v_clothes_id text;
  v_suit_id uuid;
  v_contribution_id uuid;
  v_contributor_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_user_ids uuid[] := '{}'::uuid[];
  v_source_ids bigint[] := '{}'::bigint[];
  v_source_created_ats timestamptz[] := '{}'::timestamptz[];
  v_index integer;
  v_is_legacy_missing_suit boolean := false;
begin
  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = p_re_review_item_id
  for update;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
    and candidate.re_review_item_id = p_re_review_item_id
  for update;

  if v_item.id is null or v_candidate.id is null then
    raise exception '待审核内容或审核事项不存在';
  end if;

  v_base_payload := case
    when v_item.payload ? 'base_record' then v_item.payload->'base_record'
    else public.jury_clothes_payload(v_item.clothes_id)
  end;

  v_is_legacy_missing_suit := v_item.reason = 'missing_suit'
    and pg_catalog.jsonb_typeof(v_candidate.payload) = 'object'
    and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_candidate.payload)) = 1
    and v_candidate.payload ? 'suit_id';

  v_final_payload := case
    when v_is_legacy_missing_suit
      then v_base_payload || v_candidate.payload || pg_catalog.jsonb_build_object(
        'temp_suit_name', null,
        'needs_suit_review', false
      )
    else v_candidate.payload
  end;

  if not v_is_legacy_missing_suit
    and not public.jury_payload_is_complete(v_final_payload) then
    raise exception '待审核内容不是完整服装资料';
  end if;

  if v_final_payload->'suit_id' <> 'null'::jsonb then
    begin
      v_suit_id := (v_final_payload->>'suit_id')::uuid;
    exception when invalid_text_representation then
      raise exception '所属套装格式无效';
    end;

    if not exists (select 1 from public.suits as suit where suit.id = v_suit_id) then
      raise exception '所选套装不存在';
    end if;
  end if;

  if v_item.clothes_id is not null then
    if public.jury_clothes_payload(v_item.clothes_id) is distinct from v_base_payload then
      raise exception '正式服装已变化，不能按旧的审核内容修改';
    end if;

    update public.clothes
    set
      name = v_final_payload->>'name',
      game_id = v_final_payload->>'game_id',
      category = v_final_payload->>'category',
      stars = v_final_payload->>'stars',
      scores = v_final_payload->'scores',
      suit_id = v_suit_id,
      temp_suit_name = null,
      tags = nullif(pg_catalog.btrim(coalesce(v_final_payload->>'tags', '')), '')
    where id = v_item.clothes_id;

    if not found then
      raise exception '正式服装不存在，已回滚本次投票';
    end if;

    v_clothes_id := v_item.clothes_id;
  else
    v_clothes_id := 'custom_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');

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
      v_final_payload->>'name',
      v_final_payload->>'game_id',
      v_final_payload->>'category',
      v_final_payload->>'stars',
      v_final_payload->'scores',
      v_suit_id,
      null,
      nullif(pg_catalog.btrim(coalesce(v_final_payload->>'tags', '')), '')
    );

    with earliest_matching_per_user as (
      select distinct on (source.source_user_id)
        source.source_user_id as user_id,
        source.source_pending_id,
        pending.created_at as source_created_at
      from public.re_review_item_sources as source
      join public.pending_clothes as pending
        on pending.id = source.source_pending_id
      where source.re_review_item_id = v_item.id
        and source.source_user_id is not null
        and public.jury_pending_payload(source.source_pending_id)
          is not distinct from v_final_payload
      order by source.source_user_id, pending.created_at, source.source_pending_id
    ), effective_sources as (
      select matching.*
      from earliest_matching_per_user as matching
      order by matching.source_created_at, matching.source_pending_id, matching.user_id
      limit 5
    )
    select
      coalesce(pg_catalog.array_agg(source.user_id order by source.source_created_at, source.source_pending_id), '{}'::uuid[]),
      coalesce(pg_catalog.array_agg(source.source_pending_id order by source.source_created_at, source.source_pending_id), '{}'::bigint[]),
      coalesce(pg_catalog.array_agg(source.source_created_at order by source.source_created_at, source.source_pending_id), '{}'::timestamptz[])
      into v_user_ids, v_source_ids, v_source_created_ats
    from effective_sources as source;

    v_contributor_count := pg_catalog.cardinality(v_user_ids);

    for v_index in 1..v_contributor_count loop
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
        v_candidate.id,
        v_clothes_id,
        v_user_ids[v_index],
        v_source_ids[v_index],
        'jury_resolution',
        v_index::smallint,
        v_source_created_ats[v_index]
      )
      returning id into v_contribution_id;

      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        source_id,
        re_review_candidate_id,
        jury_vote_id,
        reversal_of
      )
      values (
        v_user_ids[v_index],
        10,
        'awarded',
        'clothing_contribution',
        v_contribution_id,
        null,
        null,
        null
      );

      v_points_count := v_points_count + 1;
    end loop;

    if v_contributor_count > 0 then
      v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
        v_user_ids,
        v_clothes_id
      );
    end if;

    if v_points_count <> v_contributor_count
      or v_wardrobe_count <> v_contributor_count then
      raise exception '原始贡献、积分或衣柜写回数量异常，已回滚本次通过';
    end if;

    update public.pending_clothes as pending
    set status = case
      when public.jury_pending_payload(pending.id) is not distinct from v_final_payload
        then 'approved'
      else 'rejected'
    end
    from public.re_review_item_sources as source
    where source.re_review_item_id = v_item.id
      and source.source_pending_id = pending.id
      and pending.status = 'pending';
  end if;

  insert into public.points_ledger (
    user_id,
    delta,
    status,
    source_type,
    source_id,
    re_review_candidate_id,
    jury_vote_id,
    reversal_of
  )
  values (
    v_candidate.submitted_by,
    8,
    'awarded',
    're_review_candidate',
    null,
    v_candidate.id,
    null,
    null
  )
  on conflict (re_review_candidate_id)
    where re_review_candidate_id is not null do nothing;

  update public.re_review_candidates
  set
    status = 'approved',
    resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set
    status = 'approved',
    resolved_by = p_resolved_by,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    'clothes_id', v_clothes_id,
    'source_contributor_count', v_contributor_count,
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$$;

revoke all on function public.apply_approved_jury_candidate(uuid, uuid, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.apply_approved_jury_candidate(uuid, uuid, uuid)
  to service_role;

create or replace function public.cast_jury_vote(
  p_candidate_id uuid,
  p_vote text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_vote_id uuid;
  v_existing_vote text;
  v_approve_count integer := 0;
  v_reject_count integer := 0;
  v_result_status text := 'voting';
  v_points_awarded integer := 0;
  v_apply_result jsonb := '{}'::jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能参与陪审团投票';
  end if;

  if p_vote is null or p_vote not in ('approve', 'reject') then
    raise exception '投票只允许 approve 或 reject';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found then
    raise exception '待审核内容不存在';
  end if;

  select vote.id, vote.vote
    into v_vote_id, v_existing_vote
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id
    and vote.user_id = v_user_id;

  if found and v_existing_vote is distinct from p_vote then
    raise exception '投票提交后不能修改';
  end if;

  if v_candidate.status <> 'voting' then
    if v_vote_id is null then
      raise exception '该内容当前不可投票';
    end if;

    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
      into v_approve_count, v_reject_count
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id;

    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_candidate.re_review_item_id,
      'approve_count', v_approve_count,
      'reject_count', v_reject_count,
      'my_vote', v_existing_vote,
      'points_awarded', 0,
      'status', v_candidate.status
    );
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status <> 'voting' then
    raise exception '审核事项当前不在投票状态';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能投票审核自己提交或参与过的数据';
  end if;

  if v_vote_id is null then
    insert into public.jury_votes (candidate_id, user_id, vote)
    values (v_candidate.id, v_user_id, p_vote)
    returning id into v_vote_id;

    insert into public.points_ledger (
      user_id,
      delta,
      status,
      source_type,
      source_id,
      re_review_candidate_id,
      jury_vote_id,
      reversal_of
    )
    values (
      v_user_id,
      1,
      'awarded',
      'jury_vote',
      null,
      null,
      v_vote_id,
      null
    )
    on conflict (jury_vote_id) where jury_vote_id is not null do nothing;

    get diagnostics v_points_awarded = row_count;
    v_existing_vote := p_vote;
  end if;

  select
    pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
    pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
    into v_approve_count, v_reject_count
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id;

  if v_approve_count >= 5 and v_approve_count > v_reject_count then
    v_apply_result := public.apply_approved_jury_candidate(
      v_item.id,
      v_candidate.id,
      v_user_id
    );
    v_result_status := 'approved';
  elsif v_reject_count - v_approve_count >= 3 then
    update public.re_review_candidates
    set
      status = 'returned',
      resolved_at = pg_catalog.now()
    where id = v_candidate.id;

    update public.re_review_items
    set
      status = 'pending',
      resolved_by = null,
      resolved_at = null,
      updated_at = pg_catalog.now()
    where id = v_item.id;

    v_result_status := 'returned';
  end if;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'approve_count', v_approve_count,
    'reject_count', v_reject_count,
    'my_vote', v_existing_vote,
    'points_awarded', case when v_points_awarded > 0 then 1 else 0 end,
    'status', v_result_status
  ) || v_apply_result;
end;
$$;

create or replace function public.admin_reject_jury_candidate(
  p_candidate_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_existing_decision public.jury_admin_decisions%rowtype;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
begin
  if v_user_id is null then
    raise exception '需要登录后才能执行管理员终审';
  end if;

  if not public.is_super_admin() then
    raise exception '只有超级管理员可以执行永久驳回终审';
  end if;

  if v_reason is null then
    raise exception '永久驳回必须填写终审理由';
  end if;

  select decision.*
    into v_existing_decision
  from public.jury_admin_decisions as decision
  where decision.candidate_id = p_candidate_id;

  if found then
    if v_existing_decision.admin_user_id is not distinct from v_user_id
      and v_existing_decision.reason is not distinct from v_reason then
      return pg_catalog.jsonb_build_object(
        'candidate_id', v_existing_decision.candidate_id,
        're_review_item_id', v_existing_decision.re_review_item_id,
        'status', 'rejected',
        'idempotent', true
      );
    end if;
    raise exception '该内容已经完成管理员终审';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found or v_candidate.status not in ('voting', 'returned') then
    raise exception '待审核内容不存在或当前不能终审驳回';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status not in ('pending', 'voting', 'failed') then
    raise exception '审核事项当前不能终审驳回';
  end if;

  if (v_candidate.status = 'voting' and v_item.status <> 'voting')
    or (v_candidate.status = 'returned' and v_item.status not in ('pending', 'failed'))
    or exists (
      select 1
      from public.re_review_candidates as active_candidate
      where active_candidate.re_review_item_id = v_item.id
        and active_candidate.status = 'voting'
        and active_candidate.id <> v_candidate.id
    ) then
    raise exception '该内容已不是当前可终审轮次';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '管理员不能终审自己提交或参与过的数据';
  end if;

  if exists (
    select 1
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id
      and vote.user_id = v_user_id
  ) then
    raise exception using
      errcode = '42501',
      message = '已经参与普通投票，不能再执行终审';
  end if;

  insert into public.jury_admin_decisions (
    candidate_id,
    re_review_item_id,
    admin_user_id,
    decision,
    reason
  )
  values (
    v_candidate.id,
    v_item.id,
    v_user_id,
    'rejected',
    v_reason
  );

  update public.re_review_candidates
  set
    status = 'rejected',
    resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set
    status = 'rejected',
    resolved_by = v_user_id,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'status', 'rejected',
    'idempotent', false
  );
end;
$$;

revoke all on function public.submit_jury_candidate(uuid, jsonb)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_jury_candidate(uuid, jsonb)
  to authenticated, service_role;

revoke all on function public.get_jury_review_queue()
  from public, anon, authenticated, service_role;
grant execute on function public.get_jury_review_queue()
  to authenticated, service_role;

revoke all on function public.cast_jury_vote(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.cast_jury_vote(uuid, text)
  to authenticated, service_role;

revoke all on function public.admin_reject_jury_candidate(uuid, text)
  from public, anon, authenticated, service_role;
grant execute on function public.admin_reject_jury_candidate(uuid, text)
  to authenticated, service_role;

comment on column public.re_review_items.identity_key is
  '同一服装同时只允许一个开放审核事项的稳定身份键。';

comment on column public.points_ledger.jury_vote_id is
  '陪审员首次有效投票的唯一 +1 积分来源。';

comment on function public.submit_clothing_contribution(
  text, text, text, integer, jsonb, uuid, text, text, boolean
) is 'DB-7 补丁：五位不同用户仍不一致或与正式资料冲突时，原子转入整件全字段审核；兼容原参数与返回字段。';

comment on function public.submit_jury_candidate(uuid, jsonb) is
  'DB-7 补丁：提交完整服装资料，只允许修改审核事项列出的缺失或冲突字段；相同重试幂等。';

comment on function public.get_jury_review_queue() is
  'DB-7 补丁：返回全部开放审核类型、完整基础资料、字段问题、投票与终审权限。';

comment on function public.cast_jury_vote(uuid, text) is
  'DB-7 补丁：不可改票；首次有效投票即时 +1，达到门槛后原子应用完整审核结果。';

comment on function public.admin_reject_jury_candidate(uuid, text) is
  'DB-7 补丁：超级管理员独立终审；参投管理员不可终审，相同终审重试幂等。';

commit;
