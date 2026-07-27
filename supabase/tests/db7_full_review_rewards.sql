begin;

-- DB-7 full-record review and juror reward verification.
-- Run only against local Supabase or the explicitly authorized development project.
-- Every fixture write is rolled back.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'f8000000-0000-4000-8000-000000000001'::uuid
      and 'f8000000-0000-4000-8000-000000000012'::uuid
  ) or exists (
    select 1 from public.clothes where name like 'DB7 全字段测试%'
  ) then
    raise exception 'DB7_FULL_ASSERT: fixture identifiers already exist';
  end if;
end;
$$;

do $$
begin
  if pg_catalog.has_function_privilege(
    'anon',
    'public.get_jury_review_queue()',
    'EXECUTE'
  ) then
    raise exception 'DB7_FULL_ASSERT: anonymous role can execute jury queue RPC';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated',
    'public.get_jury_review_queue()',
    'EXECUTE'
  ) then
    raise exception 'DB7_FULL_ASSERT: authenticated role cannot execute jury queue RPC';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.jury_pending_payload(bigint)',
    'EXECUTE'
  ) then
    raise exception 'DB7_FULL_ASSERT: authenticated role can execute internal helper';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.jury_field_value_is_missing(jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'DB7_FULL_ASSERT: authenticated role can execute field validator';
  end if;

  if not public.jury_field_value_is_missing(
    '{"scores":{},"needs_suit_review":false,"temp_suit_name":null}'::jsonb,
    'pair1'
  ) or public.jury_field_value_is_missing(
    '{"scores":{},"suit_id":null,"needs_suit_review":false,"temp_suit_name":null}'::jsonb,
    'suit'
  ) or not public.jury_field_value_is_missing(
    '{"scores":{},"suit_id":null,"needs_suit_review":true,"temp_suit_name":null}'::jsonb,
    'suit'
  ) then
    raise exception 'DB7_FULL_ASSERT: missing-field classification is incorrect';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.jury_scores_are_complete(jsonb)',
    'EXECUTE'
  ) then
    raise exception 'DB7_FULL_ASSERT: authenticated role can execute score validator';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname = 're_review_items_active_identity_key'
      and index_definition.indisunique
      and index_definition.indpred is not null
  ) then
    raise exception 'DB7_FULL_ASSERT: active review identity partial unique index is missing';
  end if;

  if not exists (
    select 1
    from pg_catalog.pg_index as index_definition
    join pg_catalog.pg_class as index_relation
      on index_relation.oid = index_definition.indexrelid
    where index_relation.relname = 'points_ledger_jury_vote_id_key'
      and index_definition.indisunique
      and index_definition.indpred is not null
  ) then
    raise exception 'DB7_FULL_ASSERT: jury vote ledger partial unique index is missing';
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
  ('f8000000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db7-full-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 12) as fixture(value);

insert into public.suits (id, name)
values ('f8000000-0000-4000-8000-000000000090'::uuid, 'DB7 全字段测试套装');

insert into public.clothes (
  id, name, category, game_id, stars, scores, suit_id, temp_suit_name, tags
)
values (
  'db7_full_existing',
  'DB7 全字段测试正式资料',
  '连衣裙',
  '980002',
  '5',
  '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
  null,
  null,
  null
);

do $$
declare
  v_user_index integer;
  v_result jsonb;
  v_scores jsonb;
  v_name text;
  v_stars integer;
  v_suit_id uuid;
begin
  for v_user_index in 1..5 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'f8000000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );

    if v_user_index <= 3 then
      v_name := 'DB7 全字段测试资料甲';
      v_stars := 5;
      v_suit_id := null;
      v_scores := '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb;
    else
      v_name := 'DB7 全字段测试资料乙';
      v_stars := 4;
      v_suit_id := 'f8000000-0000-4000-8000-000000000090'::uuid;
      v_scores := '{"simple":0,"gorgeous":4305,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb;
    end if;

    v_result := public.submit_clothing_contribution(
      v_name,
      '980001',
      '连衣裙',
      v_stars,
      v_scores,
      v_suit_id,
      null,
      null,
      false
    );

    if not (v_result ? 'review_required')
      or not (v_result ? 're_review_item_id') then
      raise exception 'DB7_FULL_ASSERT: contribution result is missing review contract fields: %', v_result;
    end if;

    if v_user_index < 5 and coalesce((v_result->>'review_required')::boolean, false) then
      raise exception 'DB7_FULL_ASSERT: review opened before five distinct users: %', v_result;
    end if;

    if v_user_index = 5 and (
      coalesce((v_result->>'review_required')::boolean, false) = false
      or (v_result->>'re_review_item_id') is null
    ) then
      raise exception 'DB7_FULL_ASSERT: fifth conflicting submission did not open review: %', v_result;
    end if;
  end loop;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"f8000000-0000-4000-8000-000000000012","role":"authenticated"}',
  true
);

