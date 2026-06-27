alter table public.profiles
  add column if not exists role_level smallint;

create or replace function public.profile_role_to_level(p_role text)
returns smallint
language sql
immutable
as $$
  select case p_role
    when 'super_admin' then 2::smallint
    when 'admin' then 1::smallint
    else 0::smallint
  end;
$$;

create or replace function public.profile_role_level_to_text(p_role_level smallint)
returns text
language sql
immutable
as $$
  select case p_role_level
    when 2 then 'super_admin'
    when 1 then 'admin'
    else 'user'
  end;
$$;

update public.profiles
set role_level = public.profile_role_to_level(role)
where role_level is null
   or role_level is distinct from public.profile_role_to_level(role);

alter table public.profiles
  alter column role_level set default 0,
  alter column role_level set not null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'profiles_role_level_check'
  ) then
    alter table public.profiles
      add constraint profiles_role_level_check
      check (role_level in (0, 1, 2));
  end if;
end;
$$;

create or replace function public.sync_profile_role_fields()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    if new.role_level is null then
      new.role_level := public.profile_role_to_level(new.role);
    end if;

    new.role := public.profile_role_level_to_text(new.role_level);
    return new;
  end if;

  if new.role_level is distinct from old.role_level then
    new.role := public.profile_role_level_to_text(new.role_level);
  elsif new.role is distinct from old.role then
    new.role_level := public.profile_role_to_level(new.role);
  else
    new.role := public.profile_role_level_to_text(new.role_level);
  end if;

  return new;
end;
$$;

drop trigger if exists sync_profile_role_fields on public.profiles;

create trigger sync_profile_role_fields
before insert or update of role, role_level
on public.profiles
for each row
execute function public.sync_profile_role_fields();

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, nickname, role, role_level, quota)
  values (new.id, new.email, split_part(new.email, '@', 1), 'user', 0, 30);
  return new;
end;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles
    where id = auth.uid()
      and (role_level = 2 or role = 'super_admin')
  );
$$;

create or replace function public.is_admin_or_super_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles
    where id = auth.uid()
      and (
        role_level in (1, 2)
        or role in ('admin', 'super_admin')
      )
  );
$$;

revoke all on function public.profile_role_to_level(text) from public;
grant execute on function public.profile_role_to_level(text) to authenticated, service_role;

revoke all on function public.profile_role_level_to_text(smallint) from public;
grant execute on function public.profile_role_level_to_text(smallint) to authenticated, service_role;

revoke all on function public.sync_profile_role_fields() from public;

revoke all on function public.is_super_admin() from public;
grant execute on function public.is_super_admin() to authenticated;

revoke all on function public.is_admin_or_super_admin() from public;
grant execute on function public.is_admin_or_super_admin() to authenticated;
