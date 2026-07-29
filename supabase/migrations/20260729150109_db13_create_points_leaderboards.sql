begin;

create function private_db2.total_points_leaderboard()
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
  with scored as (
    select
      ledger.user_id,
      pg_catalog.sum(ledger.delta)::bigint as points
    from public.points_ledger as ledger
    where ledger.status = 'awarded'
      and ledger.user_id is not null
      and (select auth.uid()) is not null
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
  select
    ranked.leaderboard_rank,
    case
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(ranked.user_id::text), 1, 8)
      )
    end as display_name,
    ranked.points,
    ranked.user_id = (select auth.uid()) as is_current_user
  from ranked
  left join public.profiles as profile
    on profile.id = ranked.user_id
  order by ranked.leaderboard_rank, ranked.user_id;
$$;

create function private_db2.current_month_points_leaderboard()
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
  with month_boundary as (
    select (
      pg_catalog.date_trunc(
        'month',
        pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
      ) at time zone 'Asia/Shanghai'
    ) as starts_at
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
      and (select auth.uid()) is not null
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
  select
    ranked.leaderboard_rank,
    case
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(ranked.user_id::text), 1, 8)
      )
    end as display_name,
    ranked.points,
    ranked.user_id = (select auth.uid()) as is_current_user
  from ranked
  left join public.profiles as profile
    on profile.id = ranked.user_id
  order by ranked.leaderboard_rank, ranked.user_id;
$$;

revoke all on function private_db2.total_points_leaderboard()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.current_month_points_leaderboard()
  from public, anon, authenticated, service_role;

grant execute on function private_db2.total_points_leaderboard()
  to authenticated;
grant execute on function private_db2.current_month_points_leaderboard()
  to authenticated;

create view public.points_leaderboard_total
with (security_invoker = true, security_barrier = true)
as
select
  result.leaderboard_rank,
  result.display_name,
  result.points,
  result.is_current_user
from private_db2.total_points_leaderboard() as result;

create view public.points_leaderboard_current_month
with (security_invoker = true, security_barrier = true)
as
select
  result.leaderboard_rank,
  result.display_name,
  result.points,
  result.is_current_user
from private_db2.current_month_points_leaderboard() as result;

revoke all on table public.points_leaderboard_total
  from public, anon, authenticated, service_role;
revoke all on table public.points_leaderboard_current_month
  from public, anon, authenticated, service_role;

grant select on table public.points_leaderboard_total
  to authenticated;
grant select on table public.points_leaderboard_current_month
  to authenticated;

commit;
