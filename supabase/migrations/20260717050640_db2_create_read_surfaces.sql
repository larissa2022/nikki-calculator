begin;

create schema private_db2 authorization postgres;

revoke all on schema private_db2
  from public, anon, authenticated, service_role;

create function private_db2.current_user_points()
returns table (
  total_points bigint
)
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(ledger.delta), 0::bigint) as total_points
  from public.points_ledger as ledger
  where ledger.user_id = (select auth.uid())
    and ledger.status = 'awarded';
$$;

create function private_db2.public_initial_contributors()
returns table (
  clothes_id character varying,
  contribution_rank smallint,
  display_name text,
  contributed_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  with ranked_contributors as (
    select
      contribution.clothes_id,
      row_number() over (
        partition by contribution.clothes_id
        order by
          contribution.source_created_at,
          contribution.contribution_rank,
          contribution.created_at,
          contribution.id
      ) as stable_rank,
      case
        when contribution.user_id is null then '已注销用户'
        when nullif(btrim(profile.username), '') is not null
          then btrim(profile.username)
        else '匿名贡献者-' || substr(md5(contribution.user_id::text), 1, 8)
      end as display_name,
      contribution.source_created_at as contributed_at
    from public.clothing_contributions as contribution
    left join public.profiles as profile
      on profile.id = contribution.user_id
    where contribution.contribution_type in ('auto_entry', 'admin_arbitration')
  )
  select
    ranked.clothes_id,
    ranked.stable_rank::smallint as contribution_rank,
    ranked.display_name,
    ranked.contributed_at
  from ranked_contributors as ranked
  where ranked.stable_rank <= 3;
$$;

revoke all on function private_db2.current_user_points()
  from public, anon, authenticated, service_role;
revoke all on function private_db2.public_initial_contributors()
  from public, anon, authenticated, service_role;

grant usage on schema private_db2 to anon, authenticated;
grant execute on function private_db2.current_user_points()
  to authenticated;
grant execute on function private_db2.public_initial_contributors()
  to anon, authenticated;

create view public.user_points_summary
with (security_invoker = true, security_barrier = true)
as
select result.total_points
from private_db2.current_user_points() as result;

create view public.clothing_contributors_public
with (security_invoker = true, security_barrier = true)
as
select
  result.clothes_id,
  result.contribution_rank,
  result.display_name,
  result.contributed_at
from private_db2.public_initial_contributors() as result;

revoke all on table public.user_points_summary
  from public, anon, authenticated, service_role;
revoke all on table public.clothing_contributors_public
  from public, anon, authenticated, service_role;

grant select on table public.user_points_summary
  to authenticated;
grant select on table public.clothing_contributors_public
  to anon, authenticated;

commit;
