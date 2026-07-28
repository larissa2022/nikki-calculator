begin;

alter table public.correction_requests
  add column accepted_patch jsonb,
  add column source_pending_id bigint,
  add column re_review_item_id uuid;

alter table public.correction_requests
  add constraint correction_requests_source_pending_id_fkey
    foreign key (source_pending_id)
    references public.pending_clothes (id)
    on delete restrict,
  add constraint correction_requests_re_review_item_id_fkey
    foreign key (re_review_item_id)
    references public.re_review_items (id)
    on delete restrict,
  add constraint correction_requests_accepted_patch_check
    check (
      accepted_patch is null
      or (
        pg_catalog.jsonb_typeof(accepted_patch) = 'object'
        and accepted_patch ? field_key
        and accepted_patch = pg_catalog.jsonb_build_object(
          field_key,
          accepted_patch->field_key
        )
      )
    ),
  add constraint correction_requests_review_link_check
    check (
      (source_pending_id is null and re_review_item_id is null)
      or (source_pending_id is not null and re_review_item_id is not null)
    ),
  add constraint correction_requests_resolution_shape_check
    check (
      (
        status = 'pending'
        and accepted_patch is null
        and source_pending_id is null
        and re_review_item_id is null
      )
      or (
        status = 'converted_to_re_review'
        and accepted_patch is not null
        and source_pending_id is not null
        and re_review_item_id is not null
      )
      or (
        status = 'approved'
        and accepted_patch is not null
      )
      or status in ('reviewing', 'rejected')
    );

create index correction_requests_source_pending_id_idx
  on public.correction_requests (source_pending_id)
  where source_pending_id is not null;

create index correction_requests_re_review_item_id_idx
  on public.correction_requests (re_review_item_id)
  where re_review_item_id is not null;

alter table public.points_ledger
  add column correction_request_id uuid;

alter table public.points_ledger
  add constraint points_ledger_correction_request_id_fkey
    foreign key (correction_request_id)
    references public.correction_requests (id)
    on delete restrict;

alter table public.points_ledger
  drop constraint points_ledger_source_type_check,
  drop constraint points_ledger_entry_shape_check;

alter table public.points_ledger
  add constraint points_ledger_source_type_check
    check (
      source_type in (
        'clothing_contribution',
        're_review_candidate',
        'jury_vote',
        'correction_request',
        'reversal'
      )
    ),
  add constraint points_ledger_entry_shape_check
    check (
      (
        source_type = 'clothing_contribution'
        and source_id is not null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is null
        and reversal_of is null
        and delta > 0
      )
      or (
        source_type = 're_review_candidate'
        and source_id is null
        and re_review_candidate_id is not null
        and jury_vote_id is null
        and correction_request_id is null
        and reversal_of is null
        and delta > 0
      )
      or (
        source_type = 'jury_vote'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is not null
        and correction_request_id is null
        and reversal_of is null
        and delta = 1
      )
      or (
        source_type = 'correction_request'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is not null
        and reversal_of is null
        and delta = 5
      )
      or (
        source_type = 'reversal'
        and source_id is null
        and re_review_candidate_id is null
        and jury_vote_id is null
        and correction_request_id is null
        and reversal_of is not null
        and delta < 0
      )
    );

create unique index points_ledger_correction_request_id_key
  on public.points_ledger (correction_request_id)
  where correction_request_id is not null;

create or replace function public.correction_field_value(
  p_payload jsonb,
  p_field text
)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select case p_field
    when 'scores' then coalesce(p_payload->'scores', 'null'::jsonb)
    when 'suit' then pg_catalog.jsonb_build_object(
      'suit_id', coalesce(p_payload->'suit_id', 'null'::jsonb),
      'temp_suit_name', coalesce(p_payload->'temp_suit_name', 'null'::jsonb),
      'needs_suit_review', coalesce(p_payload->'needs_suit_review', 'false'::jsonb)
    )
    when 'other' then 'null'::jsonb
    else coalesce(p_payload->p_field, 'null'::jsonb)
  end;
$$;

create or replace function public.correction_accepted_value_is_valid(
  p_field text,
  p_value jsonb
)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_text text;
  v_number numeric;
  v_suit_id uuid;
