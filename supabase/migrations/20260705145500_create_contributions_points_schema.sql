-- Database PR draft only.
-- Do not run this migration until development verification, backup planning,
-- and product review are complete.

-- Confirmed business key for clothes entries: category + game_id.
-- This partial unique index protects complete business keys while leaving
-- historical incomplete rows outside the constraint.
create unique index if not exists clothes_category_game_id_unique
on public.clothes (category, game_id)
where nullif(trim(category), '') is not null
  and nullif(trim(game_id), '') is not null;

create table if not exists public.clothing_contributions (
  id uuid primary key default gen_random_uuid(),
  clothes_id varchar not null references public.clothes(id) on delete cascade,
  category text not null,
  game_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  contribution_type text not null,
  contribution_rank smallint not null,
  awarded_points integer not null,
  source_snapshot jsonb,
  created_at timestamptz not null default now(),

  constraint clothing_contributions_business_key_required
    check (
      nullif(trim(category), '') is not null
      and nullif(trim(game_id), '') is not null
    ),
  constraint clothing_contributions_type_check
    check (contribution_type in (
      'auto_entry',
      'admin_arbitration',
      'existing_field_completion'
    )),
  constraint clothing_contributions_awarded_points_check
    check (
      (contribution_type in ('auto_entry', 'admin_arbitration') and awarded_points = 10)
      or (contribution_type = 'existing_field_completion' and awarded_points = 5)
    ),
  constraint clothing_contributions_rank_check
    check (contribution_rank between 1 and 5),
  constraint clothing_contributions_unique_award
    unique (category, game_id, user_id, contribution_type),
  constraint clothing_contributions_unique_rank
    unique (category, game_id, contribution_type, contribution_rank)
);

create table if not exists public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  delta integer not null,
  status text not null default 'awarded',
  source_type text not null default 'clothing_contribution',
  source_id uuid not null references public.clothing_contributions(id) on delete restrict,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint points_ledger_status_awarded_only
    check (status = 'awarded'),
  constraint points_ledger_source_type_check
    check (source_type = 'clothing_contribution'),
  constraint points_ledger_nonzero_delta
    check (delta <> 0),
  constraint points_ledger_unique_source
    unique (source_type, source_id)
);

create index if not exists idx_clothing_contributions_clothes_id
on public.clothing_contributions (clothes_id);

create index if not exists idx_clothing_contributions_business_key
on public.clothing_contributions (category, game_id, contribution_rank);

create index if not exists idx_clothing_contributions_user_id
on public.clothing_contributions (user_id);

create index if not exists idx_points_ledger_user_occurred_at
on public.points_ledger (user_id, occurred_at desc);

create index if not exists idx_points_ledger_source_id
on public.points_ledger (source_id);

alter table public.clothing_contributions enable row level security;
alter table public.points_ledger enable row level security;

revoke all on table public.clothing_contributions from anon;
revoke all on table public.clothing_contributions from authenticated;
revoke all on table public.points_ledger from anon;
revoke all on table public.points_ledger from authenticated;

grant select on table public.points_ledger to authenticated;

create policy "users can read own points ledger"
on public.points_ledger
for select
to authenticated
using ((select auth.uid()) = user_id);

create or replace view public.clothing_contribution_public_view
with (security_invoker = true)
as
select
  cc.category,
  cc.game_id,
  cc.contribution_type,
  cc.contribution_rank,
  cc.awarded_points,
  cc.created_at,
  nullif(trim(p.nickname), '') as nickname,
  coalesce(
    nullif(trim(p.nickname), ''),
    nullif(trim(p.username), ''),
    '匿名搭配师'
  ) as display_name
from public.clothing_contributions cc
left join public.profiles p on p.id = cc.user_id;

create or replace view public.user_points_summary
with (security_invoker = true)
as
select
  coalesce(sum(pl.delta) filter (where pl.status = 'awarded'), 0)::integer as total_points
from public.points_ledger pl
where pl.user_id = (select auth.uid());

create or replace view public.monthly_points_summary
with (security_invoker = true)
as
select
  to_char(pl.occurred_at at time zone 'Asia/Shanghai', 'YYYY-MM') as month_utc8,
  coalesce(sum(pl.delta) filter (where pl.status = 'awarded'), 0)::integer as monthly_points
from public.points_ledger pl
where pl.user_id = (select auth.uid())
group by
  to_char(pl.occurred_at at time zone 'Asia/Shanghai', 'YYYY-MM');

grant select on public.clothing_contribution_public_view to anon, authenticated;
grant select on public.user_points_summary to authenticated;
grant select on public.monthly_points_summary to authenticated;

create or replace function public.get_clothing_contributors(
  p_category text,
  p_game_id text
)
returns table (
  category text,
  game_id text,
  contribution_type text,
  contribution_rank smallint,
  awarded_points integer,
  created_at timestamptz,
  nickname text,
  display_name text
)
language sql
stable
security invoker
set search_path = public
as $$
  select
    v.category,
    v.game_id,
    v.contribution_type,
    v.contribution_rank,
    v.awarded_points,
    v.created_at,
    v.nickname,
    v.display_name
  from public.clothing_contribution_public_view v
  where v.category = p_category
    and v.game_id = p_game_id
  order by v.contribution_rank asc, v.created_at asc
  limit 3
$$;

revoke all on function public.get_clothing_contributors(text, text) from public;
grant execute on function public.get_clothing_contributors(text, text) to anon, authenticated;
