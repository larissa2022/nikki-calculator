begin;

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

create table private_db2.points_leaderboard_months (
  month_start date primary key,
  frozen_at timestamptz not null default pg_catalog.now(),
  row_count bigint not null default 0,

  constraint points_leaderboard_months_month_start_check
    check (
      month_start = pg_catalog.date_trunc('month', month_start::timestamp)::date
    ),
  constraint points_leaderboard_months_row_count_check
    check (row_count >= 0)
);

create table private_db2.points_leaderboard_monthly_snapshots (
  id bigint generated always as identity primary key,
  month_start date not null,
  user_id uuid,
  points bigint not null,
  leaderboard_rank bigint not null,
  frozen_at timestamptz not null,

  constraint points_leaderboard_monthly_snapshots_month_fkey
    foreign key (month_start)
    references private_db2.points_leaderboard_months (month_start)
    on delete cascade,
  constraint points_leaderboard_monthly_snapshots_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete set null,
  constraint points_leaderboard_monthly_snapshots_rank_check
    check (leaderboard_rank >= 1),
  constraint points_leaderboard_monthly_snapshots_month_user_key
    unique (month_start, user_id)
);

create index points_leaderboard_monthly_snapshots_user_id_idx
  on private_db2.points_leaderboard_monthly_snapshots (user_id);

create index points_leaderboard_monthly_snapshots_month_rank_idx
  on private_db2.points_leaderboard_monthly_snapshots (
    month_start,
    leaderboard_rank,
    user_id
  );

alter table private_db2.points_leaderboard_months enable row level security;
alter table private_db2.points_leaderboard_months force row level security;
alter table private_db2.points_leaderboard_monthly_snapshots enable row level security;
alter table private_db2.points_leaderboard_monthly_snapshots force row level security;

revoke all on table private_db2.points_leaderboard_months
  from public, anon, authenticated, service_role;
revoke all on table private_db2.points_leaderboard_monthly_snapshots
  from public, anon, authenticated, service_role;
revoke all on sequence private_db2.points_leaderboard_monthly_snapshots_id_seq
  from public, anon, authenticated, service_role;

create function private_db2.freeze_points_leaderboard_month(
  p_month_start date
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_current_month date;
  v_existing_count bigint;
  v_frozen_at timestamptz := pg_catalog.now();
  v_inserted_count bigint;
begin
  if p_month_start is null
    or p_month_start <> pg_catalog.date_trunc(
      'month',
      p_month_start::timestamp
    )::date then
    raise exception using
      errcode = '22023',
      message = '冻结月份必须是自然月首日';
  end if;

  v_current_month := pg_catalog.date_trunc(
    'month',
    pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  )::date;

  if p_month_start >= v_current_month then
    raise exception using
      errcode = '22023',
      message = '只能冻结已经结束的自然月';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'db14:points_leaderboard:' || p_month_start::text,
      0
    )
  );

  select frozen_month.row_count
  into v_existing_count
  from private_db2.points_leaderboard_months as frozen_month
  where frozen_month.month_start = p_month_start;

  if found then
    return v_existing_count;
  end if;

  insert into private_db2.points_leaderboard_months (
    month_start,
    frozen_at,
    row_count
  ) values (
    p_month_start,
    v_frozen_at,
    0
  );

  with month_boundary as (
    select
      p_month_start::timestamp at time zone 'Asia/Shanghai' as starts_at,
      (p_month_start + interval '1 month')::timestamp
        at time zone 'Asia/Shanghai' as ends_at
  ),
  scored as (
    select
      ledger.user_id,
      pg_catalog.sum(ledger.delta)::bigint as points
    from public.points_ledger as ledger
    cross join month_boundary
    where ledger.status = 'awarded'
      and ledger.user_id is not null
      and ledger.occurred_at >= month_boundary.starts_at
      and ledger.occurred_at < month_boundary.ends_at
    group by ledger.user_id
  ),
  ranked as (
    select
      scored.user_id,
      scored.points,
      pg_catalog.dense_rank() over (
        order by scored.points desc
      ) as leaderboard_rank
    from scored
  )
  insert into private_db2.points_leaderboard_monthly_snapshots (
    month_start,
    user_id,
    points,
    leaderboard_rank,
    frozen_at
  )
  select
    p_month_start,
    ranked.user_id,
    ranked.points,
    ranked.leaderboard_rank,
    v_frozen_at
  from ranked;

  get diagnostics v_inserted_count = row_count;

  update private_db2.points_leaderboard_months
  set row_count = v_inserted_count
  where month_start = p_month_start;

  return v_inserted_count;
