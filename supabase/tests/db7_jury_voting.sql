begin;

-- DB-7 jury voting verification. Every fixture write is rolled back.
-- Run only against local Supabase or the explicitly authorized development project.

do $$
begin
  if exists (
    select 1
    from auth.users
    where id between 'db700000-0000-4000-8000-000000000001'::uuid
      and 'db700000-0000-4000-8000-000000000010'::uuid
  ) or exists (
    select 1 from public.clothes where name like 'DB7 陪审团测试%'
  ) then
    raise exception 'DB7_JURY_ASSERT: fixture identifiers already exist';
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
  ('db700000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db7-jury-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 10) as fixture(value);

update public.profiles
set role = 'super_admin', role_level = 2
where id = 'db700000-0000-4000-8000-000000000009'::uuid;

insert into public.suits (id, name)
values
  ('db700000-0000-4000-8000-000000000090'::uuid, 'DB7 陪审团测试通过套装'),
  ('db700000-0000-4000-8000-000000000091'::uuid, 'DB7 陪审团测试退回套装'),
  ('db700000-0000-4000-8000-000000000092'::uuid, 'DB7 陪审团测试终审套装');

insert into public.clothes (
  id, name, category, game_id, stars, scores, suit_id, temp_suit_name, tags
)
values
  ('db7_jury_clothes_approve', 'DB7 陪审团测试通过', 'DB7 测试分类', '970001', '5', '{"简约":100}'::jsonb, null, null, null),
  ('db7_jury_clothes_return', 'DB7 陪审团测试退回', 'DB7 测试分类', '970002', '4', '{"简约":90}'::jsonb, null, null, null),
  ('db7_jury_clothes_admin', 'DB7 陪审团测试终审', 'DB7 测试分类', '970003', '3', '{"简约":80}'::jsonb, null, null, null);

insert into public.re_review_items (
  id, reason, status, clothes_id, payload, submitted_by
)
values
  (
    'db700000-0000-4000-8000-000000000080'::uuid,
    'missing_suit',
    'pending',
    'db7_jury_clothes_approve',
    '{"name":"DB7 陪审团测试通过","category":"DB7 测试分类","game_id":"970001","needs_suit_review":true}'::jsonb,
    'db700000-0000-4000-8000-000000000001'::uuid
  ),
  (
    'db700000-0000-4000-8000-000000000081'::uuid,
    'missing_suit',
    'pending',
    'db7_jury_clothes_return',
    '{"name":"DB7 陪审团测试退回","category":"DB7 测试分类","game_id":"970002","needs_suit_review":true}'::jsonb,
    'db700000-0000-4000-8000-000000000001'::uuid
  ),
  (
    'db700000-0000-4000-8000-000000000082'::uuid,
    'missing_suit',
    'pending',
    'db7_jury_clothes_admin',
    '{"name":"DB7 陪审团测试终审","category":"DB7 测试分类","game_id":"970003","needs_suit_review":true}'::jsonb,
    'db700000-0000-4000-8000-000000000001'::uuid
  );

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.submit_jury_candidate(
      'db700000-0000-4000-8000-000000000080'::uuid,
      '{"suit_id":"db700000-0000-4000-8000-000000000090"}'::jsonb
    );
  exception when others then
    v_denied := true;
  end;

  if not v_denied then
    raise exception 'DB7_JURY_ASSERT: source user submitted own candidate';
  end if;
end;
$$;

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);
set local role authenticated;

select public.submit_jury_candidate(
  'db700000-0000-4000-8000-000000000080'::uuid,
  '{"suit_id":"db700000-0000-4000-8000-000000000090"}'::jsonb
);

select public.submit_jury_candidate(
  'db700000-0000-4000-8000-000000000081'::uuid,
  '{"suit_id":"db700000-0000-4000-8000-000000000091"}'::jsonb
);

select public.submit_jury_candidate(
  'db700000-0000-4000-8000-000000000082'::uuid,
  '{"suit_id":"db700000-0000-4000-8000-000000000092"}'::jsonb
);

do $$
declare
  v_denied boolean := false;
  v_candidate_id uuid;
begin
  select candidate.id
    into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000080'::uuid
    and candidate.status = 'voting';

  begin
    perform public.cast_jury_vote(v_candidate_id, 'approve');
  exception when others then
    v_denied := true;
  end;

  if not v_denied then
    raise exception 'DB7_JURY_ASSERT: candidate author voted own candidate';
  end if;
end;
$$;

reset role;

update public.profiles
set role = 'super_admin', role_level = 2
where id = 'db700000-0000-4000-8000-000000000002'::uuid;

set local role authenticated;

