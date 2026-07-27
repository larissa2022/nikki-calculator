begin;

revoke insert on table public.re_review_candidates
  from authenticated;

grant insert (re_review_item_id, payload, submitted_by)
  on table public.re_review_candidates
  to authenticated;

comment on table public.re_review_candidates is
  '登录用户只能提交重审项、候选内容和本人身份；候选 ID 与创建时间由数据库生成，候选不可修改或删除。';

commit;
