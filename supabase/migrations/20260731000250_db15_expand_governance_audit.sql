-- DB-15 治理审计补丁：展示审核者与关联任期，不暴露邮箱。
begin;

create or replace function public.list_admin_governance()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare v_result jsonb;
begin
  if not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可查看任期治理';
  end if;
  select pg_catalog.jsonb_build_object(
    'terms', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', term.id, 'user_id', term.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'source', term.source, 'service_month', term.service_month,
        'starts_at', term.starts_at, 'scheduled_end_at', term.scheduled_end_at,
        'status', term.status, 'reason', term.reason, 'end_reason', term.end_reason,
        'created_at', term.created_at
      ) order by term.created_at desc)
      from public.admin_terms as term
      left join public.profiles as profile on profile.id = term.user_id
    ), '[]'::jsonb),
    'exclusions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', exclusion.id, 'user_id', exclusion.user_id,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '未命名用户'),
        'reason', exclusion.reason, 'starts_at', exclusion.starts_at,
        'ends_at', exclusion.ends_at, 'revoked_at', exclusion.revoked_at
      ) order by exclusion.created_at desc)
      from public.admin_candidate_exclusions as exclusion
      left join public.profiles as profile on profile.id = exclusion.user_id
    ), '[]'::jsonb),
    'candidates', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'service_month', candidate.service_month,
        'candidate_order', candidate.candidate_order,
        'frozen_points', candidate.frozen_points,
        'qualifying_action_count', candidate.qualifying_action_count,
        'eligibility_status', candidate.eligibility_status,
        'skip_reason', candidate.skip_reason,
        'display_name', coalesce(nullif(pg_catalog.btrim(profile.username), ''), nullif(pg_catalog.btrim(profile.nickname), ''), '已注销用户')
      ) order by candidate.service_month desc, candidate.candidate_order)
      from private_db2.admin_rotation_candidates as candidate
      left join public.profiles as profile on profile.id = candidate.user_id
    ), '[]'::jsonb),
    'decisions', coalesce((
      select pg_catalog.jsonb_agg(pg_catalog.jsonb_build_object(
        'id', decision.id,
        'reviewer_display_name', coalesce(
          nullif(pg_catalog.btrim(reviewer.username), ''),
          nullif(pg_catalog.btrim(reviewer.nickname), ''),
          '已注销管理员'
        ),
        'term_source', term.source,
        'term_ends_at', term.scheduled_end_at,
        'action', decision.action,
        'reason', decision.reason,
        'adopted_payload', decision.adopted_payload,
        'adopted_count', pg_catalog.cardinality(decision.adopted_pending_ids),
        'source_count', pg_catalog.cardinality(decision.all_source_pending_ids),
        'created_at', decision.created_at
      ) order by decision.created_at desc)
      from public.admin_review_decisions as decision
      left join public.profiles as reviewer on reviewer.id = decision.reviewer_user_id
      left join public.admin_terms as term on term.id = decision.admin_term_id
    ), '[]'::jsonb)
  ) into v_result;
  return v_result;
end;
$$;

revoke all on function public.list_admin_governance()
  from public, anon, authenticated, service_role;
grant execute on function public.list_admin_governance()
  to authenticated, service_role;

comment on function public.list_admin_governance() is
  'DB-15 super-admin governance read model, including reviewer display and associated term facts without emails.';

commit;
