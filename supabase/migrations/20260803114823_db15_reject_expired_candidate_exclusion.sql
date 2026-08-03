begin;

create or replace function public.create_admin_candidate_exclusion(
  p_user_id uuid, p_reason text, p_starts_at timestamptz, p_ends_at timestamptz
)
returns uuid
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare v_id uuid; v_term public.admin_terms%rowtype;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可维护候选排除';
  end if;
  if p_user_id is null or nullif(pg_catalog.btrim(coalesce(p_reason, '')), '') is null
    or p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception using errcode = '22023', message = '排除用户、原因和有效期必须完整';
  end if;
  if p_ends_at <= pg_catalog.now() then
    raise exception using errcode = '22023', message = '排除结束时间必须晚于当前时间';
  end if;

  insert into public.admin_candidate_exclusions (
    user_id, reason, starts_at, ends_at, created_by
  ) values (
    p_user_id, pg_catalog.btrim(p_reason), p_starts_at, p_ends_at, (select auth.uid())
  ) returning id into v_id;

  select * into v_term from private_db2.current_admin_term(p_user_id);
  if v_term.source = 'monthly' then
    update public.admin_terms set status = 'revoked', ended_at = pg_catalog.now(),
      ended_by = (select auth.uid()), end_reason = '新增候选排除：' || pg_catalog.btrim(p_reason)
    where id = v_term.id;
    perform private_db2.fill_monthly_admin_vacancies(v_term.service_month);
  end if;
  return v_id;
end;
$$;

revoke all on function public.create_admin_candidate_exclusion(uuid, text, timestamptz, timestamptz)
  from public, anon, authenticated, service_role;
grant execute on function public.create_admin_candidate_exclusion(uuid, text, timestamptz, timestamptz)
  to authenticated, service_role;

comment on function public.create_admin_candidate_exclusion(uuid, text, timestamptz, timestamptz) is
  'DB-15 creates a future-effective candidate exclusion; expired ranges are rejected before audit insertion.';

commit;
