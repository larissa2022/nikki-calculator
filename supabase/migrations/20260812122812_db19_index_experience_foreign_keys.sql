begin;

drop index private_db2.monthly_lv4_experience_terms_source_snapshot_id_idx;

create index monthly_lv4_experience_terms_source_fact_idx
  on private_db2.monthly_lv4_experience_terms (
    source_snapshot_id,
    source_month,
    frozen_points,
    leaderboard_rank
  );

create index monthly_lv4_experience_terms_source_user_idx
  on private_db2.monthly_lv4_experience_terms (source_snapshot_id, user_id);

commit;
