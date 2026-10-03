begin;

-- DB-21: public core catalogs stay readable, but browser roles lose direct writes.
alter table public.stages enable row level security;
alter table public.stages force row level security;
alter table public.suits enable row level security;
alter table public.suits force row level security;
alter table public.pending_suits enable row level security;
alter table public.pending_suits force row level security;

drop policy if exists "DB21 public stages read" on public.stages;
create policy "DB21 public stages read"
on public.stages
for select
to anon, authenticated
using (true);

drop policy if exists "DB21 public suits read" on public.suits;
create policy "DB21 public suits read"
on public.suits
for select
to anon, authenticated
using (true);

drop policy if exists "Anyone can insert pending suits" on public.pending_suits;
drop policy if exists "Anyone can select and update pending suits" on public.pending_suits;
drop policy if exists "DB21 users read own pending suits" on public.pending_suits;
drop policy if exists "DB21 users submit own pending suits" on public.pending_suits;

create policy "DB21 users read own pending suits"
on public.pending_suits
for select
to authenticated
using (
  coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'false'
  and submitted_by = (select auth.uid())
);

create policy "DB21 users submit own pending suits"
on public.pending_suits
for insert
to authenticated
with check (
  coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'false'
  and submitted_by = (select auth.uid())
  and status = 'pending'
  and name = pg_catalog.btrim(name)
  and name <> ''
);

-- Explicit object grants are the first access boundary; RLS remains defense in depth.
revoke all on table public.stages from public, anon, authenticated, service_role;
revoke all on table public.suits from public, anon, authenticated, service_role;
revoke all on table public.pending_suits from public, anon, authenticated, service_role;

grant select on table public.stages to anon, authenticated;
grant select on table public.suits to anon, authenticated;
grant select on table public.pending_suits to authenticated;
grant insert (name, submitted_by) on table public.pending_suits to authenticated;

grant select, insert, update, delete on table public.stages to service_role;
grant select, insert, update, delete on table public.suits to service_role;
grant select, insert, update on table public.pending_suits to service_role;

revoke all on sequence public.stages_id_seq from public, anon, authenticated, service_role;
grant usage, select on sequence public.stages_id_seq to service_role;

drop index if exists public.idx_pending_suits_status;
create index idx_pending_suits_review_queue
  on public.pending_suits (status, name, created_at);

create or replace function public.list_pending_suits_for_review()
returns table (
  name text,
  request_count bigint,
  first_created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null
    or not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可查看套装审核队列';
  end if;

  return query
  select
    pending.name,
    pg_catalog.count(*)::bigint as request_count,
    pg_catalog.min(pending.created_at) as first_created_at
  from public.pending_suits as pending
  where pending.status = 'pending'
  group by pending.name
  order by request_count desc, first_created_at, pending.name;
end;
$$;

create or replace function public.review_pending_suit(
  p_name text,
  p_decision text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_name text := pg_catalog.btrim(coalesce(p_name, ''));
  v_decision text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_decision, '')));
  v_suit_id uuid;
  v_pending_count bigint := 0;
  v_approved_count bigint := 0;
  v_rejected_count bigint := 0;
  v_processed_count bigint := 0;
  v_suit_existed boolean := false;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null
    or not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可审核套装';
  end if;
  if v_name = '' then
    raise exception using errcode = '22023', message = '套装名称不能为空';
  end if;
  if v_decision not in ('approve', 'reject') then
    raise exception using errcode = '22023', message = '套装审核动作必须是 approve 或 reject';
  end if;

  -- One deterministic lock serializes approval/rejection and direct super-admin quick creation.
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('DB21:suit:' || v_name, 0)
  );

  select
    pg_catalog.count(*) filter (where pending.status = 'pending'),
    pg_catalog.count(*) filter (where pending.status = 'approved'),
    pg_catalog.count(*) filter (where pending.status = 'rejected')
  into v_pending_count, v_approved_count, v_rejected_count
  from public.pending_suits as pending
  where pending.name = v_name;

  select suit.id
  into v_suit_id
  from public.suits as suit
  where suit.name = v_name;
  v_suit_existed := found;

  if v_decision = 'approve' then
    if v_suit_id is null then
      insert into public.suits (name)
      values (v_name)
      on conflict (name) do nothing
      returning id into v_suit_id;

      if v_suit_id is null then
        select suit.id into strict v_suit_id
        from public.suits as suit
        where suit.name = v_name;
      end if;
    end if;

    update public.pending_suits
    set status = 'approved'
    where name = v_name
      and status = 'pending';
    get diagnostics v_processed_count = row_count;

    return pg_catalog.jsonb_build_object(
      'name', v_name,
      'decision', 'approved',
      'suit_id', v_suit_id,
      'processed_count', v_processed_count,
      'idempotent', v_suit_existed and v_processed_count = 0
    );
  end if;

  update public.pending_suits
  set status = 'rejected'
  where name = v_name
    and status = 'pending';
  get diagnostics v_processed_count = row_count;

  if v_processed_count = 0 then
    if v_rejected_count > 0 and v_approved_count = 0 then
      return pg_catalog.jsonb_build_object(
        'name', v_name,
        'decision', 'rejected',
        'suit_id', null,
        'processed_count', 0,
        'idempotent', true
      );
    end if;
    if v_approved_count > 0 then
      raise exception using errcode = '40001', message = '该套装申请已批准，不能改为驳回';
    end if;
    raise exception using errcode = 'P0002', message = '没有可驳回的待审核套装申请';
  end if;

  return pg_catalog.jsonb_build_object(
    'name', v_name,
    'decision', 'rejected',
    'suit_id', null,
    'processed_count', v_processed_count,
    'idempotent', false
  );
end;
$$;

revoke all on function public.list_pending_suits_for_review()
  from public, anon, authenticated, service_role;
grant execute on function public.list_pending_suits_for_review()
  to authenticated, service_role;

revoke all on function public.review_pending_suit(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.review_pending_suit(text, text)
  to authenticated, service_role;

comment on function public.list_pending_suits_for_review() is
  'DB-21 super-admin-only aggregated pending suit review queue; ordinary admins have no access.';
comment on function public.review_pending_suit(text, text) is
  'DB-21 atomic and retry-safe super-admin suit approval/rejection; approval also preserves controlled quick creation.';

commit;