do $$
declare
  v_candidate_id uuid;
  v_denied boolean := false;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000082'::uuid
    and candidate.status = 'voting';

  begin
    perform public.admin_reject_jury_candidate(v_candidate_id, '候选提交者不应终审自己的候选');
  exception when others then
    v_denied := sqlstate = '42501';
  end;

  if not v_denied then
    raise exception 'DB7_JURY_ASSERT: candidate author performed admin terminal review';
  end if;
end;
$$;

reset role;

update public.profiles
set role = 'user', role_level = 0
where id = 'db700000-0000-4000-8000-000000000002'::uuid;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_candidate_id uuid;
  v_result jsonb;
  v_changed_vote_denied boolean := false;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000080'::uuid
    and candidate.status = 'voting';

  v_result := public.cast_jury_vote(v_candidate_id, 'approve');
  if v_result->>'status' <> 'voting'
    or (v_result->>'approve_count')::integer <> 1 then
    raise exception 'DB7_JURY_ASSERT: first approval did not stay voting: %', v_result;
  end if;

  v_result := public.cast_jury_vote(v_candidate_id, 'approve');
  if (v_result->>'approve_count')::integer <> 1 then
    raise exception 'DB7_JURY_ASSERT: identical retry created a duplicate vote: %', v_result;
  end if;

  begin
    perform public.cast_jury_vote(v_candidate_id, 'reject');
  exception when others then
    v_changed_vote_denied := true;
  end;

  if not v_changed_vote_denied then
    raise exception 'DB7_JURY_ASSERT: vote change was allowed';
  end if;
end;
$$;

reset role;

do $$
declare
  v_user_index integer;
  v_candidate_id uuid;
  v_result jsonb;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000080'::uuid
    and candidate.status = 'voting';

  for v_user_index in 4..7 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'db700000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );
    v_result := public.cast_jury_vote(v_candidate_id, 'approve');
  end loop;

  if v_result->>'status' <> 'approved'
    or (v_result->>'approve_count')::integer <> 5
    or (select suit_id from public.clothes where id = 'db7_jury_clothes_approve')
      is distinct from 'db700000-0000-4000-8000-000000000090'::uuid
    or not exists (
      select 1
      from public.re_review_items
      where id = 'db700000-0000-4000-8000-000000000080'::uuid
        and status = 'approved'
    )
    or not exists (
      select 1
      from public.re_review_candidates
      where id = v_candidate_id
        and status = 'approved'
    )
    or not exists (
      select 1
      from public.points_ledger
      where re_review_candidate_id = v_candidate_id
        and user_id = 'db700000-0000-4000-8000-000000000002'::uuid
        and delta = 8
        and source_type = 're_review_candidate'
    ) then
    raise exception 'DB7_JURY_ASSERT: approval branch did not close atomically: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000003","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_candidate_id uuid;
  v_result jsonb;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000080'::uuid
    and candidate.status = 'approved';

  v_result := public.cast_jury_vote(v_candidate_id, 'approve');
  if v_result->>'status' <> 'approved'
    or (v_result->>'approve_count')::integer <> 5 then
    raise exception 'DB7_JURY_ASSERT: committed approval retry was not idempotent: %', v_result;
  end if;
end;
$$;

reset role;

do $$
declare
  v_user_index integer;
  v_candidate_id uuid;
  v_result jsonb;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000081'::uuid
    and candidate.status = 'voting';

  for v_user_index in 3..5 loop
    perform pg_catalog.set_config(
      'request.jwt.claims',
      pg_catalog.jsonb_build_object(
        'sub', 'db700000-0000-4000-8000-' || pg_catalog.lpad(v_user_index::text, 12, '0'),
        'role', 'authenticated'
      )::text,
      true
    );
    v_result := public.cast_jury_vote(v_candidate_id, 'reject');
  end loop;

  if v_result->>'status' <> 'returned'
    or (v_result->>'reject_count')::integer <> 3
    or (select suit_id from public.clothes where id = 'db7_jury_clothes_return') is not null
    or not exists (
      select 1
      from public.re_review_items
      where id = 'db700000-0000-4000-8000-000000000081'::uuid
        and status = 'pending'
        and resolved_at is null
    )
    or not exists (
      select 1
      from public.re_review_candidates
      where id = v_candidate_id
        and status = 'returned'
    )
    or exists (
      select 1
      from public.points_ledger
      where re_review_candidate_id = v_candidate_id
    ) then
    raise exception 'DB7_JURY_ASSERT: return-to-review branch changed formal data or closed item: %', v_result;
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000006","role":"authenticated"}',
  true
);
set local role authenticated;

select public.submit_jury_candidate(
  'db700000-0000-4000-8000-000000000081'::uuid,
  '{"suit_id":"db700000-0000-4000-8000-000000000091"}'::jsonb
);

reset role;
select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"db700000-0000-4000-8000-000000000009","role":"authenticated"}',
  true
);
set local role authenticated;

