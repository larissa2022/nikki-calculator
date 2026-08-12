begin;

create unique index points_leaderboard_monthly_snapshots_source_fact_key
  on private_db2.points_leaderboard_monthly_snapshots (
    id,
    month_start,
    points,
    leaderboard_rank
  );

create unique index points_leaderboard_monthly_snapshots_user_identity_key
  on private_db2.points_leaderboard_monthly_snapshots (id, user_id);

alter table private_db2.monthly_lv4_experience_terms
  drop constraint monthly_lv4_experience_terms_source_snapshot_fkey,
  add constraint monthly_lv4_experience_terms_source_fact_fkey
    foreign key (
      source_snapshot_id,
      source_month,
      frozen_points,
      leaderboard_rank
    )
    references private_db2.points_leaderboard_monthly_snapshots (
      id,
      month_start,
      points,
      leaderboard_rank
    )
    on update restrict
    on delete restrict,
  add constraint monthly_lv4_experience_terms_source_user_fkey
    foreign key (source_snapshot_id, user_id)
    references private_db2.points_leaderboard_monthly_snapshots (id, user_id)
    on update cascade
    on delete restrict;

comment on constraint monthly_lv4_experience_terms_source_fact_fkey
  on private_db2.monthly_lv4_experience_terms is
  '资格的来源月、冻结积分和第一名名次必须逐项等于所引用的冻结快照。';
comment on constraint monthly_lv4_experience_terms_source_user_fkey
  on private_db2.monthly_lv4_experience_terms is
  '资格用户必须等于冻结快照用户；账号注销时跟随快照去身份化为 null。';

commit;
