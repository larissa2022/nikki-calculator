begin;

-- DB-11 correction evidence image and jury readback verification.
-- Run only against local Supabase or the explicitly authorized development project.
-- Every fixture write is rolled back.

do $$
begin
  if exists (
    select 1 from auth.users where email like 'db11-evidence-%@example.invalid'
  ) or exists (
    select 1 from public.clothes where id = 'db11_evidence_clothes'
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: fixture identifiers already exist';
  end if;

  if not pg_catalog.has_function_privilege(
    'authenticated',
    'public.submit_correction_request_with_evidence(varchar,jsonb,text)',
    'EXECUTE'
  ) or not pg_catalog.has_function_privilege(
    'authenticated',
    'public.get_jury_review_queue_with_evidence()',
    'EXECUTE'
  ) or pg_catalog.has_function_privilege(
    'anon',
    'public.submit_correction_request_with_evidence(varchar,jsonb,text)',
    'EXECUTE'
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: RPC privileges are incorrect';
  end if;

  if pg_catalog.has_function_privilege(
    'authenticated',
    'public.submit_correction_request(varchar,text,jsonb)',
    'EXECUTE'
  ) or pg_catalog.to_regprocedure('public.can_read_correction_evidence(text)') is not null
    or pg_catalog.to_regprocedure('public.can_delete_correction_evidence(text)') is not null
    or pg_catalog.to_regprocedure('private.can_read_correction_evidence(text)') is null
    or pg_catalog.to_regprocedure('private.can_delete_correction_evidence(text)') is null then
    raise exception 'DB11_EVIDENCE_ASSERT: legacy or internal evidence entry points are exposed';
  end if;

  if not exists (
    select 1
    from storage.buckets as bucket
    where bucket.id = 'correction-evidence'
      and not bucket.public
      and bucket.file_size_limit = 8388608
      and bucket.allowed_mime_types @> array['image/jpeg', 'image/png', 'image/webp']::text[]
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: private evidence bucket is misconfigured';
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
  ('d1100000-0000-4000-8000-' || pg_catalog.lpad(value::text, 12, '0'))::uuid,
  'authenticated',
  'authenticated',
  'db11-evidence-' || value || '@example.invalid',
  '',
  pg_catalog.now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{}'::jsonb,
  pg_catalog.now(),
  pg_catalog.now()
from pg_catalog.generate_series(1, 2) as fixture(value);

insert into public.clothes (
  id, name, category, game_id, stars, scores, tags, suit_id, temp_suit_name
)
values (
  'db11_evidence_clothes',
  'DB11 图鉴图片测试',
  '连衣裙',
  '994001',
  '5',
  '{"simple":3210,"gorgeous":0,"active":2870,"elegant":0,"cute":1980,"mature":0,"pure":1760,"sexy":0,"cool":1540,"warm":0}'::jsonb,
  null,
  null,
  null
);

insert into storage.objects (
  bucket_id,
  name,
  owner_id,
  metadata
)
values (
  'correction-evidence',
  'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png',
  'd1100000-0000-4000-8000-000000000001',
  '{"mimetype":"image/png","size":1024}'::jsonb
);

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1100000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  v_first jsonb;
  v_retry jsonb;
  v_request_id uuid;
  v_item_id uuid;
  v_wrong_path_denied boolean := false;
begin
  begin
    perform public.submit_correction_request_with_evidence(
      'db11_evidence_clothes',
      '{"stars":4}'::jsonb,
      'd1100000-0000-4000-8000-000000000002/d1100000-0000-4000-8000-000000000099.png'
    );
  exception when others then
    v_wrong_path_denied := true;
  end;

  if not v_wrong_path_denied then
    raise exception 'DB11_EVIDENCE_ASSERT: foreign evidence path was accepted';
  end if;

  v_first := public.submit_correction_request_with_evidence(
    'db11_evidence_clothes',
    '{"stars":4}'::jsonb,
    'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png'
  );
  v_request_id := (v_first->>'request_id')::uuid;
  v_item_id := (v_first->>'re_review_item_id')::uuid;

  if v_first->>'status' <> 'converted_to_re_review'
    or coalesce((v_first->>'idempotent')::boolean, true)
    or v_first->>'evidence_image_path'
      <> 'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png'
    or not exists (
      select 1
      from public.correction_requests as request
      where request.id = v_request_id
        and request.re_review_item_id = v_item_id
        and request.evidence_image_path = v_first->>'evidence_image_path'
    ) then
    raise exception 'DB11_EVIDENCE_ASSERT: evidence correction was not stored and routed';
  end if;

  v_retry := public.submit_correction_request_with_evidence(
    'db11_evidence_clothes',
    '{"stars":4}'::jsonb,
    'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png'
  );

  if not coalesce((v_retry->>'idempotent')::boolean, false)
    or (v_retry->>'request_id')::uuid is distinct from v_request_id
    or (select pg_catalog.count(*) from public.correction_requests where id = v_request_id) <> 1 then
    raise exception 'DB11_EVIDENCE_ASSERT: identical retry duplicated correction facts';
  end if;

  if exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.get_jury_review_queue_with_evidence()) as queue(item)
    where (queue.item->>'re_review_item_id')::uuid = v_item_id
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: reporter can review own correction evidence';
  end if;

  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.get_my_correction_requests()) as request(item)
    where (request.item->>'request_id')::uuid = v_request_id
      and request.item->>'evidence_image_path' = v_first->>'evidence_image_path'
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: reporter history omitted evidence path';
  end if;
end;
$$;

select pg_catalog.set_config(
  'request.jwt.claims',
  '{"sub":"d1100000-0000-4000-8000-000000000002","role":"authenticated"}',
  true
);

do $$
begin
  if not exists (
    select 1
    from pg_catalog.jsonb_array_elements(public.get_jury_review_queue_with_evidence()) as queue(item)
    cross join lateral pg_catalog.jsonb_array_elements(queue.item->'correction_evidence') as evidence(value)
    where queue.item->>'clothes_id' = 'db11_evidence_clothes'
      and evidence.value->>'field_key' = 'stars'
      and evidence.value->>'evidence_image_path'
        = 'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png'
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: jury queue omitted evidence image';
  end if;
end;
$$;

set local role authenticated;

do $$
begin
  if not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = 'correction-evidence'
      and object.name = 'd1100000-0000-4000-8000-000000000001/d1100000-0000-4000-8000-000000000091.png'
  ) then
    raise exception 'DB11_EVIDENCE_ASSERT: authenticated juror cannot read referenced image';
  end if;
end;
$$;

reset role;

rollback;