do $$
declare
  v_candidate_id uuid;
  v_returned_candidate_id uuid;
  v_stale_denied boolean := false;
  v_result jsonb;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000081'::uuid
    and candidate.status = 'voting';

  select candidate.id into v_returned_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000081'::uuid
    and candidate.status = 'returned';

  begin
    perform public.admin_reject_jury_candidate(v_returned_candidate_id, '旧轮次不应覆盖当前候选');
  exception when others then
    v_stale_denied := true;
  end;

  if not v_stale_denied then
    raise exception 'DB7_JURY_ASSERT: stale returned candidate overrode active round';
  end if;

  v_result := public.admin_reject_jury_candidate(v_candidate_id, '候选仍无法解决来源冲突');

  if v_result->>'status' <> 'rejected'
    or (select suit_id from public.clothes where id = 'db7_jury_clothes_return') is not null
    or not exists (
      select 1
      from public.re_review_items
      where id = 'db700000-0000-4000-8000-000000000081'::uuid
        and status = 'rejected'
        and resolved_by = 'db700000-0000-4000-8000-000000000009'::uuid
    ) then
    raise exception 'DB7_JURY_ASSERT: admin terminal rejection was not isolated: %', v_result;
  end if;
end;
$$;

do $$
declare
  v_candidate_id uuid;
  v_denied boolean := false;
begin
  select candidate.id into v_candidate_id
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000082'::uuid
    and candidate.status = 'voting';

  perform public.cast_jury_vote(v_candidate_id, 'reject');

  begin
    perform public.admin_reject_jury_candidate(v_candidate_id, '不应允许投票后终审');
  exception when others then
    v_denied := true;
  end;

  if not v_denied
    or not exists (
      select 1
      from public.re_review_items
      where id = 'db700000-0000-4000-8000-000000000082'::uuid
        and status = 'voting'
    ) then
    raise exception 'DB7_JURY_ASSERT: voting admin also performed terminal review';
  end if;
end;
$$;

do $$
declare
  v_queue jsonb;
begin
  v_queue := public.get_jury_review_queue();
  if pg_catalog.jsonb_array_length(v_queue) = 0 then
    raise exception 'DB7_JURY_ASSERT: eligible queue was empty';
  end if;
end;
$$;

reset role;

do $$
begin
  if not exists (
    select 1
    from public.jury_admin_decisions as decision
    join public.re_review_candidates as candidate on candidate.id = decision.candidate_id
    where candidate.re_review_item_id = 'db700000-0000-4000-8000-000000000081'::uuid
      and decision.decision = 'rejected'
  ) then
    raise exception 'DB7_JURY_ASSERT: independent admin decision was not recorded';
  end if;
end;
$$;

select pg_catalog.set_config('request.jwt.claims', '{}', true);

do $$
declare
  v_denied boolean := false;
begin
  begin
    perform public.get_jury_review_queue();
  exception when others then
    v_denied := true;
  end;

  if not v_denied then
    raise exception 'DB7_JURY_ASSERT: anonymous queue access was allowed';
  end if;
end;
$$;

do $$
begin
  if has_table_privilege('authenticated', 'public.jury_votes', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.jury_votes', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('authenticated', 'public.jury_admin_decisions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_table_privilege('anon', 'public.jury_admin_decisions', 'SELECT,INSERT,UPDATE,DELETE')
    or has_column_privilege('authenticated', 'public.re_review_candidates', 'status', 'INSERT')
    or has_table_privilege('authenticated', 'public.re_review_candidates', 'INSERT')
    or has_function_privilege('anon', 'public.submit_jury_candidate(uuid,jsonb)', 'EXECUTE')
    or has_function_privilege('anon', 'public.get_jury_review_queue()', 'EXECUTE')
    or has_function_privilege('anon', 'public.cast_jury_vote(uuid,text)', 'EXECUTE')
    or has_function_privilege('anon', 'public.admin_reject_jury_candidate(uuid,text)', 'EXECUTE') then
    raise exception 'DB7_JURY_ASSERT: grants widened beyond RPC boundary';
  end if;
end;
$$;

select pg_catalog.jsonb_build_object(
  'status', 'passed',
  'one_person_one_vote', true,
  'same_vote_retry_idempotent', true,
  'approve_threshold', true,
  'return_to_review_threshold', true,
  'other_state_continues_voting', true,
  'formal_write_only_on_approval', true,
  'candidate_reward_ledger', true,
  'admin_terminal_separate', true,
  'admin_vote_conflict_denied', true,
  'candidate_author_admin_denied', true,
  'stale_round_admin_denied', true,
  'source_self_review_denied', true,
  'anonymous_denied', true,
  'fixture_rollback_pending', true
) as db7_jury_verification;

rollback;
