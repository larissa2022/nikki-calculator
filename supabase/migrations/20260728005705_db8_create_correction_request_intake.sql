begin;

create table public.correction_requests (
  id uuid primary key default gen_random_uuid(),
  clothes_id varchar not null references public.clothes(id) on delete restrict,
  reported_by uuid references auth.users(id) on delete set null,
  field_key text not null,
  reason text not null,
  proposed_patch jsonb not null,
  clothes_snapshot jsonb not null,
  status text not null default 'pending',
  reviewed_by uuid references auth.users(id) on delete set null,
  resolution_note text,
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint correction_requests_field_key_check check (
    field_key in ('name', 'game_id', 'category', 'stars', 'scores', 'suit', 'tags', 'other')
  ),
  constraint correction_requests_reason_check check (
    char_length(btrim(reason)) between 10 and 1000
  ),
  constraint correction_requests_patch_check check (
    jsonb_typeof(proposed_patch) = 'object'
    and proposed_patch <> '{}'::jsonb
    and char_length(proposed_patch::text) <= 2000
  ),
  constraint correction_requests_snapshot_check check (
    jsonb_typeof(clothes_snapshot) = 'object'
    and clothes_snapshot <> '{}'::jsonb
  ),
  constraint correction_requests_status_check check (
    status in ('pending', 'reviewing', 'approved', 'rejected', 'converted_to_re_review')
  ),
  constraint correction_requests_review_shape_check check (
    (
      status = 'pending'
      and reviewed_by is null
      and reviewed_at is null
      and resolution_note is null
    )
    or (
      status <> 'pending'
      and reviewed_by is not null
      and reviewed_at is not null
      and nullif(btrim(coalesce(resolution_note, '')), '') is not null
    )
  )
);

comment on table public.correction_requests is
  'DB-8 正式服装报错受理事实；第一阶段只收集和展示本人进度，不自动修改正式库、不触发陪审团或积分。';

comment on column public.correction_requests.proposed_patch is
  '用户建议修改的单一字段对象；字段名必须与 field_key 一致。';

comment on column public.correction_requests.clothes_snapshot is
  '提交报错时的正式服装完整资料，用于后续核对，不替代 clothes 当前事实。';

alter table public.correction_requests enable row level security;

create index correction_requests_clothes_id_idx
  on public.correction_requests (clothes_id);

create index correction_requests_reported_by_created_at_idx
  on public.correction_requests (reported_by, created_at desc)
  where reported_by is not null;

create index correction_requests_reviewed_by_idx
  on public.correction_requests (reviewed_by)
  where reviewed_by is not null;

create index correction_requests_open_queue_idx
  on public.correction_requests (created_at, id)
  where status in ('pending', 'reviewing');

create unique index correction_requests_active_reporter_field_unique
  on public.correction_requests (clothes_id, reported_by, field_key)
  where reported_by is not null
    and status in ('pending', 'reviewing');

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
  v_reason text := btrim(coalesce(p_reason, ''));
  v_existing public.correction_requests%rowtype;
  v_request public.correction_requests%rowtype;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能提交图鉴报错';
  end if;

  if nullif(btrim(coalesce(p_clothes_id, '')), '') is null then
    raise exception '请选择需要报错的正式服装';
  end if;

  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 then
    raise exception '请用 10 到 1000 个字说明判断依据';
  end if;

  if jsonb_typeof(p_proposed_patch) is distinct from 'object' then
    raise exception '建议内容必须是字段对象';
  end if;

  select count(*)::integer, min(key)
    into v_field_count, v_field_key
  from jsonb_object_keys(p_proposed_patch) as proposed(key);

  if v_field_count <> 1
    or v_field_key not in ('name', 'game_id', 'category', 'stars', 'scores', 'suit', 'tags', 'other') then
    raise exception '每次请选择一个明确的问题字段';
  end if;

  v_proposed_value := p_proposed_patch->v_field_key;

  if jsonb_typeof(v_proposed_value) is distinct from 'string'
    or nullif(btrim(v_proposed_value #>> '{}'), '') is null
    or char_length(btrim(v_proposed_value #>> '{}')) > 500 then
    raise exception '建议内容需填写 1 到 500 个字';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'correction_request|' || v_user_id::text || '|' || btrim(p_clothes_id) || '|' || v_field_key,
      0
    )
  );

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = btrim(p_clothes_id)
  for key share;

  if not found then
    raise exception '正式图鉴中找不到这件服装，请刷新图鉴后重试';
  end if;

  select request.*
    into v_existing
  from public.correction_requests as request
  where request.clothes_id = v_clothes.id
    and request.reported_by = v_user_id
    and request.field_key = v_field_key
    and request.status in ('pending', 'reviewing')
  order by request.created_at, request.id
  limit 1
  for update;

  if found then
    if v_existing.reason is not distinct from v_reason
      and v_existing.proposed_patch is not distinct from p_proposed_patch then
      return jsonb_build_object(
        'request_id', v_existing.id,
        'status', v_existing.status,
        'idempotent', true
      );
    end if;

    raise exception '这件服装的同一字段已有待处理报错，请等待处理完成后再提交';
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
    jsonb_build_object(
      'id', v_clothes.id,
      'name', v_clothes.name,
      'game_id', v_clothes.game_id,
      'category', v_clothes.category,
      'stars', v_clothes.stars,
      'scores', v_clothes.scores,
      'suit_id', v_clothes.suit_id,
      'temp_suit_name', v_clothes.temp_suit_name,
      'tags', v_clothes.tags
    )
  )
  returning * into v_request;

  return jsonb_build_object(
    'request_id', v_request.id,
    'status', v_request.status,
    'idempotent', false
  );
end;
$$;

comment on function public.submit_correction_request(varchar, text, jsonb) is
  'DB-8：登录用户对正式服装提交单字段报错；同用户同服装同字段的相同重试幂等，内容不同则拒绝覆盖。';

create or replace function public.get_my_correction_requests()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能查看图鉴报错';
  end if;

  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'request_id', request.id,
        'clothes_id', request.clothes_id,
        'clothes_name', coalesce(clothes.name, request.clothes_snapshot->>'name', '已移除服装'),
        'game_id', coalesce(clothes.game_id, request.clothes_snapshot->>'game_id', ''),
        'category', coalesce(clothes.category, request.clothes_snapshot->>'category', ''),
        'field_key', request.field_key,
        'reason', request.reason,
        'proposed_patch', request.proposed_patch,
        'status', request.status,
        'resolution_note', request.resolution_note,
        'created_at', request.created_at,
        'updated_at', request.updated_at
      )
      order by request.created_at desc, request.id desc
    ),
    '[]'::jsonb
  )
    into v_result
  from public.correction_requests as request
  left join public.clothes as clothes on clothes.id = request.clothes_id
  where request.reported_by = v_user_id;

  return v_result;
end;
$$;

comment on function public.get_my_correction_requests() is
  'DB-8：只返回当前登录用户本人提交的正式服装报错和处理状态。';

revoke all on table public.correction_requests from public, anon, authenticated;
grant select, insert, update on table public.correction_requests to service_role;

revoke all on function public.submit_correction_request(varchar, text, jsonb)
  from public, anon, authenticated;
grant execute on function public.submit_correction_request(varchar, text, jsonb)
  to authenticated, service_role;

revoke all on function public.get_my_correction_requests()
  from public, anon, authenticated;
grant execute on function public.get_my_correction_requests()
  to authenticated, service_role;

commit;
