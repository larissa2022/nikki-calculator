-- DB-9 correction request admin review verification.
-- Every fixture write is rolled back.

begin;

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db9-correction-%@example.invalid'
  ) or exists (
    select 1 from public.clothes where id like 'db9_correction_%'
  ) then
    raise exception 'DB9_CORRECTION_ASSERT: fixture identifiers already exist';
  end if;

  if has_function_privilege('anon', 'public.get_correction_review_queue()', 'EXECUTE')
    or not has_function_privilege('authenticated', 'public.get_correction_review_queue()', 'EXECUTE')
    or has_function_privilege(
      'anon',
      'public.review_correction_request(uuid,text,jsonb,text)',
      'EXECUTE'
    )
    or not has_function_privilege(
      'authenticated',
      'public.review_correction_request(uuid,text,jsonb,text)',
      'EXECUTE'
    ) then
    raise exception 'DB9_CORRECTION_ASSERT: public RPC grants are incorrect';
  end if;

  if has_function_privilege(
    'authenticated',
    'public.sync_correction_requests_from_re_review()',
    'EXECUTE'
  ) then
    raise exception 'DB9_CORRECTION_ASSERT: internal trigger function is exposed';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname = 'points_ledger_correction_request_id_key'
      and index_definition.indisunique
      and index_definition.indpred is not null
  ) then
    raise exception 'DB9_CORRECTION_ASSERT: correction reward unique index is missing';
  end if;
end;
$$;

insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
select
  '00000000-0000-0000-0000-000000000000'::uuid,
  ('db900000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db9-correction-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 4) as fixture(value);

update public.profiles
set role = 'super_admin'
where id = 'db900000-0000-4000-8000-000000000003'::uuid;

insert into public.clothes (
  id,
  name,
  category,
  game_id,
  stars,
  scores,
  suit_id,
  temp_suit_name,
  tags
)
values
  (
    'db9_correction_empty',
    'DB9 空字段补全测试',
    '连衣裙',
    '991001',
    '5',
    null,
    null,
    null,
    null
  ),
  (
    'db9_correction_conflict',
    'DB9 非空修正测试',
    '连衣裙',
    '991002',
    '5',
    '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
    null,
    null,
    null
  ),
  (
    'db9_correction_reject',
    'DB9 不采纳测试',
    '连衣裙',
    '991003',
    '4',
    '{"simple":3200,"gorgeous":0,"active":3200,"elegant":0,"cute":3200,"mature":0,"pure":3200,"sexy":0,"cool":3200,"warm":0}'::jsonb,
    null,
    null,
    '现有标签'
  );

do $$
declare
  v_empty_request_id uuid;
  v_conflict_request_id uuid;
  v_tags_request_id uuid;
  v_reject_request_id uuid;
  v_self_request_id uuid;
  v_existing_item_id uuid;
  v_contribution_result jsonb;
  v_queue jsonb;
begin
  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  insert into public.correction_requests (
    clothes_id, reported_by, field_key, reason, proposed_patch, clothes_snapshot
  ) values (
    'db9_correction_empty',
    'db900000-0000-4000-8000-000000000001'::uuid,
    'scores',
    '正式图鉴缺少完整属性分值，请管理员核对补全。',
    '{"scores":"五组属性请按游戏内图鉴完整补全"}'::jsonb,
    public.jury_clothes_payload('db9_correction_empty')
  ) returning id into v_empty_request_id;

  insert into public.correction_requests (
    clothes_id, reported_by, field_key, reason, proposed_patch, clothes_snapshot
  ) values (
    'db9_correction_conflict',
    'db900000-0000-4000-8000-000000000001'::uuid,
    'stars',
    '游戏内图鉴显示为四星，现有五星资料需要复核。',
    '{"stars":"4"}'::jsonb,
    public.jury_clothes_payload('db9_correction_conflict')
  ) returning id into v_conflict_request_id;

  insert into public.correction_requests (
    clothes_id, reported_by, field_key, reason, proposed_patch, clothes_snapshot
  ) values (
    'db9_correction_empty',
    'db900000-0000-4000-8000-000000000001'::uuid,
    'tags',
    '正式图鉴未记录特殊标签，请管理员核对后直接补全。',
    '{"tags":"欧式古典"}'::jsonb,
    public.jury_clothes_payload('db9_correction_empty')
  ) returning id into v_tags_request_id;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000002","role":"authenticated"}',
    true
  );

  insert into public.correction_requests (
    clothes_id, reported_by, field_key, reason, proposed_patch, clothes_snapshot
  ) values (
    'db9_correction_reject',
    'db900000-0000-4000-8000-000000000002'::uuid,
    'tags',
    '该标签看起来不准确，但暂时没有足够依据支持修改。',
    '{"tags":"建议标签"}'::jsonb,
    public.jury_clothes_payload('db9_correction_reject')
  ) returning id into v_reject_request_id;

  v_contribution_result := public.submit_clothing_contribution(
    'DB9 非空修正测试',
    '991002',
    '连衣裙',
    3,
    '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
    null,
    null,
    null,
    false
  );
  v_existing_item_id := (v_contribution_result->>'re_review_item_id')::uuid;

  if not coalesce((v_contribution_result->>'review_required')::boolean, false)
    or v_existing_item_id is null then
    raise exception 'DB9_CORRECTION_ASSERT: existing active review setup failed';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );

  insert into public.correction_requests (
    clothes_id, reported_by, field_key, reason, proposed_patch, clothes_snapshot
  ) values (
    'db9_correction_reject',
    'db900000-0000-4000-8000-000000000003'::uuid,
    'stars',
    '管理员本人提交的报错不能由本人继续处理审核。',
    '{"stars":"3"}'::jsonb,
    public.jury_clothes_payload('db9_correction_reject')
  ) returning id into v_self_request_id;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000004","role":"authenticated"}',
    true
  );

  begin
    perform public.get_correction_review_queue();
    raise exception 'DB9_CORRECTION_ASSERT: regular user read admin queue';
  exception
    when insufficient_privilege then null;
  end;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );

  v_queue := public.get_correction_review_queue();

  if (
    select pg_catalog.count(*)
    from pg_catalog.jsonb_array_elements(v_queue) as queue(item)
    where (queue.item->>'request_id')::uuid = any(array[
      v_empty_request_id,
      v_conflict_request_id,
      v_tags_request_id,
      v_reject_request_id,
      v_self_request_id
    ]::uuid[])
  ) <> 5
    or not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_queue) as queue(item)
      where (queue.item->>'request_id')::uuid = v_empty_request_id
        and (queue.item->>'can_approve_directly')::boolean
        and not (queue.item->>'can_send_to_jury')::boolean
    )
    or not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_queue) as queue(item)
      where (queue.item->>'request_id')::uuid = v_conflict_request_id
        and not (queue.item->>'can_approve_directly')::boolean
        and (queue.item->>'can_send_to_jury')::boolean
    )
    or not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_queue) as queue(item)
      where (queue.item->>'request_id')::uuid = v_tags_request_id
        and (queue.item->>'can_approve_directly')::boolean
        and not (queue.item->>'can_send_to_jury')::boolean
    )
    or not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_queue) as queue(item)
      where (queue.item->>'request_id')::uuid = v_self_request_id
        and (queue.item->>'is_own_request')::boolean
        and not (queue.item->>'can_review')::boolean
        and not (queue.item->>'can_approve_directly')::boolean
        and not (queue.item->>'can_send_to_jury')::boolean
    ) then
    raise exception 'DB9_CORRECTION_ASSERT: admin queue routing is incorrect: %', v_queue;
  end if;

  begin
    perform public.review_correction_request(
      v_self_request_id,
      'reject',
      null,
      '管理员本人不能处理自己提交的图鉴报错。'
    );
    raise exception 'DB9_CORRECTION_ASSERT: administrator reviewed own report';
  exception
    when insufficient_privilege then null;
  end;

  perform public.review_correction_request(
    v_tags_request_id,
    'approve_empty',
    '"欧式古典"'::jsonb,
    '已核对游戏内图鉴，确认需要补全这一项特殊标签。'
  );

  if (select tags from public.clothes where id = 'db9_correction_empty') <> '欧式古典'
    or not exists (
      select 1
      from public.points_ledger
      where correction_request_id = v_tags_request_id
        and delta = 5
    ) then
    raise exception 'DB9_CORRECTION_ASSERT: empty tags completion or reward failed';
  end if;

  perform public.review_correction_request(
    v_empty_request_id,
    'approve_empty',
    '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
    '已核对游戏内完整属性分值，仅补全原本缺失的属性字段。'
  );

  if (select status from public.correction_requests where id = v_empty_request_id) <> 'approved'
    or not public.jury_scores_are_complete(
      (select scores from public.clothes where id = 'db9_correction_empty')
    )
    or (
      select pg_catalog.count(*)
      from public.points_ledger
      where correction_request_id = v_empty_request_id
        and user_id = 'db900000-0000-4000-8000-000000000001'::uuid
        and delta = 5
    ) <> 1 then
    raise exception 'DB9_CORRECTION_ASSERT: direct completion or +5 reward failed';
  end if;

  if (public.review_correction_request(
    v_empty_request_id,
    'approve_empty',
    '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
    '已核对游戏内完整属性分值，仅补全原本缺失的属性字段。'
  )->>'idempotent')::boolean is not true
    or (
      select pg_catalog.count(*)
      from public.points_ledger
      where correction_request_id = v_empty_request_id
    ) <> 1 then
    raise exception 'DB9_CORRECTION_ASSERT: direct completion retry duplicated reward';
  end if;

  begin
    perform public.review_correction_request(
      v_empty_request_id,
      'approve_empty',
      '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
      '改写后的处理说明不能伪装成同一次幂等重试。'
    );
    raise exception 'DB9_CORRECTION_ASSERT: mismatched completion retry was accepted';
  exception
    when others then
      if sqlerrm = 'DB9_CORRECTION_ASSERT: mismatched completion retry was accepted' then
        raise;
      end if;
  end;

  perform public.review_correction_request(
    v_conflict_request_id,
    'send_to_jury',
    '4'::jsonb,
    '正式资料已有非空星级，已核对建议值并转交陪审审核。'
  );

  if not exists (
    select 1
    from public.correction_requests as request
    join public.pending_clothes as pending on pending.id = request.source_pending_id
    join public.re_review_items as item on item.id = request.re_review_item_id
    where request.id = v_conflict_request_id
      and request.status = 'converted_to_re_review'
      and request.accepted_patch = '{"stars":4}'::jsonb
      and request.re_review_item_id = v_existing_item_id
      and pending.status = 're_review'
      and item.status = 'pending'
      and (
        select pg_catalog.count(*)
        from public.re_review_item_sources as source
        where source.re_review_item_id = item.id
      ) = 2
      and exists (
        select 1
        from pg_catalog.jsonb_array_elements(item.payload->'issues') as issue(value)
        where issue.value->>'field' = 'stars'
      )
  ) or exists (
    select 1 from public.points_ledger where correction_request_id = v_conflict_request_id
  ) then
    raise exception 'DB9_CORRECTION_ASSERT: non-empty correction did not route safely';
  end if;

  if (public.review_correction_request(
    v_conflict_request_id,
    'send_to_jury',
    '4'::jsonb,
    '正式资料已有非空星级，已核对建议值并转交陪审审核。'
  )->>'idempotent')::boolean is not true then
    raise exception 'DB9_CORRECTION_ASSERT: route retry was not idempotent';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000001","role":"authenticated"}',
    true
  );

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.get_jury_review_queue()) as queue(item)
    where (queue.item->>'item_id')::uuid = (
      select request.re_review_item_id
      from public.correction_requests as request
      where request.id = v_conflict_request_id
    )
  ) then
    raise exception 'DB9_CORRECTION_ASSERT: correction reporter could review own source';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"db900000-0000-4000-8000-000000000003","role":"authenticated"}',
    true
  );

  update public.clothes
  set stars = '4'
  where id = 'db9_correction_conflict';

  update public.re_review_items
  set
    status = 'approved',
    resolved_by = 'db900000-0000-4000-8000-000000000004'::uuid,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = (
    select request.re_review_item_id
    from public.correction_requests as request
    where request.id = v_conflict_request_id
  );

  if (select status from public.correction_requests where id = v_conflict_request_id) <> 'approved'
    or (
      select pg_catalog.count(*)
      from public.points_ledger
      where correction_request_id = v_conflict_request_id
        and user_id = 'db900000-0000-4000-8000-000000000001'::uuid
        and delta = 5
    ) <> 1 then
    raise exception 'DB9_CORRECTION_ASSERT: jury adoption did not settle report +5';
  end if;

  perform public.review_correction_request(
    v_reject_request_id,
    'reject',
    null,
    '当前依据不足以支持修改正式资料，本次报错暂不采纳。'
  );

  if (select status from public.correction_requests where id = v_reject_request_id) <> 'rejected'
    or exists (
      select 1 from public.points_ledger where correction_request_id = v_reject_request_id
    )
    or (select tags from public.clothes where id = 'db9_correction_reject') <> '现有标签' then
    raise exception 'DB9_CORRECTION_ASSERT: rejection changed data or rewarded points';
  end if;
end;
$$;

select 'db9_correction_request_review_passed' as result;

rollback;
