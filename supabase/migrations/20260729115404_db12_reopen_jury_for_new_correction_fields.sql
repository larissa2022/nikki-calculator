begin;

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
  v_reopen_voting boolean := false;
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

  if v_item.id is not null and v_item.status = 'voting' then
    select exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_new_issues) as requested(value)
      where not exists (
        select 1
        from pg_catalog.jsonb_array_elements(
          case
            when v_item.payload ? 'issues' then v_item.payload->'issues'
            when v_item.reason = 'missing_suit' then pg_catalog.jsonb_build_array(
              pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
            )
            else '[]'::jsonb
          end
        ) as existing(value)
        where existing.value->>'field' = requested.value->>'field'
      )
    ) into v_reopen_voting;
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
    if v_item.status in ('pending', 'failed') or v_reopen_voting then
      v_merged_issues := case
        when v_item.payload ? 'issues' then v_item.payload->'issues'
        when v_item.reason = 'missing_suit' then pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
        )
        else '[]'::jsonb
      end;

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

      if v_reopen_voting then
        update public.re_review_candidates
        set
          status = 'returned',
          resolved_at = pg_catalog.now()
        where re_review_item_id = v_item_id
          and status = 'voting';

        if not found then
          raise exception '审核事项状态异常，请刷新后重试';
        end if;
      end if;

      update public.re_review_items
      set
        reason = 'correction',
        status = case when v_reopen_voting then 'pending' else status end,
        payload = pg_catalog.jsonb_build_object(
          'base_record', v_base_payload,
          'base_version', pg_catalog.md5(v_base_payload::text),
          'issues', v_merged_issues,
          'field_options', coalesce(v_item.payload->'field_options', '{}'::jsonb) || v_field_options
        ),
        resolved_by = case when v_reopen_voting then null else resolved_by end,
        resolved_at = case when v_reopen_voting then null else resolved_at end,
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
    resolution_note = case
      when v_reopen_voting
        then '用户提交后已合并新问题并重新等待补充'
      else '用户提交后已直接转交陪审团'
    end,
    updated_at = pg_catalog.now()
  where id = v_request.id;

  return v_item_id;
end;
$$;

revoke all on function public.route_correction_request_to_jury(uuid)
  from public, anon, authenticated, service_role;

comment on function public.route_correction_request_to_jury(uuid) is
  '内部函数：将报错挂接到同一服装唯一活动审核项；新字段到达投票轮次时保留历史票据并重开为等待补充。';

commit;