do $$
declare
  v_existing_item_id uuid;
  v_result jsonb;
begin
  select item.id into v_existing_item_id
  from public.re_review_items as item
  where item.identity_key = 'entry|game|连衣裙|980001'
    and item.status = 'pending';

  v_result := public.submit_clothing_contribution(
    'DB7 全字段测试资料丙',
    '980001',
    '连衣裙',
    4,
    '{"simple":0,"gorgeous":4305,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
    null,
    null,
    null,
    false
  );

  if v_result->>'re_review_item_id' is distinct from v_existing_item_id::text
    or (select pg_catalog.count(*) from public.re_review_items where identity_key = 'entry|game|连衣裙|980001' and status in ('pending', 'voting', 'failed')) <> 1 then
    raise exception 'DB7_FULL_ASSERT: active review was not reused: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"f8000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

select public.submit_clothing_contribution(
  'DB7 全字段测试正式资料修正',
  '980002',
  '连衣裙',
  5,
  '{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0}'::jsonb,
  null,
  null,
  null,
  false
);

do $$
declare
  v_item_id uuid;
  v_payload jsonb;
  v_duplicate_identity_denied boolean := false;
begin
  select item.id, item.payload
    into v_item_id, v_payload
  from public.re_review_items as item
  where item.identity_key = 'entry|game|连衣裙|980001'
    and item.status = 'pending';

  if v_item_id is null
    or (select pg_catalog.count(*) from public.re_review_items where identity_key = 'entry|game|连衣裙|980001' and status in ('pending', 'voting', 'failed')) <> 1
    or not (v_payload->'issues' @> '[{"field":"name","kind":"conflict"}]'::jsonb)
    or not (v_payload->'issues' @> '[{"field":"stars","kind":"conflict"}]'::jsonb)
    or not (v_payload->'issues' @> '[{"field":"pair1","kind":"conflict"}]'::jsonb)
    or not (v_payload->'issues' @> '[{"field":"suit","kind":"conflict"}]'::jsonb) then
    raise exception 'DB7_FULL_ASSERT: multi-field issues were incomplete: %', v_payload;
  end if;

  begin
    insert into public.re_review_items (
      reason,
      status,
      source_pending_id,
      payload,
      submitted_by,
      identity_key
    )
    select
      item.reason,
      item.status,
      item.source_pending_id,
      item.payload,
      item.submitted_by,
      item.identity_key
    from public.re_review_items as item
    where item.id = v_item_id;
  exception when unique_violation then
    v_duplicate_identity_denied := true;
  end;

  if not v_duplicate_identity_denied then
    raise exception 'DB7_FULL_ASSERT: duplicate active review identity was accepted';
  end if;

  if not exists (
    select 1
    from public.re_review_items as item
    where item.identity_key = 'clothes|db7_full_existing'
      and item.reason = 'correction'
      and item.status = 'pending'
  ) or (select name from public.clothes where id = 'db7_full_existing') <> 'DB7 全字段测试正式资料' then
    raise exception 'DB7_FULL_ASSERT: formal conflict did not route without changing formal data';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"f8000000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

