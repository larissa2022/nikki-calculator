begin;

-- DB-10 direct correction-to-jury and focused-field regression verification.
-- Run only against local Supabase or the explicitly authorized development project.
-- Every fixture write is rolled back.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db10-direct-%@example.invalid'
  ) or exists (
    select 1 from public.clothes where id like 'db10_direct_%'
  ) then
    raise exception 'DB10_DIRECT_ASSERT: fixture identifiers already exist';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.route_correction_request_to_jury(uuid)',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'authenticated',
    'public.correction_proposed_value_is_valid(text,jsonb)',
    'EXECUTE'
  ) then
    raise exception 'DB10_DIRECT_ASSERT: internal correction helpers are exposed';
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
  ('d1000000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db10-direct-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 7) as fixture(value);

insert into public.suits (id, name)
values ('d1000000-0000-4000-8000-000000000090'::uuid, 'DB10 目标套装');

insert into public.clothes (
  id, name, category, game_id, stars, scores, tags, suit_id, temp_suit_name
)
values
  (
    'db10_direct_suit',
    'DB10 只改套装测试',
    '连衣裙',
    '993001',
    '5',
    '{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0}'::jsonb,
    '欧式古典',
    null,
    null
  ),
  (
    'db10_direct_missing',
    'DB10 缺失字段聚合测试',
    '连衣裙',
    '993002',
    '5',
    null,
    null,
    null,
    null
  );

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_item_id uuid;
  v_conflict_denied boolean := false;
  v_missing_item_id uuid;
begin
  v_first := public.submit_correction_request(
    'db10_direct_suit',
    '游戏内显示属于 DB10 目标套装，请核对所属套装。',
    '{"suit":{"suit_id":"d1000000-0000-4000-8000-000000000090","temp_suit_name":null,"needs_suit_review":false}}'::jsonb
  );
  v_item_id := (v_first->>'re_review_item_id')::uuid;

  if v_first->>'status' <> 'converted_to_re_review'
    or coalesce((v_first->>'idempotent')::boolean, true)
    or v_item_id is null
    or not exists (
      select 1
      from public.re_review_items as item
      where item.id = v_item_id
        and item.status = 'pending'
        and item.reason = 'correction'
        and item.identity_key = 'clothes|db10_direct_suit'
        and pg_catalog.jsonb_array_length(item.payload->'issues') = 1
        and item.payload->'issues'->0->>'field' = 'suit'
    ) then
    raise exception 'DB10_DIRECT_ASSERT: structured correction did not route directly';
  end if;

  v_retry := public.submit_correction_request(
    'db10_direct_suit',
    '游戏内显示属于 DB10 目标套装，请核对所属套装。',
    '{"suit":{"needs_suit_review":false,"temp_suit_name":null,"suit_id":"d1000000-0000-4000-8000-000000000090"}}'::jsonb
  );

  if not coalesce((v_retry->>'idempotent')::boolean, false)
    or (v_retry->>'re_review_item_id')::uuid is distinct from v_item_id
    or (
      select pg_catalog.count(*)
      from public.re_review_item_sources
      where re_review_item_id = v_item_id
    ) <> 1 then
    raise exception 'DB10_DIRECT_ASSERT: identical retry duplicated review facts';
  end if;

  begin
    perform public.submit_correction_request(
      'db10_direct_suit',
      '这次提交另一个套装建议，不能覆盖正在陪审的报错。',
      '{"suit":{"suit_id":null,"temp_suit_name":null,"needs_suit_review":false}}'::jsonb
    );
  exception when others then
    v_conflict_denied := true;
  end;

  if not v_conflict_denied then
    raise exception 'DB10_DIRECT_ASSERT: conflicting retry was accepted';
  end if;

  v_missing_item_id := (
    public.submit_correction_request(
      'db10_direct_missing',
      '服装名称和缺失的完整属性都需要由陪审团核对补充。',
      '{"name":"DB10 缺失字段修正名称"}'::jsonb
    )->>'re_review_item_id'
  )::uuid;

  if (
    select pg_catalog.count(*)
    from pg_catalog.jsonb_array_elements(
      (select payload->'issues' from public.re_review_items where id = v_missing_item_id)
    ) as issue(value)
    where issue.value->>'field' = any(array['name', 'pair1', 'pair2', 'pair3', 'pair4', 'pair5'])
  ) <> 6 then
    raise exception 'DB10_DIRECT_ASSERT: correction item omitted other missing fields';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.get_jury_review_queue()) as queue(item)
    where (queue.item->>'re_review_item_id')::uuid in (v_item_id, v_missing_item_id)
  ) then
    raise exception 'DB10_DIRECT_ASSERT: reporter can review own correction source';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
declare
  v_item_id uuid;
  v_candidate_payload jsonb;
  v_result jsonb;
begin
  select id into v_item_id
  from public.re_review_items
  where identity_key = 'clothes|db10_direct_suit'
    and status = 'pending';

  v_candidate_payload := '{
    "name":"DB10 只改套装测试",
    "game_id":"993001",
    "category":"连衣裙",
    "stars":5,
    "scores":{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0},
    "suit_id":"d1000000-0000-4000-8000-000000000090",
    "temp_suit_name":null,
    "tags":"欧式古典",
    "needs_suit_review":false
  }'::jsonb;

  v_result := public.submit_jury_candidate(v_item_id, v_candidate_payload);
  if v_result->>'candidate_status' <> 'voting'
    or (
      select candidate.payload->'scores'
      from public.re_review_candidates as candidate
      where candidate.id = (v_result->>'candidate_id')::uuid
    ) is distinct from '{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0}'::jsonb then
    raise exception 'DB10_DIRECT_ASSERT: suit-only candidate changed non-issue scores';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1000000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

do $$
declare
  v_candidate_id uuid;
  v_vote jsonb;
  v_user_index integer;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  join public.re_review_items as item on item.id = candidate.re_review_item_id
  where item.identity_key = 'clothes|db10_direct_suit'
    and candidate.status = 'voting';

  for v_user_index in 3..7 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'd1000000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );
    v_vote := public.cast_jury_vote(v_candidate_id, 'approve');
    if (v_vote->>'points_awarded')::integer <> 1 then
      raise exception 'DB10_DIRECT_ASSERT: juror % did not receive +1', v_user_index;
    end if;
  end loop;

  if (
    select pg_catalog.count(*)
    from public.points_ledger
    where jury_vote_id is not null
      and user_id between 'd1000000-0000-4000-8000-000000000003'::uuid
        and 'd1000000-0000-4000-8000-000000000007'::uuid
      and delta = 1
  ) <> 5
    or not exists (
      select 1
      from public.points_ledger
      where correction_request_id is not null
        and user_id = 'd1000000-0000-4000-8000-000000000001'::uuid
        and delta = 5
    )
    or not exists (
      select 1
      from public.points_ledger
      where re_review_candidate_id = v_candidate_id
        and user_id = 'd1000000-0000-4000-8000-000000000002'::uuid
        and delta = 8
    )
    or (select suit_id from public.clothes where id = 'db10_direct_suit')
      is distinct from 'd1000000-0000-4000-8000-000000000090'::uuid
    or not exists (
      select 1
      from public.correction_requests
      where clothes_id = 'db10_direct_suit'
        and status = 'approved'
    ) then
    raise exception 'DB10_DIRECT_ASSERT: approval, +1, +5 or +8 settlement is incorrect';
  end if;
end;
$$;

select 'db10_direct_correction_jury_passed' as result;

rollback;