end;
$$;

create function private_db2.freeze_previous_month_if_due(
  p_run_at timestamptz default pg_catalog.now()
)
returns bigint
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_local_date date;
  v_target_month date;
begin
  v_local_date := pg_catalog.timezone('Asia/Shanghai', p_run_at)::date;

  if extract(day from v_local_date) <> 1 then
    return 0;
  end if;

  v_target_month := (
    pg_catalog.date_trunc('month', v_local_date::timestamp) - interval '1 month'
  )::date;

  return private_db2.freeze_points_leaderboard_month(v_target_month);
end;
$$;

create function private_db2.last_month_points_leaderboard()
returns table (
  leaderboard_rank bigint,
  display_name text,
  points bigint,
  is_current_user boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  with target_month as (
    select (
      pg_catalog.date_trunc(
        'month',
        pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
      ) - interval '1 month'
    )::date as month_start
  )
  select
    snapshot.leaderboard_rank,
    case
      when snapshot.user_id is null then '已注销用户'
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(snapshot.user_id::text), 1, 8)
      )
    end as display_name,
    snapshot.points,
    snapshot.user_id = (select auth.uid()) as is_current_user
  from private_db2.points_leaderboard_monthly_snapshots as snapshot
  cross join target_month
  left join public.profiles as profile
    on profile.id = snapshot.user_id
  where snapshot.month_start = target_month.month_start
    and (select auth.uid()) is not null
  order by snapshot.leaderboard_rank, snapshot.id;
$$;

revoke all on function private_db2.freeze_points_leaderboard_month(date)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.freeze_previous_month_if_due(timestamptz)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.last_month_points_leaderboard()
  from public, anon, authenticated, service_role;

grant execute on function private_db2.last_month_points_leaderboard()
  to authenticated;

create view public.points_leaderboard_last_month
with (security_invoker = true, security_barrier = true)
as
select
  result.leaderboard_rank,
  result.display_name,
  result.points,
  result.is_current_user
from private_db2.last_month_points_leaderboard() as result;

revoke all on table public.points_leaderboard_last_month
  from public, anon, authenticated, service_role;

grant select on table public.points_leaderboard_last_month
  to authenticated;

comment on table private_db2.points_leaderboard_months is
  'DB-14 monthly leaderboard freeze marker, including empty months.';
comment on table private_db2.points_leaderboard_monthly_snapshots is
  'DB-14 frozen monthly points and dense rank. Display names remain live.';
comment on function private_db2.freeze_points_leaderboard_month(date) is
  'Freeze one completed Asia/Shanghai natural month exactly once.';
comment on function private_db2.freeze_previous_month_if_due(timestamptz) is
  'Daily cron entrypoint; freezes only on day 1 in Asia/Shanghai.';
comment on view public.points_leaderboard_last_month is
  'Authenticated-only latest completed Asia/Shanghai monthly leaderboard.';

select private_db2.freeze_points_leaderboard_month(
  (
    pg_catalog.date_trunc(
      'month',
      pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
    ) - interval '1 month'
  )::date
);

do $$
begin
  if exists (
    select 1
    from cron.job
    where jobname = 'db14-freeze-previous-month-leaderboard'
  ) then
    raise exception 'DB14 migration refuses to overwrite an existing cron job';
  end if;
end;
$$;

select cron.schedule(
  'db14-freeze-previous-month-leaderboard',
  '5 16 * * *',
  $command$select private_db2.freeze_previous_month_if_due();$command$
);

commit;