do $$
declare
  v_item_id uuid;
  v_queue jsonb;
  v_result jsonb;
  v_invalid_payload_denied boolean := false;
  v_candidate_payload jsonb := '{
    "name":"DB7 全字段测试资料甲",
    "game_id":"980001",
    "category":"连衣裙",
    "stars":5,
    "scores":{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0},
    "suit_id":null,
    "temp_suit_name":null,
    "tags":null,
    "needs_suit_review":false
  }'::jsonb;
begin
  select item.id into v_item_id
  from public.re_review_items as item
  where item.identity_key = 'entry|game|连衣裙|980001'
    and item.status = 'pending';

  v_queue := public.get_jury_review_queue();
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(v_queue) as queue_item(value)
    where queue_item.value->>'re_review_item_id' = v_item_id::text
      and (queue_item.value->>'can_submit_candidate')::boolean
      and pg_catalog.jsonb_array_length(queue_item.value->'issues') >= 4
  ) then
    raise exception 'DB7_FULL_ASSERT: queue omitted full issue context: %', v_queue;
  end if;

  begin
    perform public.submit_jury_candidate(
      v_item_id,
      v_candidate_payload || pg_catalog.jsonb_build_object(
        'scores', '{"simple":4305}'::jsonb
      )
    );
  exception when others then
    v_invalid_payload_denied := true;
  end;

  if not v_invalid_payload_denied then
    raise exception 'DB7_FULL_ASSERT: incomplete score payload was accepted';
  end if;

  v_result := public.submit_jury_candidate(v_item_id, v_candidate_payload);
  if v_result->>'candidate_status' <> 'voting' then
    raise exception 'DB7_FULL_ASSERT: full candidate did not enter voting: %', v_result;
  end if;

  v_result := public.submit_jury_candidate(v_item_id, v_candidate_payload);
  if coalesce((v_result->>'idempotent')::boolean, false) = false then
    raise exception 'DB7_FULL_ASSERT: identical candidate retry was not idempotent: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_candidate_id uuid;
  v_user_index integer;
  v_result jsonb;
  v_changed_vote_denied boolean := false;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  join public.re_review_items as item on item.id = candidate.re_review_item_id
  where item.identity_key = 'entry|game|连衣裙|980001'
    and candidate.status = 'voting';

  for v_user_index in 7..11 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'f8000000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );

    v_result := public.cast_jury_vote(v_candidate_id, 'approve');

    if (v_result->>'points_awarded')::integer <> 1 then
      raise exception 'DB7_FULL_ASSERT: first valid vote did not award +1: %', v_result;
    end if;

    if v_user_index = 7 then
      v_result := public.cast_jury_vote(v_candidate_id, 'approve');
      if (v_result->>'points_awarded')::integer <> 0 then
        raise exception 'DB7_FULL_ASSERT: identical vote retry duplicated points: %', v_result;
      end if;

      begin
        perform public.cast_jury_vote(v_candidate_id, 'reject');
      exception when others then
        v_changed_vote_denied := true;
      end;
    end if;
  end loop;

  if not v_changed_vote_denied or v_result->>'status' <> 'approved' then
    raise exception 'DB7_FULL_ASSERT: immutable vote or approval threshold failed: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_candidate_id uuid;
  v_clothes_id text;
begin
  select candidate.id, item.clothes_id
    into v_candidate_id, v_clothes_id
  from public.re_review_candidates as candidate
  join public.re_review_items as item on item.id = candidate.re_review_item_id
  where item.identity_key = 'entry|game|连衣裙|980001'
    and candidate.status = 'approved';

  if v_clothes_id is not null then
    raise exception 'DB7_FULL_ASSERT: new clothes id should remain on result, not source item';
  end if;

  select contribution.clothes_id into v_clothes_id
  from public.clothing_contributions as contribution
  where contribution.event_id = v_candidate_id
  order by contribution.contribution_rank
  limit 1;

  if v_clothes_id is null
    or (select pg_catalog.count(*) from public.jury_votes where candidate_id = v_candidate_id) <> 5
    or (select pg_catalog.count(*) from public.points_ledger where jury_vote_id in (select id from public.jury_votes where candidate_id = v_candidate_id) and delta = 1) <> 5
    or not exists (select 1 from public.points_ledger where re_review_candidate_id = v_candidate_id and delta = 8)
    or (select pg_catalog.count(*) from public.clothing_contributions where event_id = v_candidate_id and contribution_type = 'jury_resolution') <> 3
    or (select pg_catalog.count(*) from public.points_ledger as ledger join public.clothing_contributions as contribution on contribution.id = ledger.source_id where contribution.event_id = v_candidate_id and ledger.delta = 10) <> 3
    or (select pg_catalog.count(*) from public.pending_clothes where game_id = '980001' and status = 'approved') <> 3
    or (select pg_catalog.count(*) from public.pending_clothes where game_id = '980001' and status = 'rejected') <> 3 then
    raise exception 'DB7_FULL_ASSERT: approval rewards or source settlement were incorrect';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"f8000000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);

