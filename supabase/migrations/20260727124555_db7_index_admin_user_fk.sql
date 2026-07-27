begin;

create index jury_admin_decisions_admin_user_id_idx
  on public.jury_admin_decisions (admin_user_id)
  where admin_user_id is not null;

comment on index public.jury_admin_decisions_admin_user_id_idx is
  'DB-7 覆盖管理员终审记录的用户外键，避免删除用户或按管理员追溯时扫描整表。';

commit;