begin
  if p_value is null then
    return false;
  end if;

  case
    when p_field in ('name', 'category') then
      return pg_catalog.jsonb_typeof(p_value) = 'string'
        and nullif(pg_catalog.btrim(p_value #>> '{}'), '') is not null
        and pg_catalog.char_length(pg_catalog.btrim(p_value #>> '{}')) <= 200;
    when p_field = 'game_id' then
      return pg_catalog.jsonb_typeof(p_value) = 'string'
        and pg_catalog.btrim(p_value #>> '{}') ~ '^[0-9]+$'
        and pg_catalog.char_length(pg_catalog.btrim(p_value #>> '{}')) <= 30;
    when p_field = 'stars' then
      if pg_catalog.jsonb_typeof(p_value) <> 'number' then
        return false;
      end if;
      v_number := (p_value #>> '{}')::numeric;
      return v_number = pg_catalog.trunc(v_number) and v_number between 1 and 6;
    when p_field = 'scores' then
      return public.jury_scores_are_complete(p_value);
    when p_field = 'suit' then
      if pg_catalog.jsonb_typeof(p_value) <> 'object'
        or not (p_value ?& array['suit_id', 'temp_suit_name', 'needs_suit_review'])
        or (p_value - array['suit_id', 'temp_suit_name', 'needs_suit_review']) <> '{}'::jsonb
        or p_value->'temp_suit_name' <> 'null'::jsonb
        or p_value->'needs_suit_review' <> 'false'::jsonb
        or not (
          p_value->'suit_id' = 'null'::jsonb
          or pg_catalog.jsonb_typeof(p_value->'suit_id') = 'string'
        ) then
        return false;
      end if;

      if p_value->'suit_id' = 'null'::jsonb then
        return true;
      end if;

      v_suit_id := (p_value->>'suit_id')::uuid;
      return exists (
        select 1 from public.suits as suit where suit.id = v_suit_id
      );
    when p_field = 'tags' then
      if p_value = 'null'::jsonb then
        return true;
      end if;
      v_text := pg_catalog.btrim(p_value #>> '{}');
      return pg_catalog.jsonb_typeof(p_value) = 'string'
        and pg_catalog.char_length(v_text) <= 500;
    else
      return false;
  end case;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

create or replace function public.correction_field_is_directly_completable(
  p_payload jsonb,
  p_field text
)
returns boolean
language sql
stable
set search_path = ''
as $$
  select case
    when p_field in ('name', 'game_id', 'category', 'stars', 'tags') then
      public.correction_field_value(p_payload, p_field) = 'null'::jsonb
      or nullif(
        pg_catalog.btrim(public.correction_field_value(p_payload, p_field) #>> '{}'),
        ''
      ) is null
    when p_field = 'scores' then not public.jury_scores_are_complete(p_payload->'scores')
    when p_field = 'suit' then public.jury_field_value_is_missing(p_payload, 'suit')
    else false
  end;
$$;

create or replace function public.get_correction_review_queue()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null or not (select public.is_admin_or_super_admin()) then
    raise exception using
      errcode = '42501',
      message = '当前账号没有处理图鉴报错的权限';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'clothes_id', request.clothes_id,
        'clothes_name', clothes.name,
        'game_id', clothes.game_id,
        'category', clothes.category,
        'field_key', request.field_key,
        'reason', request.reason,
        'proposed_patch', request.proposed_patch,
        'base_payload', base.payload,
        'current_value', public.correction_field_value(base.payload, request.field_key),
        'reporter_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), '已注销用户'),
        'created_at', request.created_at,
        'is_own_request', request.reported_by is not distinct from v_user_id,
        'can_review', request.reported_by is distinct from v_user_id,
        'can_approve_directly', request.reported_by is distinct from v_user_id
          and public.correction_field_is_directly_completable(
            base.payload,
            request.field_key
          ),
        'can_send_to_jury', request.reported_by is distinct from v_user_id
          and request.field_key <> 'other'
          and not public.correction_field_is_directly_completable(base.payload, request.field_key)
      )
      order by request.created_at, request.id
    ),
    '[]'::jsonb
  )
    into v_result
  from public.correction_requests as request
  join public.clothes as clothes on clothes.id = request.clothes_id
  left join public.profiles as profile on profile.id = request.reported_by
  cross join lateral (
    select public.jury_clothes_payload(request.clothes_id) as payload
  ) as base
  where request.status = 'pending';

  return v_result;
end;
$$;

create or replace function public.review_correction_request(
  p_request_id uuid,
  p_action text,
  p_accepted_value jsonb default null,
  p_resolution_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_action text := pg_catalog.btrim(coalesce(p_action, ''));
  v_note text := pg_catalog.btrim(coalesce(p_resolution_note, ''));
  v_request public.correction_requests%rowtype;
  v_clothes public.clothes%rowtype;
  v_base_payload jsonb;
  v_current_value jsonb;
  v_review_payload jsonb;
  v_accepted_patch jsonb;
  v_pending_id bigint;
  v_item_id uuid;
  v_existing_item_id uuid;
  v_existing_item_status text;
  v_suit_id uuid;
  v_expected_issue_fields text[];
  v_points_awarded integer := 0;
begin
  if v_user_id is null or not (select public.is_admin_or_super_admin()) then
    raise exception using
      errcode = '42501',
      message = '当前账号没有处理图鉴报错的权限';
  end if;

  if p_request_id is null then
    raise exception '请选择需要处理的图鉴报错';
  end if;

  if v_action not in ('approve_empty', 'send_to_jury', 'reject') then
    raise exception '处理动作只允许补全空字段、转交陪审或不采纳';
  end if;

  if pg_catalog.char_length(v_note) < 10 or pg_catalog.char_length(v_note) > 1000 then
    raise exception '请用 10 到 1000 个字填写处理说明';
  end if;

  select request.*
    into v_request
  from public.correction_requests as request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception '图鉴报错不存在';
  end if;

  if v_request.reported_by is not distinct from v_user_id then
    raise exception using
      errcode = '42501',
      message = '不能处理自己提交的图鉴报错';
  end if;

  if v_request.status <> 'pending' then
    if v_request.reviewed_by is not distinct from v_user_id
      and (
        (v_action = 'approve_empty' and v_request.status = 'approved' and v_request.re_review_item_id is null)
        or (v_action = 'send_to_jury' and v_request.re_review_item_id is not null)
        or (v_action = 'reject' and v_request.status = 'rejected' and v_request.re_review_item_id is null)
      ) then
      if v_note is distinct from coalesce(v_request.resolution_note, '') then
        raise exception '这条图鉴报错已经结案，只有完全相同的处理请求可以安全重试';
      end if;

      if v_action = 'reject' then
        if p_accepted_value is not null then
          raise exception '这条图鉴报错已经结案，只有完全相同的处理请求可以安全重试';
        end if;
      elsif not public.correction_accepted_value_is_valid(
        v_request.field_key,
        p_accepted_value
      ) or v_request.accepted_patch is distinct from pg_catalog.jsonb_build_object(
        v_request.field_key,
        p_accepted_value
      ) then
        raise exception '这条图鉴报错已经结案，只有完全相同的处理请求可以安全重试';
      end if;

      return pg_catalog.jsonb_build_object(
        'request_id', v_request.id,
        'status', v_request.status,
        're_review_item_id', v_request.re_review_item_id,
        'points_awarded', 0,
        'idempotent', true
      );
    end if;

    raise exception '这条图鉴报错已经由其他处理结果结案';
  end if;

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = v_request.clothes_id
  for update;

  if not found then
    raise exception '正式图鉴中找不到这件服装';
  end if;

  v_base_payload := public.jury_clothes_payload(v_clothes.id);
  v_current_value := public.correction_field_value(v_base_payload, v_request.field_key);

  if v_action = 'reject' then
    update public.correction_requests
    set
      status = 'rejected',
      reviewed_by = v_user_id,
      reviewed_at = pg_catalog.now(),
      resolution_note = v_note,
      updated_at = pg_catalog.now()
    where id = v_request.id;

    return pg_catalog.jsonb_build_object(
      'request_id', v_request.id,
      'status', 'rejected',
      'points_awarded', 0,
      'idempotent', false
    );
  end if;

  if not public.correction_accepted_value_is_valid(v_request.field_key, p_accepted_value) then
    raise exception '请填写与问题字段匹配的有效核对结果';
  end if;

  if v_current_value is not distinct from p_accepted_value then
    raise exception '核对结果与正式图鉴当前资料相同，无需修改';
  end if;

  v_accepted_patch := pg_catalog.jsonb_build_object(
    v_request.field_key,
    p_accepted_value
  );

  if v_action = 'approve_empty' then
    if not public.correction_field_is_directly_completable(v_base_payload, v_request.field_key) then
      raise exception '正式图鉴当前字段已有内容，必须转交陪审审核，不能直接覆盖';
    end if;

    case v_request.field_key
      when 'name' then
        update public.clothes
        set name = pg_catalog.btrim(p_accepted_value #>> '{}')
        where id = v_clothes.id;
      when 'game_id' then
        update public.clothes
        set game_id = pg_catalog.btrim(p_accepted_value #>> '{}')
        where id = v_clothes.id;
      when 'category' then
        update public.clothes
        set category = pg_catalog.btrim(p_accepted_value #>> '{}')
        where id = v_clothes.id;
      when 'stars' then
        update public.clothes
        set stars = (p_accepted_value #>> '{}')
        where id = v_clothes.id;
      when 'scores' then
        update public.clothes
        set scores = p_accepted_value
        where id = v_clothes.id;
      when 'suit' then
        v_suit_id := case
          when p_accepted_value->'suit_id' = 'null'::jsonb then null
          else (p_accepted_value->>'suit_id')::uuid
        end;
        update public.clothes
        set suit_id = v_suit_id, temp_suit_name = null
        where id = v_clothes.id;
      when 'tags' then
        update public.clothes
        set tags = nullif(pg_catalog.btrim(coalesce(p_accepted_value #>> '{}', '')), '')
        where id = v_clothes.id;
      else
        raise exception '该字段不能走空字段直接补全';
    end case;

    update public.correction_requests
    set
      status = 'approved',
      accepted_patch = v_accepted_patch,
      reviewed_by = v_user_id,
      reviewed_at = pg_catalog.now(),
      resolution_note = v_note,
      updated_at = pg_catalog.now()
    where id = v_request.id;

    if v_request.reported_by is not null then
      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        source_id,
        re_review_candidate_id,
        jury_vote_id,
        correction_request_id,
        reversal_of
      )
      values (
        v_request.reported_by,
        5,
        'awarded',
        'correction_request',
        null,
        null,
        null,
        v_request.id,
        null
      )
      on conflict (correction_request_id)
        where correction_request_id is not null do nothing;

      get diagnostics v_points_awarded = row_count;
      v_points_awarded := v_points_awarded * 5;
    end if;

    return pg_catalog.jsonb_build_object(
      'request_id', v_request.id,
      'status', 'approved',
      'points_awarded', v_points_awarded,
      'idempotent', false
    );
  end if;

  if public.correction_field_is_directly_completable(v_base_payload, v_request.field_key) then
    raise exception '正式图鉴当前字段缺失，请核实后直接补全，不需要转交陪审';
  end if;

  v_review_payload := case v_request.field_key
    when 'scores' then pg_catalog.jsonb_set(v_base_payload, '{scores}', p_accepted_value, false)
    when 'suit' then v_base_payload || p_accepted_value
    else pg_catalog.jsonb_set(
      v_base_payload,
      array[v_request.field_key],
      p_accepted_value,
      false
    )
  end;

  v_suit_id := case
    when v_review_payload->'suit_id' = 'null'::jsonb then null
    else (v_review_payload->>'suit_id')::uuid
  end;

  select item.id, item.status
    into v_existing_item_id, v_existing_item_status
  from public.re_review_items as item
  where item.identity_key = 'clothes|' || v_clothes.id
    and item.status in ('pending', 'voting', 'failed')
  order by item.created_at, item.id
  limit 1
  for update;

  if v_existing_item_id is not null
    and v_existing_item_status in ('pending', 'failed') then
    update public.pending_clothes as pending
    set status = 'pending'
    from public.correction_requests as linked_request
    where linked_request.re_review_item_id = v_existing_item_id
      and linked_request.source_pending_id = pending.id
      and linked_request.status = 'converted_to_re_review'
      and pending.status = 're_review';
  end if;

  insert into public.pending_clothes (
    name,
    category,
    stars,
    scores,
    tags,
    suit_name,
    game_id,
    status,
    submitted_by,
    suit_id,
    temp_suit_name,
    needs_suit_review
  )
  values (
    v_review_payload->>'name',
    v_review_payload->>'category',
    case when v_review_payload->'stars' = 'null'::jsonb then null else (v_review_payload->>'stars')::integer end,
    v_review_payload->'scores',
    v_review_payload->>'tags',
    null,
    v_review_payload->>'game_id',
    'pending',
    v_request.reported_by,
    v_suit_id,
    v_review_payload->>'temp_suit_name',
    coalesce((v_review_payload->>'needs_suit_review')::boolean, false)
  )
  returning id into v_pending_id;

  v_item_id := public.ensure_full_jury_review_item(
    v_pending_id,
    v_clothes.id,
    false
  );

  if v_item_id is null then
    raise exception '核对结果没有形成可审核的字段差异';
  end if;

  v_expected_issue_fields := case v_request.field_key
    when 'scores' then array['pair1', 'pair2', 'pair3', 'pair4', 'pair5']
    else array[v_request.field_key]
  end;

  if not exists (
    select 1
    from public.re_review_items as item
    cross join lateral pg_catalog.jsonb_array_elements(
      coalesce(item.payload->'issues', '[]'::jsonb)
    ) as issue(value)
    where item.id = v_item_id
      and issue.value->>'field' = any(v_expected_issue_fields)
  ) then
    raise exception '同一服装已有冻结中的其他审核内容，请等待本轮结束后再转交';
  end if;

  update public.pending_clothes as pending
  set status = 're_review'
  where pending.status = 'pending'
    and (
      pending.id = v_pending_id
      or exists (
        select 1
        from public.correction_requests as linked_request
        where linked_request.re_review_item_id = v_item_id
          and linked_request.source_pending_id = pending.id
          and linked_request.status = 'converted_to_re_review'
      )
    );

  update public.correction_requests
  set
    status = 'converted_to_re_review',
    accepted_patch = v_accepted_patch,
    source_pending_id = v_pending_id,
    re_review_item_id = v_item_id,
    reviewed_by = v_user_id,
    reviewed_at = pg_catalog.now(),
    resolution_note = v_note,
    updated_at = pg_catalog.now()
  where id = v_request.id;

  return pg_catalog.jsonb_build_object(
    'request_id', v_request.id,
    'status', 'converted_to_re_review',
    're_review_item_id', v_item_id,
    'points_awarded', 0,
    'idempotent', false
  );
end;
$$;

create or replace function public.sync_correction_requests_from_re_review()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status not in ('approved', 'rejected')
    or new.status is not distinct from old.status then
    return new;
  end if;

  with resolved as (
    select
      request.id,
      request.reported_by,
      case
        when new.status = 'approved'
          and public.correction_field_value(
            public.jury_clothes_payload(request.clothes_id),
            request.field_key
          ) is not distinct from request.accepted_patch->request.field_key
          then 'approved'
        else 'rejected'
      end as final_status
    from public.correction_requests as request
    where request.re_review_item_id = new.id
      and request.status = 'converted_to_re_review'
  ), updated as (
    update public.correction_requests as request
    set
      status = resolved.final_status,
      resolution_note = request.resolution_note || case resolved.final_status
        when 'approved' then '；陪审审核已采用该核对结果'
        else '；陪审审核未采用该核对结果'
      end,
      updated_at = pg_catalog.now()
    from resolved
    where request.id = resolved.id
    returning request.id, request.reported_by, request.status
  )
  insert into public.points_ledger (
    user_id,
    delta,
    status,
    source_type,
    source_id,
    re_review_candidate_id,
    jury_vote_id,
    correction_request_id,
    reversal_of
  )
  select
    updated.reported_by,
    5,
    'awarded',
    'correction_request',
    null,
    null,
    null,
    updated.id,
    null
  from updated
  where updated.status = 'approved'
    and updated.reported_by is not null
  on conflict (correction_request_id)
    where correction_request_id is not null do nothing;

  return new;
end;
$$;

create trigger sync_correction_requests_after_re_review
after update of status on public.re_review_items
for each row
execute function public.sync_correction_requests_from_re_review();

revoke all on function public.correction_field_value(jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.correction_accepted_value_is_valid(text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.correction_field_is_directly_completable(jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_correction_review_queue()
  from public, anon, authenticated, service_role;
revoke all on function public.review_correction_request(uuid, text, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_correction_requests_from_re_review()
  from public, anon, authenticated, service_role;

grant execute on function public.correction_field_value(jsonb, text) to service_role;
grant execute on function public.correction_accepted_value_is_valid(text, jsonb) to service_role;
grant execute on function public.correction_field_is_directly_completable(jsonb, text) to service_role;
grant execute on function public.get_correction_review_queue() to authenticated, service_role;
grant execute on function public.review_correction_request(uuid, text, jsonb, text)
  to authenticated, service_role;

comment on column public.correction_requests.accepted_patch is
  '管理员核实后的单字段结构化结果；直接补全或转重审均以此作为报错 +5 的唯一比对依据。';

comment on column public.correction_requests.re_review_item_id is
  '非空字段或争议修正转入的全字段重审事项；同一服装的活动事项继续复用。';

comment on column public.points_ledger.correction_request_id is
  '报错被直接采纳或陪审最终采用后产生的唯一 +5 积分来源。';

comment on function public.get_correction_review_queue() is
  'DB-9：仅管理员读取待处理图鉴报错、当前正式资料和可执行分流。';

comment on function public.review_correction_request(uuid, text, jsonb, text) is
  'DB-9：管理员不采纳、补全空字段或将非空修正转入全字段陪审；动作、正式资料、状态和 +5 结算保持原子幂等。';

commit;
