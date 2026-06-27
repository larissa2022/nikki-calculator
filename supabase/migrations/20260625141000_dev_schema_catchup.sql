create table if not exists public.app_errors (
  id uuid primary key default gen_random_uuid(),
  created_at timestamp with time zone not null default timezone('utc'::text, now()),
  user_id uuid,
  action_name text,
  error_message text,
  error_stack text,
  user_agent text
);

create table if not exists public.suits (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  source text,
  created_at timestamp with time zone default now()
);

alter table public.clothes
  add column if not exists suit_id uuid,
  add column if not exists temp_suit_name text;

alter table public.pending_clothes
  add column if not exists category text,
  add column if not exists stars integer,
  add column if not exists scores jsonb,
  add column if not exists tags text,
  add column if not exists suit_name text,
  add column if not exists game_id text,
  add column if not exists status text default 'pending',
  add column if not exists submitted_by uuid,
  add column if not exists suit_id uuid,
  add column if not exists temp_suit_name text;

create table if not exists public.pending_suits (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  submitted_by uuid,
  status text default 'pending',
  created_at timestamp with time zone default now()
);

alter table public.profiles
  add column if not exists created_at timestamp with time zone default timezone('utc'::text, now()),
  add column if not exists username text,
  add column if not exists total_points integer default 0,
  add column if not exists current_month_points integer default 0,
  add column if not exists monthly_action_count integer default 0;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'clothes_suit_id_fkey'
  ) then
    alter table public.clothes
      add constraint clothes_suit_id_fkey
      foreign key (suit_id) references public.suits(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'pending_clothes_suit_id_fkey'
  ) then
    alter table public.pending_clothes
      add constraint pending_clothes_suit_id_fkey
      foreign key (suit_id) references public.suits(id) on delete set null;
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'pending_clothes_submitted_by_fkey'
  ) then
    alter table public.pending_clothes
      add constraint pending_clothes_submitted_by_fkey
      foreign key (submitted_by) references auth.users(id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'pending_suits_submitted_by_fkey'
  ) then
    alter table public.pending_suits
      add constraint pending_suits_submitted_by_fkey
      foreign key (submitted_by) references auth.users(id);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'suits_name_key'
  ) then
    alter table public.suits add constraint suits_name_key unique (name);
  end if;

  if not exists (
    select 1 from pg_constraint where conname = 'profiles_username_key'
  ) then
    alter table public.profiles add constraint profiles_username_key unique (username);
  end if;
end;
$$;

create index if not exists idx_clothes_suit_id on public.clothes using btree (suit_id);
create index if not exists idx_pending_clothes_status on public.pending_clothes using btree (status);
create index if not exists idx_pending_suits_status on public.pending_suits using btree (status);
create index if not exists idx_profiles_username on public.profiles using btree (username);
create index if not exists idx_suits_name on public.suits using btree (name);

alter table public.app_errors enable row level security;
alter table public.pending_suits enable row level security;

create or replace function public.is_super_admin()
returns boolean
language sql
security definer
as $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'super_admin');
$$;

create policy "Anyone can insert pending suits"
on public.pending_suits
for insert
with check (true);

create policy "Anyone can select and update pending suits"
on public.pending_suits
using (true);

create policy "允许任何人上报错误"
on public.app_errors
for insert
with check (true);

create policy "允许认证用户提交完整申请"
on public.pending_clothes
for insert
to authenticated
with check (true);

create policy "允许已登录用户读取档案"
on public.profiles
for select
to authenticated
using (true);

create policy "允许超管修改档案"
on public.profiles
for update
to authenticated
using (public.is_super_admin());

create or replace function public.deduct_user_quota(user_id_param uuid)
returns boolean
language plpgsql
security definer
as $$
declare
  current_quota integer;
begin
  select quota into current_quota from public.profiles where id = user_id_param;

  if current_quota is null or current_quota <= 0 then
    return false;
  end if;

  update public.profiles set quota = quota - 1 where id = user_id_param;
  return true;
end;
$$;

create or replace function public.auto_link_shadow_suits()
returns trigger
language plpgsql
as $$
begin
  update public.clothes
  set suit_id = new.id, temp_suit_name = null
  where temp_suit_name = new.name;

  update public.pending_clothes
  set suit_id = new.id, temp_suit_name = null
  where temp_suit_name = new.name;

  return new;
end;
$$;

drop trigger if exists trigger_auto_link_shadow_suits on public.suits;
create trigger trigger_auto_link_shadow_suits
after insert on public.suits
for each row
execute function public.auto_link_shadow_suits();
