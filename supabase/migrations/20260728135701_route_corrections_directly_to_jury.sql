begin;

alter table public.correction_requests
  drop constraint correction_requests_review_shape_check;

alter table public.correction_requests
  add constraint correction_requests_review_shape_check
    check (
      (
        status = 'pending'
        and reviewed_by is null
        and reviewed_at is null
        and resolution_note is null
      )
      or (
        status in ('converted_to_re_review', 'approved', 'rejected')
        and nullif(pg_catalog.btrim(coalesce(resolution_note, '')), '') is not null
        and (
          (reviewed_by is not null and reviewed_at is not null)
          or (
            reviewed_by is null
            and reviewed_at is null
            and source_pending_id is not null
            and re_review_item_id is not null
          )
        )
      )
      or (
        status = 'reviewing'
        and reviewed_by is not null
        and reviewed_at is not null
        and nullif(pg_catalog.btrim(coalesce(resolution_note, '')), '') is not null
      )
    );

create or replace function public.correction_proposed_value_is_valid(
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
begin
  if p_value is null then
    return false;
  end if;

  if pg_catalog.jsonb_typeof(p_value) = 'string' then
    v_text := pg_catalog.btrim(p_value #>> '{}');
    return pg_catalog.char_length(v_text) between 1 and 500;
  end if;

  if p_field = 'stars' and pg_catalog.jsonb_typeof(p_value) = 'number' then
    v_number := (p_value #>> '{}')::numeric;
    return v_number = pg_catalog.trunc(v_number) and v_number between 1 and 6;
  end if;

  if p_field = 'scores' and pg_catalog.jsonb_typeof(p_value) = 'object' then
    return public.jury_scores_are_complete(p_value);
  end if;

  if p_field = 'suit' and pg_catalog.jsonb_typeof(p_value) = 'object' then
    return public.correction_accepted_value_is_valid(p_field, p_value);
  end if;

  return false;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;

create or replace function public.route_correction_request_to_jury(
  p_request_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_request public.correction_requests%rowtype;
  v_clothes public.clothes%rowtype;
  v_item public.re_review_items%rowtype;
  v_base_payload jsonb;
  v_proposal_payload jsonb;
  v_proposed_value jsonb;
  v_issue_fields text[];
  v_all_fields text[] := array[
    'name', 'game_id', 'category', 'stars',
    'pair1', 'pair2', 'pair3', 'pair4', 'pair5',
    'suit', 'tags'
  ];
  v_issue_field text;
  v_issue_kind text;
  v_new_issue jsonb;
  v_new_issues jsonb := '[]'::jsonb;
  v_merged_issues jsonb;
  v_field_options jsonb := '{}'::jsonb;
  v_pending_id bigint;
  v_item_id uuid;
  v_suit_id uuid;
begin
  if p_request_id is null then
    raise exception '图鉴报错不存在';
  end if;

  select request.*
    into v_request
  from public.correction_requests as request
  where request.id = p_request_id
  for update;

  if not found then
    raise exception '图鉴报错不存在';
  end if;

  if v_request.status = 'converted_to_re_review'
    and v_request.re_review_item_id is not null then
    return v_request.re_review_item_id;
  end if;

  if v_request.status <> 'pending' then
    raise exception '只有待处理报错可以转交陪审团';
  end if;

  if v_request.field_key = 'other' then
    raise exception '请选择一个明确的错误项目后再提交';
  end if;

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = v_request.clothes_id
  for key share;

  if not found then
    raise exception '正式图鉴中找不到这件服装';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db7-review|clothes|' || v_clothes.id, 0)
  );

  v_base_payload := public.jury_clothes_payload(v_clothes.id);
  v_proposed_value := v_request.proposed_patch->v_request.field_key;
  v_issue_fields := case v_request.field_key
    when 'scores' then array['pair1', 'pair2', 'pair3', 'pair4', 'pair5']
    else array[v_request.field_key]
  end;

  v_proposal_payload := case
    when v_request.field_key = 'scores'
      and pg_catalog.jsonb_typeof(v_proposed_value) = 'object'
      then pg_catalog.jsonb_set(v_base_payload, '{scores}', v_proposed_value, false)
    when v_request.field_key = 'suit'
      and pg_catalog.jsonb_typeof(v_proposed_value) = 'object'
      then v_base_payload || v_proposed_value
    when v_request.field_key not in ('scores', 'suit')
      then pg_catalog.jsonb_set(
        v_base_payload,
        array[v_request.field_key],
        v_proposed_value,
        false
      )
    else v_base_payload
  end;

  foreach v_issue_field in array v_all_fields loop
    continue when not (v_issue_field = any(v_issue_fields))
      and not public.jury_field_value_is_missing(v_base_payload, v_issue_field);

    v_issue_kind := case
      when public.jury_field_value_is_missing(v_base_payload, v_issue_field)
        then 'missing'
      else 'conflict'
    end;
    v_new_issues := v_new_issues || pg_catalog.jsonb_build_array(
      pg_catalog.jsonb_build_object(
        'field', v_issue_field,
        'kind', v_issue_kind
      )
    );
    v_field_options := v_field_options || pg_catalog.jsonb_build_object(
      v_issue_field,
      pg_catalog.jsonb_build_array(
        public.jury_payload_field_value(v_base_payload, v_issue_field),
        public.jury_payload_field_value(v_proposal_payload, v_issue_field)
      )
    );
  end loop;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.identity_key = 'clothes|' || v_clothes.id
    and item.status in ('pending', 'voting', 'failed')
  order by item.created_at, item.id
  limit 1
  for update;

  if found and v_item.status = 'voting' and exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_new_issues) as requested(value)
    where not exists (
      select 1
      from pg_catalog.jsonb_array_elements(
        coalesce(v_item.payload->'issues', '[]'::jsonb)
      ) as existing(value)
      where existing.value->>'field' = requested.value->>'field'
    )
  ) then
    raise exception '这件服装正在审核其他字段，请等待本轮结束后再提交新问题';
  end if;

  v_suit_id := case
    when v_base_payload->'suit_id' = 'null'::jsonb then null
    else (v_base_payload->>'suit_id')::uuid
  end;

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
    v_base_payload->>'name',
    v_base_payload->>'category',
    (v_base_payload->>'stars')::integer,
    v_base_payload->'scores',
    v_base_payload->>'tags',
    null,
    v_base_payload->>'game_id',
    're_review',
    null,
    v_suit_id,
    null,
    false
  )
  returning id into v_pending_id;

  if v_item.id is null then
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
      'correction',
      'pending',
      v_pending_id,
      v_clothes.id,
      pg_catalog.jsonb_build_object(
        'base_record', v_base_payload,
        'base_version', pg_catalog.md5(v_base_payload::text),
        'issues', v_new_issues,
        'field_options', v_field_options
      ),
      v_request.reported_by,
      'clothes|' || v_clothes.id
    )
    returning id into v_item_id;
  else
    v_item_id := v_item.id;
    if v_item.status in ('pending', 'failed') then
      v_merged_issues := coalesce(v_item.payload->'issues', '[]'::jsonb);
      for v_new_issue in
        select issue.value
        from pg_catalog.jsonb_array_elements(v_new_issues) as issue(value)
      loop
        v_issue_field := v_new_issue->>'field';
        if not exists (
          select 1
          from pg_catalog.jsonb_array_elements(v_merged_issues) as existing(value)
          where existing.value->>'field' = v_issue_field
        ) then
          v_merged_issues := v_merged_issues || v_new_issue;
        end if;
      end loop;

      update public.re_review_items
      set
        reason = 'correction',
        payload = pg_catalog.jsonb_build_object(
          'base_record', v_base_payload,
          'base_version', pg_catalog.md5(v_base_payload::text),
          'issues', v_merged_issues,
          'field_options', coalesce(v_item.payload->'field_options', '{}'::jsonb) || v_field_options
        ),
        updated_at = pg_catalog.now()
      where id = v_item_id;
    end if;
  end if;

  insert into public.re_review_item_sources (
    re_review_item_id,
    source_pending_id,
    source_user_id
  )
  values (
    v_item_id,
    v_pending_id,
    v_request.reported_by
  );

  update public.correction_requests
  set
    status = 'converted_to_re_review',
    accepted_patch = proposed_patch,
    source_pending_id = v_pending_id,
    re_review_item_id = v_item_id,
    resolution_note = '用户提交后已直接转交陪审团',
    updated_at = pg_catalog.now()
  where id = v_request.id;

  return v_item_id;
