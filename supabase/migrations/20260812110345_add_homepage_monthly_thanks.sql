begin;

create function private_db2.homepage_monthly_thanks()
returns table (
  month_start date,
  display_order integer,
  display_name text
)
language sql
stable
security definer
set search_path = ''
as $$
  with target_month as (
    select
      pg_catalog.date_trunc(
        'month',
        pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
      )::date as service_month
  ), eligible as (
    select
      candidate.source_month as month_start,
      candidate.user_id,
      pg_catalog.row_number() over (
        order by candidate.candidate_order
      )::integer as display_order
    from private_db2.admin_rotation_candidates as candidate
    join target_month
      on target_month.service_month = candidate.service_month
    join auth.users as account
      on account.id = candidate.user_id
    where candidate.source_month = (
      target_month.service_month - interval '1 month'
    )::date
      and candidate.qualifying_action_count >= 5
    order by candidate.candidate_order
    limit 10
  )
  select
    eligible.month_start,
    eligible.display_order,
    case
      when nullif(pg_catalog.btrim(profile.username), '') is not null
        then pg_catalog.btrim(profile.username)
      else '匿名搭配师-' || pg_catalog.upper(
        pg_catalog.substr(pg_catalog.md5(eligible.user_id::text), 1, 8)
      )
    end as display_name
  from eligible
  left join public.profiles as profile
    on profile.id = eligible.user_id
  order by eligible.display_order;
$$;

revoke all on function private_db2.homepage_monthly_thanks()
  from public, anon, authenticated, service_role;
grant execute on function private_db2.homepage_monthly_thanks()
  to anon, authenticated;

create view public.homepage_monthly_thanks
with (security_invoker = true, security_barrier = true)
as
select
  result.month_start,
  result.display_order,
  result.display_name
from private_db2.homepage_monthly_thanks() as result;

revoke all on table public.homepage_monthly_thanks
  from public, anon, authenticated, service_role;
grant select on table public.homepage_monthly_thanks
  to anon, authenticated;

comment on function private_db2.homepage_monthly_thanks() is
  'Return at most ten active users from the latest frozen Beijing month for public homepage thanks.';
comment on view public.homepage_monthly_thanks is
  'Anonymous-readable homepage thanks with only month, stable order, and current public display name.';

commit;
