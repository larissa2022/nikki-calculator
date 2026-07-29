begin;

-- DB-12 voting-round reopening when a new correction field arrives.
-- Run only against local Supabase or the explicitly authorized development project.
-- Every fixture write is rolled back.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db12-reopen-%@example.invalid'
  ) or exists (
    select 1 from public.clothes where id = 'db12_reopen_clothes'
  ) or exists (
    select 1 from public.pending_clothes where id = -120001
  ) or exists (
    select 1 from public.re_review_items
    where id = 'd1200000-0000-4000-8000-000000000081'::uuid
  ) then
    raise exception 'DB12_REOPEN_ASSERT: fixture identifiers already exist';
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
  ('d1200000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db12-reopen-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 5) as fixture(value);

insert into public.suits (id, name)
values ('d1200000-0000-4000-8000-000000000090'::uuid, 'DB12 原投票套装');

insert into public.clothes (
  id, name, category, game_id, stars, scores, tags, suit_id, temp_suit_name
)
values (
  'db12_reopen_clothes',
  'DB12 投票中新增问题测试',
  '连衣裙',
  '995001',
  '5',
  '{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0}'::jsonb,
  null,
  null,
  null
);

insert into public.pending_clothes (
  id, name, category, stars, scores, tags, game_id, status,
  submitted_by, suit_id, temp_suit_name, needs_suit_review
)
values (
  -120001,
  'DB12 投票中新增问题测试',
  '连衣裙',
  5,
  '{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0}'::jsonb,
  null,
  '995001',
  're_review',
  'd1200000-0000-4000-8000-000000000001'::uuid,
  null,
  null,
  true
);

insert into public.re_review_items (
  id, reason, status, source_pending_id, clothes_id, payload, submitted_by, identity_key
)
values (
  'd1200000-0000-4000-8000-000000000081'::uuid,
  'missing_suit',
  'pending',
  -120001,
  'db12_reopen_clothes',
  '{"name":"DB12 投票中新增问题测试","game_id":"995001","category":"连衣裙"}'::jsonb,
  'd1200000-0000-4000-8000-000000000001'::uuid,
  'clothes|db12_reopen_clothes'
);

insert into public.re_review_item_sources (
  re_review_item_id, source_pending_id, source_user_id
)
values (
  'd1200000-0000-4000-8000-000000000081'::uuid,
  -120001,
  'd1200000-0000-4000-8000-000000000001'::uuid
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1200000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

select public.submit_jury_candidate(
  'd1200000-0000-4000-8000-000000000081'::uuid,
  '{"suit_id":"d1200000-0000-4000-8000-000000000090"}'::jsonb
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1200000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);

select public.cast_jury_vote(
  (
    select candidate.id
    from public.re_review_candidates as candidate
    where candidate.re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
      and candidate.status = 'voting'
  ),
  'approve'
);

insert into storage.objects (bucket_id, name, owner_id, metadata)
values (
  'correction-evidence',
  'd1200000-0000-4000-8000-000000000004/d1200000-0000-4000-8000-000000000091.png',
  'd1200000-0000-4000-8000-000000000004',
  '{"mimetype":"image/png","size":1024}'::jsonb
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1200000-0000-4000-8000-000000000004","role":"authenticated"}',
  true
);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_request_id uuid;
  v_queue_item jsonb;
begin
  v_first := public.submit_correction_request_with_evidence(
    'db12_reopen_clothes',
    '{"stars":4}'::jsonb,
    'd1200000-0000-4000-8000-000000000004/d1200000-0000-4000-8000-000000000091.png'
  );
  v_request_id := (v_first->>'request_id')::uuid;

  if v_first->>'status' <> 'converted_to_re_review'
    or (v_first->>'re_review_item_id')::uuid
      is distinct from 'd1200000-0000-4000-8000-000000000081'::uuid
    or coalesce((v_first->>'idempotent')::boolean, true) then
    raise exception 'DB12_REOPEN_ASSERT: new correction did not reuse the active item: %', v_first;
  end if;

  if not exists (
    select 1
    from public.re_review_items as item
    where item.id = 'd1200000-0000-4000-8000-000000000081'::uuid
      and item.status = 'pending'
      and item.reason = 'correction'
      and (
        select pg_catalog.count(*)
        from pg_catalog.jsonb_array_elements(item.payload->'issues') as issue(value)
        where issue.value->>'field' = any(array['suit', 'stars'])
      ) = 2
      and pg_catalog.jsonb_array_length(item.payload->'issues') = 2
  ) then
    raise exception 'DB12_REOPEN_ASSERT: active item was not reopened with suit and stars';
  end if;

  if not exists (
    select 1
    from public.re_review_candidates as candidate
    where candidate.re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
      and candidate.status = 'returned'
      and candidate.resolved_at is not null
  ) or exists (
    select 1
    from public.re_review_candidates as candidate
    where candidate.re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
      and candidate.status = 'voting'
  ) then
    raise exception 'DB12_REOPEN_ASSERT: old voting candidate was not returned';
  end if;

  if (
    select pg_catalog.count(*)
    from public.jury_votes as vote
    join public.re_review_candidates as candidate on candidate.id = vote.candidate_id
    where candidate.re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
  ) <> 1
    or (
      select pg_catalog.count(*)
      from public.points_ledger
      where jury_vote_id is not null
        and user_id = 'd1200000-0000-4000-8000-000000000003'::uuid
        and delta = 1
    ) <> 1 then
    raise exception 'DB12_REOPEN_ASSERT: historical vote or participation point was changed';
  end if;

  if not exists (
    select 1
    from public.correction_requests as request
    where request.id = v_request_id
      and request.status = 'converted_to_re_review'
      and request.field_key = 'stars'
      and request.re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
      and request.evidence_image_path =
        'd1200000-0000-4000-8000-000000000004/d1200000-0000-4000-8000-000000000091.png'
      and request.resolution_note = '用户提交后已合并新问题并重新等待补充'
  ) then
    raise exception 'DB12_REOPEN_ASSERT: correction request was not linked to the reopened item';
  end if;

  if (select stars from public.clothes where id = 'db12_reopen_clothes') <> '5'
    or (
      select pg_catalog.count(*)
      from public.re_review_items
      where identity_key = 'clothes|db12_reopen_clothes'
        and status in ('pending', 'voting', 'failed')
    ) <> 1 then
    raise exception 'DB12_REOPEN_ASSERT: formal clothing changed or active item duplicated';
  end if;

  v_retry := public.submit_correction_request_with_evidence(
    'db12_reopen_clothes',
    '{"stars":4}'::jsonb,
    'd1200000-0000-4000-8000-000000000004/d1200000-0000-4000-8000-000000000091.png'
  );

  if not coalesce((v_retry->>'idempotent')::boolean, false)
    or (v_retry->>'request_id')::uuid is distinct from v_request_id
    or (select pg_catalog.count(*) from public.correction_requests where clothes_id = 'db12_reopen_clothes') <> 1
    or (
      select pg_catalog.count(*)
      from public.re_review_item_sources
      where re_review_item_id = 'd1200000-0000-4000-8000-000000000081'::uuid
    ) <> 2 then
    raise exception 'DB12_REOPEN_ASSERT: identical retry duplicated review facts';
  end if;

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"d1200000-0000-4000-8000-000000000005","role":"authenticated"}',
    true
  );

  select queue.item
    into v_queue_item
  from pg_catalog.jsonb_array_elements(public.get_jury_review_queue_with_evidence()) as queue(item)
  where (queue.item->>'re_review_item_id')::uuid =
    'd1200000-0000-4000-8000-000000000081'::uuid;

  if v_queue_item is null
    or not coalesce((v_queue_item->>'can_submit_candidate')::boolean, false)
    or v_queue_item->>'item_status' <> 'pending'
    or (
      select pg_catalog.count(*)
      from pg_catalog.jsonb_array_elements(v_queue_item->'issues') as issue(value)
      where issue.value->>'field' = any(array['suit', 'stars'])
    ) <> 2
    or v_queue_item->'correction_evidence'->0->>'evidence_image_path'
      <> 'd1200000-0000-4000-8000-000000000004/d1200000-0000-4000-8000-000000000091.png' then
    raise exception 'DB12_REOPEN_ASSERT: reopened item is not ready for another user: %', v_queue_item;
  end if;
end;
$$;

select 'db12_reopen_jury_for_new_correction_fields_passed' as result;

rollback;