end;
$$;

create or replace function public.submit_correction_request(
  p_clothes_id varchar,
  p_reason text,
  p_proposed_patch jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_clothes public.clothes%rowtype;
  v_field_key text;
  v_field_count integer;
  v_proposed_value jsonb;
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_existing public.correction_requests%rowtype;
  v_request public.correction_requests%rowtype;
  v_item_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能提交图鉴报错';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_clothes_id, '')), '') is null then
    raise exception '请选择需要报错的正式服装';
  end if;

  if pg_catalog.char_length(v_reason) < 10 or pg_catalog.char_length(v_reason) > 1000 then
    raise exception '请用 10 到 1000 个字说明判断依据';
  end if;

  if pg_catalog.jsonb_typeof(p_proposed_patch) is distinct from 'object' then
    raise exception '建议内容必须是字段对象';
  end if;

  select pg_catalog.count(*)::integer, pg_catalog.min(key)
    into v_field_count, v_field_key
  from pg_catalog.jsonb_object_keys(p_proposed_patch) as proposed(key);

  if v_field_count <> 1
    or v_field_key not in ('name', 'game_id', 'category', 'stars', 'scores', 'suit', 'tags') then
    raise exception '每次请选择一个明确的问题字段';
  end if;

  v_proposed_value := p_proposed_patch->v_field_key;
  if not public.correction_proposed_value_is_valid(v_field_key, v_proposed_value) then
    raise exception '请填写与错误项目匹配的正确内容';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'correction_request|' || v_user_id::text || '|' || pg_catalog.btrim(p_clothes_id) || '|' || v_field_key,
      0
    )
  );

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = pg_catalog.btrim(p_clothes_id)
  for key share;

  if not found then
    raise exception '正式图鉴中找不到这件服装，请刷新图鉴后重试';
  end if;

  if public.correction_field_value(
    public.jury_clothes_payload(v_clothes.id),
    v_field_key
  ) is not distinct from v_proposed_value then
    raise exception '请把图鉴当前值改成正确内容后再提交';
  end if;

  select request.*
    into v_existing
  from public.correction_requests as request
  where request.clothes_id = v_clothes.id
    and request.reported_by = v_user_id
    and request.field_key = v_field_key
    and request.status in ('pending', 'reviewing', 'converted_to_re_review')
  order by request.created_at, request.id
  limit 1
  for update;

  if found then
    if v_existing.reason is not distinct from v_reason
      and v_existing.proposed_patch is not distinct from p_proposed_patch then
      return pg_catalog.jsonb_build_object(
        'request_id', v_existing.id,
        'status', v_existing.status,
        're_review_item_id', v_existing.re_review_item_id,
        'idempotent', true
      );
    end if;

    raise exception '这件服装的同一字段已有陪审中的报错，请等待处理完成后再提交';
  end if;

  insert into public.correction_requests (
    clothes_id,
    reported_by,
    field_key,
    reason,
    proposed_patch,
    clothes_snapshot
  )
  values (
    v_clothes.id,
    v_user_id,
    v_field_key,
    v_reason,
    p_proposed_patch,
    public.jury_clothes_payload(v_clothes.id)
  )
  returning * into v_request;

  v_item_id := public.route_correction_request_to_jury(v_request.id);

  return pg_catalog.jsonb_build_object(
    'request_id', v_request.id,
    'status', 'converted_to_re_review',
    're_review_item_id', v_item_id,
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
      resolution_note = coalesce(request.resolution_note, '') || case resolved.final_status
        when 'approved' then '；陪审审核已采用该报错建议'
        else '；陪审审核未采用该报错建议'
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

revoke all on function public.correction_proposed_value_is_valid(text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.route_correction_request_to_jury(uuid)
  from public, anon, authenticated, service_role;
revoke all on function public.submit_correction_request(varchar, text, jsonb)
  from public, anon, authenticated, service_role;
revoke all on function public.sync_correction_requests_from_re_review()
  from public, anon, authenticated, service_role;

grant execute on function public.submit_correction_request(varchar, text, jsonb)
  to authenticated, service_role;

comment on function public.submit_correction_request(varchar, text, jsonb) is
  '验收修复：登录用户选择明确错误项目后直接创建或复用全字段陪审事项；相同请求幂等，不经过管理员转交。';

comment on function public.route_correction_request_to_jury(uuid) is
  '内部函数：将待处理报错原子挂接到同一服装的唯一活动陪审事项，并保留报错用户来源以阻止自审。';

commit;
