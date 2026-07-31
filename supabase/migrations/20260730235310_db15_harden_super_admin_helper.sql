-- DB-15 安全补丁：收紧复用的超级管理员 helper。
begin;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles as profile
    where profile.id = (select auth.uid())
      and (profile.role_level = 2 or profile.role = 'super_admin')
  );
$$;

revoke all on function public.is_super_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.is_super_admin()
  to authenticated, service_role;

comment on function public.is_super_admin() is
  'DB-15 privileged helper with empty search_path; checks only the compatible super-admin profile fact.';

commit;
