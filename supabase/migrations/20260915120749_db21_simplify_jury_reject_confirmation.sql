begin;

-- DB-21 V2.1 复验补丁：永久驳回沿用套装驳回的确认方式。
-- 第一位管理员填写理由，后续管理员读取同一提案并直接确认，不再重复输入。

create or replace function public.get_jury_review_queue_with_evidence()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_user_level smallint;
  v_is_super_admin boolean := false;
  v_is_ordinary_admin boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  v_is_super_admin := public.is_super_admin();
  v_is_ordinary_admin := private_db2.is_effective_ordinary_admin(v_user_id, pg_catalog.now());

  select private_db2.level_for_points(coalesce(pg_catalog.sum(ledger.delta), 0))
  into v_user_level
  from public.points_ledger as ledger
  where ledger.user_id = v_user_id
    and ledger.status = 'awarded';

  select coalesce(
    pg_catalog.jsonb_agg(
      queue.item || pg_catalog.jsonb_build_object(
        'correction_evidence', coalesce(evidence.items, '[]'::jsonb),
        'approve_weight', coalesce(vote_stats.approve_weight, 0),
        'reject_weight', coalesce(vote_stats.reject_weight, 0),
        'review_opinions', coalesce(vote_stats.review_opinions, '[]'::jsonb),
        'can_submit_review_note',
          v_user_level >= 2 and coalesce((queue.item->>'can_vote')::boolean, false),
        'current_user_level', v_user_level,
        'can_admin_reject',
          nullif(queue.item->>'candidate_id', '') is not null
          and not coalesce((queue.item->>'is_candidate_author')::boolean, false)
          and not coalesce(admin_reject.signed_by_me, false)
          and (
            v_is_super_admin
            or (
              v_is_ordinary_admin
              and nullif(queue.item->>'my_vote', '') is null
            )
          ),
        'admin_reject_block_reason', case
          when nullif(queue.item->>'candidate_id', '') is null then 'no_candidate'
          when coalesce((queue.item->>'is_candidate_author')::boolean, false) then 'candidate_author'
          when coalesce(admin_reject.signed_by_me, false) then 'already_confirmed'
          when v_is_super_admin then null
          when not v_is_ordinary_admin then 'not_admin'
          when nullif(queue.item->>'my_vote', '') is not null then 'already_voted'
          else null
        end,
        'admin_reject_reason', case
          when v_is_super_admin or v_is_ordinary_admin then admin_reject.reason
          else null
        end,
        'admin_reject_signature_count', case
          when v_is_super_admin or v_is_ordinary_admin then coalesce(admin_reject.signature_count, 0)
          else 0
        end,
        'admin_reject_required_signatures', case
          when v_is_super_admin or v_is_ordinary_admin
            then coalesce(admin_reject.required_signatures, case when v_is_super_admin then 1 else 2 end)
          else 0
        end,
        'admin_reject_signed_by_me', case
          when v_is_super_admin or v_is_ordinary_admin then coalesce(admin_reject.signed_by_me, false)
          else false
        end
      )
      order by queue.ordinality
    ),
    '[]'::jsonb
  ) into v_result
  from pg_catalog.jsonb_array_elements(public.get_jury_review_queue())
    with ordinality as queue(item, ordinality)
  left join lateral (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'field_key', request.field_key,
        'evidence_image_path', request.evidence_image_path
      ) order by request.created_at, request.id
    ) as items
    from public.correction_requests as request
    where request.re_review_item_id = (queue.item->>'re_review_item_id')::uuid
      and request.evidence_image_path is not null
  ) as evidence on true
  left join lateral (
    select
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'approve'), 0)::integer as approve_weight,
      coalesce(pg_catalog.sum(vote.vote_weight) filter (where vote.vote = 'reject'), 0)::integer as reject_weight,
      pg_catalog.jsonb_agg(
        pg_catalog.jsonb_build_object(
          'voter_level', vote.voter_level,
          'vote', vote.vote,
          'review_note', vote.review_note
        ) order by vote.created_at, vote.id
      ) filter (where vote.review_note is not null) as review_opinions
    from public.jury_votes as vote
    where vote.candidate_id = nullif(queue.item->>'candidate_id', '')::uuid
  ) as vote_stats on true
  left join lateral (
    select
      action.reason,
      action.required_signatures,
      coalesce((
        select pg_catalog.count(*)::integer
        from public.community_admin_action_signatures as signature
        left join public.admin_terms as term on term.id = signature.admin_term_id
        where signature.action_id = action.id
          and (
            signature.signature_source = 'super_admin'
            or (
              signature.signature_source = 'ordinary_admin'
              and term.status = 'active'
              and term.starts_at <= pg_catalog.now()
              and term.scheduled_end_at > pg_catalog.now()
            )
          )
      ), 0) as signature_count,
      exists (
        select 1
        from public.community_admin_action_signatures as mine
        where mine.action_id = action.id
          and mine.signer_user_id = v_user_id
      ) as signed_by_me
    from public.community_admin_actions as action
    where action.action_type = 'jury_permanent_reject'
      and action.target_key = 'jury:' || nullif(queue.item->>'candidate_id', '')
      and action.status = 'proposed'
      and action.expires_at > pg_catalog.now()
    order by action.created_at, action.id
    limit 1
  ) as admin_reject on true;

  return v_result;
end;
$$;

revoke all on function public.get_jury_review_queue_with_evidence()
  from public, anon, authenticated, service_role;
grant execute on function public.get_jury_review_queue_with_evidence()
  to authenticated, service_role;

comment on function public.get_jury_review_queue_with_evidence() is
  'DB-21 V2.1 陪审队列：第一位管理员填写永久驳回理由，后续管理员读取该理由后直接确认。';

commit;
