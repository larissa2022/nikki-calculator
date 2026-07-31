-- DB-15 Advisor 补丁：补齐新增外键覆盖索引。
begin;

create index admin_review_authorizations_term_id_idx
  on private_db2.admin_review_authorizations (term_id);

create index admin_rotation_candidates_user_id_idx
  on private_db2.admin_rotation_candidates (user_id);

create index admin_candidate_exclusions_created_by_idx
  on public.admin_candidate_exclusions (created_by);

create index admin_candidate_exclusions_revoked_by_idx
  on public.admin_candidate_exclusions (revoked_by)
  where revoked_by is not null;

create index admin_review_decisions_admin_term_id_idx
  on public.admin_review_decisions (admin_term_id)
  where admin_term_id is not null;

create index admin_terms_ended_by_idx
  on public.admin_terms (ended_by)
  where ended_by is not null;

create index admin_terms_granted_by_idx
  on public.admin_terms (granted_by)
  where granted_by is not null;

commit;