do $$
declare
  v_item_id uuid;
  v_result jsonb;
begin
  select item.id into v_item_id
  from public.re_review_items as item
  where item.identity_key = 'clothes|db7_full_existing'
    and item.status = 'pending';

  v_result := public.submit_jury_candidate(
    v_item_id,
    '{
      "name":"DB7 全字段测试正式资料修正",
      "game_id":"980002",
      "category":"连衣裙",
      "stars":5,
      "scores":{"simple":4305,"gorgeous":0,"active":4305,"elegant":0,"cute":4305,"mature":0,"pure":4305,"sexy":0,"cool":4305,"warm":0},
      "suit_id":null,
      "temp_suit_name":null,
      "tags":null,
      "needs_suit_review":false
    }'::jsonb
  );

  if v_result->>'candidate_status' <> 'voting' then
    raise exception 'DB7_FULL_ASSERT: formal correction did not enter voting: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_candidate_id uuid;
  v_user_index integer;
  v_stale_denied boolean := false;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  join public.re_review_items as item on item.id = candidate.re_review_item_id
  where item.identity_key = 'clothes|db7_full_existing'
    and candidate.status = 'voting';

  for v_user_index in 7..10 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'f8000000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );
    perform public.cast_jury_vote(v_candidate_id, 'approve');
  end loop;

  update public.clothes
  set tags = 'DB7 外部变化'
  where id = 'db7_full_existing';

  perform pg_catalog.set_config(
    'request.jwt.claims',
    '{"sub":"f8000000-0000-4000-8000-000000000011","role":"authenticated"}',
    true
  );

  begin
    perform public.cast_jury_vote(v_candidate_id, 'approve');
  exception when others then
    if sqlerrm like '%正式服装已变化%' then
      v_stale_denied := true;
    else
      raise;
    end if;
  end;

  if not v_stale_denied
    or exists (
      select 1
      from public.jury_votes as vote
      where vote.candidate_id = v_candidate_id
        and vote.user_id = 'f8000000-0000-4000-8000-000000000011'::uuid
    ) then
    raise exception 'DB7_FULL_ASSERT: stale formal change did not roll back terminal vote';
  end if;

  update public.clothes
  set tags = null
  where id = 'db7_full_existing';

  perform public.cast_jury_vote(v_candidate_id, 'approve');

  if (select name from public.clothes where id = 'db7_full_existing') <> 'DB7 全字段测试正式资料修正'
    or (select game_id from public.clothes where id = 'db7_full_existing') <> '980002'
    or (select tags from public.clothes where id = 'db7_full_existing') is not null
    or not exists (
      select 1
      from public.re_review_items as item
      where item.identity_key = 'clothes|db7_full_existing'
        and item.status = 'approved'
    ) then
    raise exception 'DB7_FULL_ASSERT: approved formal correction changed unexpected fields';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'five_user_conflict_routing', true,
  'formal_conflict_routing', true,
  'active_review_reused', true,
  'active_identity_unique', true,
  'multi_field_issue_list', true,
  'full_candidate_and_retry', true,
  'juror_reward_plus_one', true,
  'vote_retry_no_duplicate', true,
  'vote_change_denied', true,
  'candidate_reward_plus_eight', true,
  'matching_sources_plus_ten', true,
  'stale_formal_change_denied', true,
  'listed_formal_change_only', true,
  'fixture_rollback_pending', true
) as db7_full_review_verification;

rollback;
