


SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


CREATE SCHEMA IF NOT EXISTS "public";


ALTER SCHEMA "public" OWNER TO "pg_database_owner";


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE OR REPLACE FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") RETURNS integer
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_updated_count integer := 0;
begin
  if p_clothes_id is null or nullif(trim(p_clothes_id), '') is null then
    return 0;
  end if;

  if p_user_ids is null or array_length(p_user_ids, 1) is null then
    return 0;
  end if;

  with target_users as (
    select distinct user_id
    from unnest(p_user_ids) as submitter_ids(user_id)
    where user_id is not null
  ),
  merged_wardrobes as (
    select
      tu.user_id,
      (
        select coalesce(jsonb_agg(to_jsonb(value) order by value), '[]'::jsonb)
        from (
          select distinct value
          from jsonb_array_elements_text(
            case
              when jsonb_typeof(uw.owned_clothes) = 'array' then uw.owned_clothes
              else '[]'::jsonb
            end || jsonb_build_array(p_clothes_id)
          ) as existing_ids(value)
        ) deduped_ids
      ) as owned_clothes
    from target_users tu
    left join public.user_wardrobes uw on uw.user_id = tu.user_id
  ),
  upserted as (
    insert into public.user_wardrobes (user_id, owned_clothes)
    select user_id, owned_clothes
    from merged_wardrobes
    on conflict (user_id) do update
      set owned_clothes = excluded.owned_clothes
    returning 1
  )
  select count(*)::integer into v_updated_count
  from upserted;

  return v_updated_count;
end;
$$;


ALTER FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := (select auth.uid());
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_existing_decision public.jury_admin_decisions%rowtype;
  v_reason text := nullif(pg_catalog.btrim(coalesce(p_reason, '')), '');
begin
  if v_user_id is null then
    raise exception '需要登录后才能执行管理员终审';
  end if;

  if not public.is_super_admin() then
    raise exception '只有超级管理员可以执行永久驳回终审';
  end if;

  if v_reason is null then
    raise exception '永久驳回必须填写终审理由';
  end if;

  select decision.*
    into v_existing_decision
  from public.jury_admin_decisions as decision
  where decision.candidate_id = p_candidate_id;

  if found then
    if v_existing_decision.admin_user_id is not distinct from v_user_id
      and v_existing_decision.reason is not distinct from v_reason then
      return pg_catalog.jsonb_build_object(
        'candidate_id', v_existing_decision.candidate_id,
        're_review_item_id', v_existing_decision.re_review_item_id,
        'status', 'rejected',
        'idempotent', true
      );
    end if;
    raise exception '该内容已经完成管理员终审';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found or v_candidate.status not in ('voting', 'returned') then
    raise exception '待审核内容不存在或当前不能终审驳回';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status not in ('pending', 'voting', 'failed') then
    raise exception '审核事项当前不能终审驳回';
  end if;

  if (v_candidate.status = 'voting' and v_item.status <> 'voting')
    or (v_candidate.status = 'returned' and v_item.status not in ('pending', 'failed'))
    or exists (
      select 1
      from public.re_review_candidates as active_candidate
      where active_candidate.re_review_item_id = v_item.id
        and active_candidate.status = 'voting'
        and active_candidate.id <> v_candidate.id
    ) then
    raise exception '该内容已不是当前可终审轮次';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '管理员不能终审自己提交或参与过的数据';
  end if;

  if exists (
    select 1
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id
      and vote.user_id = v_user_id
  ) then
    raise exception using
      errcode = '42501',
      message = '已经参与普通投票，不能再执行终审';
  end if;

  insert into public.jury_admin_decisions (
    candidate_id,
    re_review_item_id,
    admin_user_id,
    decision,
    reason
  )
  values (
    v_candidate.id,
    v_item.id,
    v_user_id,
    'rejected',
    v_reason
  );

  update public.re_review_candidates
  set
    status = 'rejected',
    resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set
    status = 'rejected',
    resolved_by = v_user_id,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'status', 'rejected',
    'idempotent', false
  );
end;
$$;


ALTER FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") IS 'DB-7 补丁：超级管理员独立终审；参投管理员不可终审，相同终审重试幂等。';



CREATE OR REPLACE FUNCTION "public"."apply_approved_jury_candidate"("p_re_review_item_id" "uuid", "p_candidate_id" "uuid", "p_resolved_by" "uuid") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_item public.re_review_items%rowtype;
  v_candidate public.re_review_candidates%rowtype;
  v_base_payload jsonb;
  v_final_payload jsonb;
  v_clothes_id text;
  v_suit_id uuid;
  v_contribution_id uuid;
  v_contributor_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_user_ids uuid[] := '{}'::uuid[];
  v_source_ids bigint[] := '{}'::bigint[];
  v_source_created_ats timestamptz[] := '{}'::timestamptz[];
  v_index integer;
  v_is_legacy_missing_suit boolean := false;
begin
  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = p_re_review_item_id
  for update;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
    and candidate.re_review_item_id = p_re_review_item_id
  for update;

  if v_item.id is null or v_candidate.id is null then
    raise exception '待审核内容或审核事项不存在';
  end if;

  v_base_payload := case
    when v_item.payload ? 'base_record' then v_item.payload->'base_record'
    else public.jury_clothes_payload(v_item.clothes_id)
  end;

  v_is_legacy_missing_suit := v_item.reason = 'missing_suit'
    and pg_catalog.jsonb_typeof(v_candidate.payload) = 'object'
    and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(v_candidate.payload)) = 1
    and v_candidate.payload ? 'suit_id';

  v_final_payload := case
    when v_is_legacy_missing_suit
      then v_base_payload || v_candidate.payload || pg_catalog.jsonb_build_object(
        'temp_suit_name', null,
        'needs_suit_review', false
      )
    else v_candidate.payload
  end;

  if not v_is_legacy_missing_suit
    and not public.jury_payload_is_complete(v_final_payload) then
    raise exception '待审核内容不是完整服装资料';
  end if;

  if v_final_payload->'suit_id' <> 'null'::jsonb then
    begin
      v_suit_id := (v_final_payload->>'suit_id')::uuid;
    exception when invalid_text_representation then
      raise exception '所属套装格式无效';
    end;

    if not exists (select 1 from public.suits as suit where suit.id = v_suit_id) then
      raise exception '所选套装不存在';
    end if;
  end if;

  if v_item.clothes_id is not null then
    if public.jury_clothes_payload(v_item.clothes_id) is distinct from v_base_payload then
      raise exception '正式服装已变化，不能按旧的审核内容修改';
    end if;

    update public.clothes
    set
      name = v_final_payload->>'name',
      game_id = v_final_payload->>'game_id',
      category = v_final_payload->>'category',
      stars = v_final_payload->>'stars',
      scores = v_final_payload->'scores',
      suit_id = v_suit_id,
      temp_suit_name = null,
      tags = nullif(pg_catalog.btrim(coalesce(v_final_payload->>'tags', '')), '')
    where id = v_item.clothes_id;

    if not found then
      raise exception '正式服装不存在，已回滚本次投票';
    end if;

    v_clothes_id := v_item.clothes_id;
  else
    v_clothes_id := 'custom_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');

    insert into public.clothes (
      id,
      name,
      game_id,
      category,
      stars,
      scores,
      suit_id,
      temp_suit_name,
      tags
    )
    values (
      v_clothes_id,
      v_final_payload->>'name',
      v_final_payload->>'game_id',
      v_final_payload->>'category',
      v_final_payload->>'stars',
      v_final_payload->'scores',
      v_suit_id,
      null,
      nullif(pg_catalog.btrim(coalesce(v_final_payload->>'tags', '')), '')
    );

    with earliest_matching_per_user as (
      select distinct on (source.source_user_id)
        source.source_user_id as user_id,
        source.source_pending_id,
        pending.created_at as source_created_at
      from public.re_review_item_sources as source
      join public.pending_clothes as pending
        on pending.id = source.source_pending_id
      where source.re_review_item_id = v_item.id
        and source.source_user_id is not null
        and public.jury_pending_payload(source.source_pending_id)
          is not distinct from v_final_payload
      order by source.source_user_id, pending.created_at, source.source_pending_id
    ), effective_sources as (
      select matching.*
      from earliest_matching_per_user as matching
      order by matching.source_created_at, matching.source_pending_id, matching.user_id
      limit 5
    )
    select
      coalesce(pg_catalog.array_agg(source.user_id order by source.source_created_at, source.source_pending_id), '{}'::uuid[]),
      coalesce(pg_catalog.array_agg(source.source_pending_id order by source.source_created_at, source.source_pending_id), '{}'::bigint[]),
      coalesce(pg_catalog.array_agg(source.source_created_at order by source.source_created_at, source.source_pending_id), '{}'::timestamptz[])
      into v_user_ids, v_source_ids, v_source_created_ats
    from effective_sources as source;

    v_contributor_count := pg_catalog.cardinality(v_user_ids);

    for v_index in 1..v_contributor_count loop
      insert into public.clothing_contributions (
        event_id,
        clothes_id,
        user_id,
        source_pending_id,
        contribution_type,
        contribution_rank,
        source_created_at
      )
      values (
        v_candidate.id,
        v_clothes_id,
        v_user_ids[v_index],
        v_source_ids[v_index],
        'jury_resolution',
        v_index::smallint,
        v_source_created_ats[v_index]
      )
      returning id into v_contribution_id;

      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        source_id,
        re_review_candidate_id,
        jury_vote_id,
        reversal_of
      )
      values (
        v_user_ids[v_index],
        10,
        'awarded',
        'clothing_contribution',
        v_contribution_id,
        null,
        null,
        null
      );

      v_points_count := v_points_count + 1;
    end loop;

    if v_contributor_count > 0 then
      v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
        v_user_ids,
        v_clothes_id
      );
    end if;

    if v_points_count <> v_contributor_count
      or v_wardrobe_count <> v_contributor_count then
      raise exception '原始贡献、积分或衣柜写回数量异常，已回滚本次通过';
    end if;

    update public.pending_clothes as pending
    set status = case
      when public.jury_pending_payload(pending.id) is not distinct from v_final_payload
        then 'approved'
      else 'rejected'
    end
    from public.re_review_item_sources as source
    where source.re_review_item_id = v_item.id
      and source.source_pending_id = pending.id
      and pending.status = 'pending';
  end if;

  insert into public.points_ledger (
    user_id,
    delta,
    status,
    source_type,
    source_id,
    re_review_candidate_id,
    jury_vote_id,
    reversal_of
  )
  values (
    v_candidate.submitted_by,
    8,
    'awarded',
    're_review_candidate',
    null,
    v_candidate.id,
    null,
    null
  )
  on conflict (re_review_candidate_id)
    where re_review_candidate_id is not null do nothing;

  update public.re_review_candidates
  set
    status = 'approved',
    resolved_at = pg_catalog.now()
  where id = v_candidate.id;

  update public.re_review_items
  set
    status = 'approved',
    resolved_by = p_resolved_by,
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    'clothes_id', v_clothes_id,
    'source_contributor_count', v_contributor_count,
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$$;


ALTER FUNCTION "public"."apply_approved_jury_candidate"("p_re_review_item_id" "uuid", "p_candidate_id" "uuid", "p_resolved_by" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[], "p_needs_suit_review" boolean DEFAULT NULL::boolean) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_distinct_review_values integer := 0;
  v_needs_suit_review boolean := false;
  v_result jsonb;
  v_re_review_item_id uuid;
begin
  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception '待审核记录不能为空，且不能包含空值或重复 ID';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(distinct pending.needs_suit_review)::integer,
    coalesce(pg_catalog.bool_or(pending.needs_suit_review), false)
    into v_requested_count, v_distinct_review_values, v_needs_suit_review
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '存在找不到的待审核记录';
  end if;

  if v_distinct_review_values <> 1 then
    raise exception '纯散件与所属套装待确认不能合并为同一次仲裁';
  end if;

  if p_needs_suit_review is not null
    and p_needs_suit_review is distinct from v_needs_suit_review then
    raise exception '审核表单的套装状态与来源记录不一致，请刷新后重试';
  end if;

  if v_needs_suit_review
    and (
      p_suit_id is not null
      or nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '') is not null
    ) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_result := public.approve_pending_clothes_arbitration_db4_core(
    p_id,
    p_name,
    p_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_sorted_pending_ids
  );

  if v_needs_suit_review then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      p_id,
      v_sorted_pending_ids,
      coalesce((v_result->>'already_completed')::boolean, false) = false
    );

    v_result := v_result || pg_catalog.jsonb_build_object(
      're_review_item_id',
      v_re_review_item_id
    );
  end if;

  return v_result;
end;
$$;


ALTER FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[], "p_needs_suit_review" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[], "p_needs_suit_review" boolean) IS 'DB-6：管理员仲裁保持 DB-4 原子闭环；所属套装待确认的来源同时创建并核验重审项，纯散件不进入重审池。';



CREATE OR REPLACE FUNCTION "public"."approve_pending_clothes_arbitration_db4_core"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_pending_ids bigint[] := coalesce(p_pending_ids, '{}');
  v_sorted_pending_ids bigint[] := '{}';
  v_requested_pending_count integer := 0;
  v_matched_pending_count integer := 0;
  v_pending_status_count integer := 0;
  v_approved_status_count integer := 0;
  v_approved_pending_count integer := 0;
  v_effective_user_ids uuid[] := '{}';
  v_effective_pending_ids bigint[] := '{}';
  v_effective_created_ats timestamptz[] := '{}';
  v_effective_contributor_count integer := 0;
  v_contribution_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_existing_event_count integer := 0;
  v_matching_contribution_count integer := 0;
  v_matching_points_count integer := 0;
  v_matching_wardrobe_count integer := 0;
  v_event_hash text;
  v_event_id uuid;
  v_contribution_id uuid;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_index integer;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有仲裁入库权限';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_id, '')), '') is null then
    raise exception '服装 ID 不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_game_id, '')), '') is null
    or pg_catalog.btrim(p_game_id) !~ '^[0-9]+$' then
    raise exception '短编号必须为数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(v_pending_ids) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_pending_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_pending_count = 0 then
    raise exception '待审核记录不能为空';
  end if;

  if v_requested_pending_count <> pg_catalog.cardinality(v_pending_ids) then
    raise exception '待审核记录包含空值或重复 ID';
  end if;

  v_event_hash := pg_catalog.md5(
    'admin_arbitration|'
    || p_id
    || '|'
    || pg_catalog.array_to_string(v_sorted_pending_ids, ',')
  );
  v_event_id := (
    pg_catalog.substr(v_event_hash, 1, 8) || '-'
    || pg_catalog.substr(v_event_hash, 9, 4) || '-'
    || pg_catalog.substr(v_event_hash, 13, 4) || '-'
    || pg_catalog.substr(v_event_hash, 17, 4) || '-'
    || pg_catalog.substr(v_event_hash, 21, 12)
  )::uuid;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (where pending.status = 'pending')::integer,
    pg_catalog.count(*) filter (where pending.status = 'approved')::integer,
    pg_catalog.count(*) filter (
      where pending.name is not distinct from p_name
        and pending.category is not distinct from p_category
        and nullif(pg_catalog.btrim(coalesce(pending.game_id, '')), '') is not null
        and pg_catalog.btrim(pending.game_id) = pg_catalog.btrim(p_game_id)
        and pending.stars is not distinct from p_stars
        and pending.scores is not distinct from p_scores
        and pending.suit_id is not distinct from p_suit_id
        and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '')
        and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_tags, '')), '')
    )::integer
    into
      v_requested_pending_count,
      v_pending_status_count,
      v_approved_status_count,
      v_matched_pending_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_pending_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '存在找不到的待审核记录';
  end if;

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '存在与本次管理员仲裁最终数据不一致的待审核记录，已拒绝入库';
  end if;

  with earliest_per_user as (
    select distinct on (pending.submitted_by)
      pending.submitted_by as user_id,
      pending.id as source_pending_id,
      pending.created_at as source_created_at
    from public.pending_clothes as pending
    where pending.id = any(v_sorted_pending_ids)
      and pending.submitted_by is not null
    order by pending.submitted_by, pending.created_at, pending.id
  ),
  effective_contributors as (
    select
      earliest.user_id,
      earliest.source_pending_id,
      earliest.source_created_at,
      pg_catalog.row_number() over (
        order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      )::smallint as contribution_rank
    from earliest_per_user as earliest
    order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
    limit 5
  )
  select
    coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
    coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
    coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
    into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
  from effective_contributors as effective;

  v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

  select *
    into v_existing_clothes
  from public.clothes
  where id = p_id
  for update;

  v_clothes_exists := found;

  if v_pending_status_count = 0 and v_approved_status_count = v_requested_pending_count then
    if not v_clothes_exists
      or v_existing_clothes.name is distinct from p_name
      or v_existing_clothes.category is distinct from p_category
      or pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')) is distinct from pg_catalog.btrim(p_game_id)
      or pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')) is distinct from p_stars::text
      or v_existing_clothes.scores is distinct from p_scores
      or v_existing_clothes.suit_id is distinct from p_suit_id
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '')
        is distinct from nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '')
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '')
        is distinct from nullif(pg_catalog.btrim(coalesce(p_tags, '')), '') then
      raise exception '待审核记录已通过，但正式服装事实与本次仲裁不一致；禁止自动回填';
    end if;

    select pg_catalog.count(*)::integer
      into v_existing_event_count
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id;

    select pg_catalog.count(*)::integer
      into v_matching_contribution_count
    from pg_catalog.generate_subscripts(v_effective_user_ids, 1) as expected(array_index)
    join public.clothing_contributions as contribution
      on contribution.event_id = v_event_id
      and contribution.clothes_id = p_id
      and contribution.user_id = v_effective_user_ids[expected.array_index]
      and contribution.source_pending_id = v_effective_pending_ids[expected.array_index]
      and contribution.source_created_at = v_effective_created_ats[expected.array_index]
      and contribution.contribution_rank = expected.array_index::smallint
      and contribution.contribution_type = 'admin_arbitration';

    select pg_catalog.count(*)::integer
      into v_matching_points_count
    from public.clothing_contributions as contribution
    join public.points_ledger as ledger
      on ledger.source_id = contribution.id
      and ledger.user_id = contribution.user_id
      and ledger.delta = 10
      and ledger.status = 'awarded'
      and ledger.source_type = 'clothing_contribution'
      and ledger.reversal_of is null
    where contribution.event_id = v_event_id;

    select pg_catalog.count(*)::integer
      into v_matching_wardrobe_count
    from pg_catalog.unnest(v_effective_user_ids) as expected(user_id)
    join public.user_wardrobes as wardrobe
      on wardrobe.user_id = expected.user_id
      and coalesce(wardrobe.owned_clothes, '[]'::jsonb)
        @> pg_catalog.jsonb_build_array(p_id);

    if v_existing_event_count <> v_effective_contributor_count
      or v_matching_contribution_count <> v_effective_contributor_count
      or v_matching_points_count <> v_effective_contributor_count
      or v_matching_wardrobe_count <> v_effective_contributor_count then
      raise exception '待审核记录已通过，但贡献、积分或衣柜事实不完整；禁止自动回填，请人工核对';
    end if;

    return pg_catalog.jsonb_build_object(
      'approved', true,
      'already_completed', true,
      'event_id', v_event_id,
      'clothes_id', p_id,
      'approved_pending_count', v_requested_pending_count,
      'submitter_count', v_effective_contributor_count,
      'contribution_count', v_matching_contribution_count,
      'points_awarded_count', v_matching_points_count,
      'points_awarded_total', v_matching_points_count * 10,
      'wardrobe_updated_count', v_matching_wardrobe_count
    );
  end if;

  if v_pending_status_count <> v_requested_pending_count or v_approved_status_count <> 0 then
    raise exception '待审核记录状态不一致，请刷新审核页后重试';
  end if;

  if v_clothes_exists then
    raise exception '正式库已存在该服装，请刷新后台后使用正式库补全或重审流程';
  end if;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_sorted_pending_ids)
  ) then
    raise exception '本次来源已存在贡献事实，但待审核状态未完成；请人工核对';
  end if;

  insert into public.clothes (
    id,
    name,
    game_id,
    category,
    stars,
    scores,
    suit_id,
    temp_suit_name,
    tags
  )
  values (
    p_id,
    p_name,
    pg_catalog.btrim(p_game_id),
    p_category,
    p_stars::text,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags
  );

  if v_effective_contributor_count > 0 then
    for v_index in 1..v_effective_contributor_count loop
      insert into public.clothing_contributions (
        event_id,
        clothes_id,
        user_id,
        source_pending_id,
        contribution_type,
        contribution_rank,
        source_created_at
      )
      values (
        v_event_id,
        p_id,
        v_effective_user_ids[v_index],
        v_effective_pending_ids[v_index],
        'admin_arbitration',
        v_index::smallint,
        v_effective_created_ats[v_index]
      )
      returning id into v_contribution_id;

      v_contribution_count := v_contribution_count + 1;

      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        source_id
      )
      values (
        v_effective_user_ids[v_index],
        10,
        'awarded',
        'clothing_contribution',
        v_contribution_id
      );

      v_points_count := v_points_count + 1;
    end loop;
  end if;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
    v_effective_user_ids,
    p_id
  );

  if v_contribution_count <> v_effective_contributor_count
    or v_points_count <> v_effective_contributor_count
    or v_wardrobe_count <> v_effective_contributor_count then
    raise exception '贡献、积分或衣柜写回数量异常，已回滚本次仲裁';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_sorted_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '待审核记录通过数量异常，已回滚本次仲裁';
  end if;

  return pg_catalog.jsonb_build_object(
    'approved', true,
    'already_completed', false,
    'event_id', v_event_id,
    'clothes_id', p_id,
    'approved_pending_count', v_approved_pending_count,
    'submitter_count', v_effective_contributor_count,
    'contribution_count', v_contribution_count,
    'points_awarded_count', v_points_count,
    'points_awarded_total', v_points_count * 10,
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$_$;


ALTER FUNCTION "public"."approve_pending_clothes_arbitration_db4_core"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."approve_pending_clothes_arbitration_db4_core"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) IS 'DB-6 内部兼容核心：保留 DB-4 管理员仲裁、贡献、积分、衣柜和 pending 原子写入，由公开包装函数补充待补套装重审链。';



CREATE OR REPLACE FUNCTION "public"."auto_link_shadow_suits"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  update public.clothes
  set suit_id = new.id, temp_suit_name = null
  where temp_suit_name = new.name;

  update public.pending_clothes
  set suit_id = new.id, temp_suit_name = null
  where temp_suit_name = new.name;

  return new;
end;
$$;


ALTER FUNCTION "public"."auto_link_shadow_suits"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."build_jury_review_payload"("p_pending_ids" bigint[], "p_clothes_id" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE
    SET "search_path" TO ''
    AS $$
declare
  v_fields text[] := array[
    'name', 'game_id', 'category', 'stars',
    'pair1', 'pair2', 'pair3', 'pair4', 'pair5',
    'suit', 'tags'
  ];
  v_field text;
  v_base jsonb;
  v_values jsonb;
  v_distinct_count integer;
  v_has_null boolean;
  v_issues jsonb := '[]'::jsonb;
  v_options jsonb := '{}'::jsonb;
begin
  if p_clothes_id is not null then
    v_base := public.jury_clothes_payload(p_clothes_id);
  else
    select public.jury_pending_payload(pending.id)
      into v_base
    from public.pending_clothes as pending
    where pending.id = any(coalesce(p_pending_ids, '{}'::bigint[]))
    order by pending.created_at, pending.id
    limit 1;
  end if;

  if v_base is null then
    raise exception '无法读取审核事项的基础资料';
  end if;

  foreach v_field in array v_fields loop
    with field_values as (
      select
        public.jury_payload_field_value(
          public.jury_pending_payload(pending.id),
          v_field
        ) as value,
        public.jury_field_value_is_missing(
          public.jury_pending_payload(pending.id),
          v_field
        ) as is_missing
      from public.pending_clothes as pending
      where pending.id = any(coalesce(p_pending_ids, '{}'::bigint[]))

      union all

      select
        public.jury_payload_field_value(v_base, v_field),
        public.jury_field_value_is_missing(v_base, v_field)
      where p_clothes_id is not null
    ), distinct_values as (
      select distinct value
      from field_values
    )
    select
      coalesce(pg_catalog.jsonb_agg(value order by value::text), '[]'::jsonb),
      pg_catalog.count(*)::integer,
      coalesce((select pg_catalog.bool_or(is_missing) from field_values), false)
      into v_values, v_distinct_count, v_has_null
    from distinct_values;

    if v_distinct_count > 1 or (v_has_null and v_field <> 'tags') then
      v_issues := v_issues || pg_catalog.jsonb_build_array(
        pg_catalog.jsonb_build_object(
          'field', v_field,
          'kind', case when v_has_null then 'missing' else 'conflict' end
        )
      );
      v_options := v_options || pg_catalog.jsonb_build_object(v_field, v_values);
    end if;
  end loop;

  return pg_catalog.jsonb_build_object(
    'base_record', v_base,
    'base_version', pg_catalog.md5(v_base::text),
    'issues', v_issues,
    'field_options', v_options
  );
end;
$$;


ALTER FUNCTION "public"."build_jury_review_payload"("p_pending_ids" bigint[], "p_clothes_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := (select auth.uid());
  v_candidate public.re_review_candidates%rowtype;
  v_item public.re_review_items%rowtype;
  v_vote_id uuid;
  v_existing_vote text;
  v_approve_count integer := 0;
  v_reject_count integer := 0;
  v_result_status text := 'voting';
  v_points_awarded integer := 0;
  v_apply_result jsonb := '{}'::jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能参与陪审团投票';
  end if;

  if p_vote is null or p_vote not in ('approve', 'reject') then
    raise exception '投票只允许 approve 或 reject';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.id = p_candidate_id
  for update;

  if not found then
    raise exception '待审核内容不存在';
  end if;

  select vote.id, vote.vote
    into v_vote_id, v_existing_vote
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id
    and vote.user_id = v_user_id;

  if found and v_existing_vote is distinct from p_vote then
    raise exception '投票提交后不能修改';
  end if;

  if v_candidate.status <> 'voting' then
    if v_vote_id is null then
      raise exception '该内容当前不可投票';
    end if;

    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
      into v_approve_count, v_reject_count
    from public.jury_votes as vote
    where vote.candidate_id = v_candidate.id;

    return pg_catalog.jsonb_build_object(
      'candidate_id', v_candidate.id,
      're_review_item_id', v_candidate.re_review_item_id,
      'approve_count', v_approve_count,
      'reject_count', v_reject_count,
      'my_vote', v_existing_vote,
      'points_awarded', 0,
      'status', v_candidate.status
    );
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = v_candidate.re_review_item_id
  for update;

  if not found or v_item.status <> 'voting' then
    raise exception '审核事项当前不在投票状态';
  end if;

  if v_candidate.submitted_by is not distinct from v_user_id
    or v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能投票审核自己提交或参与过的数据';
  end if;

  if v_vote_id is null then
    insert into public.jury_votes (candidate_id, user_id, vote)
    values (v_candidate.id, v_user_id, p_vote)
    returning id into v_vote_id;

    insert into public.points_ledger (
      user_id,
      delta,
      status,
      source_type,
      source_id,
      re_review_candidate_id,
      jury_vote_id,
      reversal_of
    )
    values (
      v_user_id,
      1,
      'awarded',
      'jury_vote',
      null,
      null,
      v_vote_id,
      null
    )
    on conflict (jury_vote_id) where jury_vote_id is not null do nothing;

    get diagnostics v_points_awarded = row_count;
    v_existing_vote := p_vote;
  end if;

  select
    pg_catalog.count(*) filter (where vote.vote = 'approve')::integer,
    pg_catalog.count(*) filter (where vote.vote = 'reject')::integer
    into v_approve_count, v_reject_count
  from public.jury_votes as vote
  where vote.candidate_id = v_candidate.id;

  if v_approve_count >= 5 and v_approve_count > v_reject_count then
    v_apply_result := public.apply_approved_jury_candidate(
      v_item.id,
      v_candidate.id,
      v_user_id
    );
    v_result_status := 'approved';
  elsif v_reject_count - v_approve_count >= 3 then
    update public.re_review_candidates
    set
      status = 'returned',
      resolved_at = pg_catalog.now()
    where id = v_candidate.id;

    update public.re_review_items
    set
      status = 'pending',
      resolved_by = null,
      resolved_at = null,
      updated_at = pg_catalog.now()
    where id = v_item.id;

    v_result_status := 'returned';
  end if;

  return pg_catalog.jsonb_build_object(
    'candidate_id', v_candidate.id,
    're_review_item_id', v_item.id,
    'approve_count', v_approve_count,
    'reject_count', v_reject_count,
    'my_vote', v_existing_vote,
    'points_awarded', case when v_points_awarded > 0 then 1 else 0 end,
    'status', v_result_status
  ) || v_apply_result;
end;
$$;


ALTER FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") IS 'DB-7 补丁：不可改票；首次有效投票即时 +1，达到门槛后原子应用完整审核结果。';



CREATE OR REPLACE FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
begin
  update public.re_review_items
  set
    status = 'approved',
    resolved_by = (select auth.uid()),
    resolved_at = pg_catalog.now(),
    updated_at = pg_catalog.now()
  where clothes_id = new.id
    and reason = 'missing_suit'
    and status in ('pending', 'voting');

  return new;
end;
$$;


ALTER FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"() IS 'DB-6 内部触发器函数：正式服装绑定正式套装后自动关闭活跃的待补套装重审项。';



CREATE OR REPLACE FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_missing_suit_count integer := 0;
  v_pending_count integer := 0;
  v_approved_count integer := 0;
  v_allow_create boolean := false;
  v_result jsonb;
  v_re_review_item_id uuid;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有补全正式库权限';
  end if;

  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception 'pending 来源不能为空，且不能包含空值或重复 ID';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (where pending.needs_suit_review)::integer,
    pg_catalog.count(*) filter (where pending.status = 'pending')::integer,
    pg_catalog.count(*) filter (where pending.status = 'approved')::integer
    into v_requested_count, v_missing_suit_count, v_pending_count, v_approved_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '部分 pending 来源不存在';
  end if;

  if v_missing_suit_count > 0
    and v_missing_suit_count <> v_requested_count then
    raise exception '纯散件与所属套装待确认来源不能混合补全';
  end if;

  if v_missing_suit_count = v_requested_count then
    if v_pending_count = v_requested_count then
      v_allow_create := true;
    elsif v_approved_count = v_requested_count then
      v_allow_create := false;
    else
      raise exception '所属套装待确认来源状态不一致，禁止静默补写';
    end if;
  end if;

  v_result := public.complete_existing_clothes_from_pending_db3_core(
    p_existing_id,
    p_name,
    p_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_sorted_pending_ids
  );

  if v_missing_suit_count = v_requested_count then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      p_existing_id,
      v_sorted_pending_ids,
      v_allow_create
    );

    v_result := v_result || pg_catalog.jsonb_build_object(
      're_review_item_id', v_re_review_item_id
    );
  end if;

  return v_result;
end;
$$;


ALTER FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) IS 'DB-6 包装层：保持 DB-3 参数兼容；补全已有正式服装时，所属套装待确认来源必须同事务创建或核验唯一重审项。';



CREATE OR REPLACE FUNCTION "public"."complete_existing_clothes_from_pending_db3_core"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_pending_ids bigint[] := coalesce(p_pending_ids, '{}');
  v_sorted_pending_ids bigint[] := '{}';
  v_existing_clothes public.clothes%rowtype;
  v_requested_pending_count integer := 0;
  v_matched_pending_count integer := 0;
  v_pending_status_count integer := 0;
  v_approved_status_count integer := 0;
  v_approved_pending_count integer := 0;
  v_effective_user_ids uuid[] := '{}';
  v_effective_pending_ids bigint[] := '{}';
  v_effective_created_ats timestamptz[] := '{}';
  v_effective_contributor_count integer := 0;
  v_contribution_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_existing_event_count integer := 0;
  v_matching_contribution_count integer := 0;
  v_matching_points_count integer := 0;
  v_matching_wardrobe_count integer := 0;
  v_event_hash text;
  v_event_id uuid;
  v_contribution_id uuid;
  v_index integer;
  v_has_effective_completion boolean := false;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有补全正式库权限';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_existing_id, '')), '') is null then
    raise exception '正式库服装 ID 不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_game_id, '')), '') is null
    or pg_catalog.btrim(p_game_id) !~ '^[0-9]+$' then
    raise exception '短编号必须为数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(v_pending_ids) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_pending_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_pending_count = 0 then
    raise exception '待审核记录不能为空';
  end if;

  if v_requested_pending_count <> pg_catalog.cardinality(v_pending_ids) then
    raise exception '待审核记录包含空值或重复 ID';
  end if;

  v_event_hash := pg_catalog.md5(
    'existing_field_completion|'
    || p_existing_id
    || '|'
    || pg_catalog.array_to_string(v_sorted_pending_ids, ',')
  );
  v_event_id := (
    pg_catalog.substr(v_event_hash, 1, 8) || '-'
    || pg_catalog.substr(v_event_hash, 9, 4) || '-'
    || pg_catalog.substr(v_event_hash, 13, 4) || '-'
    || pg_catalog.substr(v_event_hash, 17, 4) || '-'
    || pg_catalog.substr(v_event_hash, 21, 12)
  )::uuid;

  select *
    into v_existing_clothes
  from public.clothes
  where id = p_existing_id
    and name is not distinct from p_name
    and category is not distinct from p_category
  for update;

  if not found then
    raise exception '正式库服装不存在，或名称分类与待审核记录不一致';
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.game_id) is distinct from pg_catalog.btrim(p_game_id) then
    raise exception '正式库短编号已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.stars) is distinct from p_stars::text then
    raise exception '正式库星级已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if v_existing_clothes.scores is not null
    and v_existing_clothes.scores is distinct from p_scores then
    raise exception '正式库属性分值已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if v_existing_clothes.suit_id is not null
    and p_suit_id is not null
    and v_existing_clothes.suit_id is distinct from p_suit_id then
    raise exception '正式库套装关联已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '') is not null
    and nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.temp_suit_name) is distinct from pg_catalog.btrim(p_temp_suit_name) then
    raise exception '正式库临时套装名已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '') is not null
    and nullif(pg_catalog.btrim(coalesce(p_tags, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.tags) is distinct from pg_catalog.btrim(p_tags) then
    raise exception '正式库标签已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (where pending.status = 'pending')::integer,
    pg_catalog.count(*) filter (where pending.status = 'approved')::integer,
    pg_catalog.count(*) filter (
      where pending.name is not distinct from p_name
        and pending.category is not distinct from p_category
        and nullif(pg_catalog.btrim(coalesce(pending.game_id, '')), '') is not null
        and pg_catalog.btrim(pending.game_id) = pg_catalog.btrim(p_game_id)
        and pending.stars is not distinct from p_stars
        and pending.scores is not distinct from p_scores
        and pending.suit_id is not distinct from p_suit_id
        and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '')
        and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(p_tags, '')), '')
    )::integer
    into
      v_requested_pending_count,
      v_pending_status_count,
      v_approved_status_count,
      v_matched_pending_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_pending_count <> pg_catalog.cardinality(v_sorted_pending_ids) then
    raise exception '存在找不到的待审核记录';
  end if;

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '存在与本次正式库补全最终数据不一致的待审核记录，已拒绝自动通过';
  end if;

  with earliest_per_user as (
    select distinct on (pending.submitted_by)
      pending.submitted_by as user_id,
      pending.id as source_pending_id,
      pending.created_at as source_created_at
    from public.pending_clothes as pending
    where pending.id = any(v_sorted_pending_ids)
      and pending.submitted_by is not null
    order by pending.submitted_by, pending.created_at, pending.id
  ),
  effective_contributors as (
    select
      earliest.user_id,
      earliest.source_pending_id,
      earliest.source_created_at,
      pg_catalog.row_number() over (
        order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      )::smallint as contribution_rank
    from earliest_per_user as earliest
    order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
    limit 5
  )
  select
    coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
    coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
    coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
    into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
  from effective_contributors as effective;

  v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

  if v_pending_status_count = 0 and v_approved_status_count = v_requested_pending_count then
    select pg_catalog.count(*)::integer
      into v_existing_event_count
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id;

    select pg_catalog.count(*)::integer
      into v_matching_contribution_count
    from pg_catalog.generate_subscripts(v_effective_user_ids, 1) as expected(array_index)
    join public.clothing_contributions as contribution
      on contribution.event_id = v_event_id
      and contribution.clothes_id = p_existing_id
      and contribution.user_id = v_effective_user_ids[expected.array_index]
      and contribution.source_pending_id = v_effective_pending_ids[expected.array_index]
      and contribution.source_created_at = v_effective_created_ats[expected.array_index]
      and contribution.contribution_rank = expected.array_index::smallint
      and contribution.contribution_type = 'existing_field_completion';

    select pg_catalog.count(*)::integer
      into v_matching_points_count
    from public.clothing_contributions as contribution
    join public.points_ledger as ledger
      on ledger.source_id = contribution.id
      and ledger.user_id = contribution.user_id
      and ledger.delta = 5
      and ledger.status = 'awarded'
      and ledger.source_type = 'clothing_contribution'
      and ledger.reversal_of is null
    where contribution.event_id = v_event_id;

    select pg_catalog.count(*)::integer
      into v_matching_wardrobe_count
    from pg_catalog.unnest(v_effective_user_ids) as expected(user_id)
    join public.user_wardrobes as wardrobe
      on wardrobe.user_id = expected.user_id
      and coalesce(wardrobe.owned_clothes, '[]'::jsonb)
        @> pg_catalog.jsonb_build_array(p_existing_id);

    if v_existing_event_count <> v_effective_contributor_count
      or v_matching_contribution_count <> v_effective_contributor_count
      or v_matching_points_count <> v_effective_contributor_count
      or v_matching_wardrobe_count <> v_effective_contributor_count then
      raise exception '待审核记录已通过，但贡献、积分或衣柜事实不完整；禁止自动回填，请人工核对';
    end if;

    return pg_catalog.jsonb_build_object(
      'completed_existing', true,
      'already_completed', true,
      'event_id', v_event_id,
      'clothes_id', p_existing_id,
      'approved_pending_count', v_requested_pending_count,
      'submitter_count', v_effective_contributor_count,
      'contribution_count', v_matching_contribution_count,
      'points_awarded_count', v_matching_points_count,
      'points_awarded_total', v_matching_points_count * 5,
      'wardrobe_updated_count', v_matching_wardrobe_count
    );
  end if;

  if v_pending_status_count <> v_requested_pending_count or v_approved_status_count <> 0 then
    raise exception '待审核记录状态不一致，请刷新审核页后重试';
  end if;

  v_has_effective_completion :=
    nullif(pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')), '') is null
    or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')), '') is null
    or v_existing_clothes.scores is null
    or (v_existing_clothes.suit_id is null and p_suit_id is not null)
    or (
      nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '') is null
      and nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '') is not null
    )
    or (
      nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '') is null
      and nullif(pg_catalog.btrim(coalesce(p_tags, '')), '') is not null
    );

  if not v_has_effective_completion then
    raise exception '正式库没有可由本次请求补全的空字段，禁止重复奖励';
  end if;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_sorted_pending_ids)
  ) then
    raise exception '本次来源已存在贡献事实，但待审核状态未完成；请人工核对';
  end if;

  update public.clothes
  set
    game_id = case
      when nullif(pg_catalog.btrim(coalesce(game_id, '')), '') is null
        then pg_catalog.btrim(p_game_id)
      else game_id
    end,
    stars = case
      when nullif(pg_catalog.btrim(coalesce(stars, '')), '') is null
        then p_stars::text
      else stars
    end,
    scores = case when scores is null then p_scores else scores end,
    suit_id = case when suit_id is null then p_suit_id else suit_id end,
    temp_suit_name = case
      when nullif(pg_catalog.btrim(coalesce(temp_suit_name, '')), '') is null
        then p_temp_suit_name
      else temp_suit_name
    end,
    tags = case
      when nullif(pg_catalog.btrim(coalesce(tags, '')), '') is null
        then p_tags
      else tags
    end
  where id = v_existing_clothes.id;

  if v_effective_contributor_count > 0 then
    for v_index in 1..v_effective_contributor_count loop
      insert into public.clothing_contributions (
        event_id,
        clothes_id,
        user_id,
        source_pending_id,
        contribution_type,
        contribution_rank,
        source_created_at
      )
      values (
        v_event_id,
        p_existing_id,
        v_effective_user_ids[v_index],
        v_effective_pending_ids[v_index],
        'existing_field_completion',
        v_index::smallint,
        v_effective_created_ats[v_index]
      )
      returning id into v_contribution_id;

      v_contribution_count := v_contribution_count + 1;

      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        source_id
      )
      values (
        v_effective_user_ids[v_index],
        5,
        'awarded',
        'clothing_contribution',
        v_contribution_id
      );

      v_points_count := v_points_count + 1;
    end loop;
  end if;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
    v_effective_user_ids,
    p_existing_id
  );

  if v_contribution_count <> v_effective_contributor_count
    or v_points_count <> v_effective_contributor_count
    or v_wardrobe_count <> v_effective_contributor_count then
    raise exception '贡献、积分或衣柜写回数量异常，已回滚本次补全';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_sorted_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '待审核记录通过数量异常，已回滚本次补全';
  end if;

  return pg_catalog.jsonb_build_object(
    'completed_existing', true,
    'already_completed', false,
    'event_id', v_event_id,
    'clothes_id', p_existing_id,
    'approved_pending_count', v_approved_pending_count,
    'submitter_count', v_effective_contributor_count,
    'contribution_count', v_contribution_count,
    'points_awarded_count', v_points_count,
    'points_awarded_total', v_points_count * 5,
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$_$;


ALTER FUNCTION "public"."complete_existing_clothes_from_pending_db3_core"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."complete_existing_clothes_from_pending_db3_core"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) IS 'DB-3：正式库空字段补全，同事务记录前 5 位有效贡献者、每人 5 分、衣柜写回和 pending 通过；重复请求幂等。';



CREATE OR REPLACE FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  current_quota integer;
begin
  select quota into current_quota from public.profiles where id = user_id_param;

  if current_quota is null or current_quota <= 0 then
    return false;
  end if;

  update public.profiles set quota = quota - 1 where id = user_id_param;
  return true;
end;
$$;


ALTER FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_full_jury_review_item"("p_pending_id" bigint, "p_clothes_id" "text" DEFAULT NULL::"text", "p_require_five_sources" boolean DEFAULT true) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_pending public.pending_clothes%rowtype;
  v_identity_key text;
  v_item_id uuid;
  v_source_ids bigint[] := '{}'::bigint[];
  v_source_user_count integer := 0;
  v_primary_pending_id bigint;
  v_primary_user_id uuid;
  v_payload jsonb;
  v_reason text;
begin
  select pending.*
    into v_pending
  from public.pending_clothes as pending
  where pending.id = p_pending_id
  for update;

  if not found then
    raise exception '审核来源不存在';
  end if;

  if p_clothes_id is not null then
    v_identity_key := 'clothes|' || p_clothes_id;
  elsif exists (
    select 1
    from public.pending_clothes as same_name
    where same_name.status = 'pending'
      and same_name.name is not distinct from v_pending.name
      and same_name.category is not distinct from v_pending.category
      and pg_catalog.btrim(coalesce(same_name.game_id, ''))
        is distinct from pg_catalog.btrim(coalesce(v_pending.game_id, ''))
  ) then
    v_identity_key := 'entry|name|'
      || coalesce(v_pending.category, '') || '|'
      || pg_catalog.lower(pg_catalog.btrim(coalesce(v_pending.name, '')));
  else
    v_identity_key := 'entry|game|'
      || coalesce(v_pending.category, '') || '|'
      || pg_catalog.btrim(coalesce(v_pending.game_id, ''));
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db7-review|' || v_identity_key, 0)
  );

  select item.id
    into v_item_id
  from public.re_review_items as item
  where item.identity_key = v_identity_key
    and item.status in ('pending', 'voting', 'failed')
  order by item.created_at, item.id
  limit 1
  for update;

  select
    coalesce(pg_catalog.array_agg(source.id order by source.created_at, source.id), '{}'::bigint[]),
    pg_catalog.count(distinct source.submitted_by) filter (where source.submitted_by is not null)::integer
    into v_source_ids, v_source_user_count
  from public.pending_clothes as source
  where source.status = 'pending'
    and (
      (
        source.category is not distinct from v_pending.category
        and pg_catalog.btrim(coalesce(source.game_id, ''))
          = pg_catalog.btrim(coalesce(v_pending.game_id, ''))
      )
      or
      (
        source.name is not distinct from v_pending.name
        and source.category is not distinct from v_pending.category
      )
    );

  if v_item_id is null
    and coalesce(p_require_five_sources, true)
    and v_source_user_count < 5 then
    return null;
  end if;

  if pg_catalog.cardinality(v_source_ids) = 0 then
    raise exception '审核来源集合为空';
  end if;

  v_payload := public.build_jury_review_payload(v_source_ids, p_clothes_id);

  if pg_catalog.jsonb_array_length(coalesce(v_payload->'issues', '[]'::jsonb)) = 0 then
    return null;
  end if;

  v_reason := case
    when p_clothes_id is not null then 'correction'
    when exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_payload->'issues') as issue(value)
      where issue.value->>'kind' = 'missing'
    ) then 'field_missing'
    else 'field_conflict'
  end;

  select source.id, source.submitted_by
    into v_primary_pending_id, v_primary_user_id
  from public.pending_clothes as source
  where source.id = any(v_source_ids)
  order by source.created_at, source.id
  limit 1;

  if v_item_id is null then
    insert into public.re_review_items (
      reason,
      status,
      source_pending_id,
      clothes_id,
      payload,
      submitted_by,
      identity_key
    )
    values (
      v_reason,
      'pending',
      v_primary_pending_id,
      p_clothes_id,
      v_payload,
      v_primary_user_id,
      v_identity_key
    )
    returning id into v_item_id;
  else
    update public.re_review_items
    set
      payload = case when status in ('pending', 'failed') then v_payload else payload end,
      updated_at = pg_catalog.now()
    where id = v_item_id;
  end if;

  insert into public.re_review_item_sources (
    re_review_item_id,
    source_pending_id,
    source_user_id
  )
  select
    v_item_id,
    source.id,
    source.submitted_by
  from public.pending_clothes as source
  where source.id = any(v_source_ids)
  on conflict (re_review_item_id, source_pending_id) do nothing;

  return v_item_id;
end;
$$;


ALTER FUNCTION "public"."ensure_full_jury_review_item"("p_pending_id" bigint, "p_clothes_id" "text", "p_require_five_sources" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."ensure_missing_suit_re_review_item"("p_clothes_id" "text", "p_pending_ids" bigint[], "p_allow_create" boolean DEFAULT false) RETURNS "uuid"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_sorted_pending_ids bigint[] := '{}'::bigint[];
  v_requested_count integer := 0;
  v_matching_count integer := 0;
  v_existing_item_count integer := 0;
  v_source_count integer := 0;
  v_primary_pending_id bigint;
  v_primary_user_id uuid;
  v_item_id uuid;
  v_existing_source_ids bigint[] := '{}'::bigint[];
  v_clothes public.clothes%rowtype;
  v_payload jsonb;
begin
  select coalesce(pg_catalog.array_agg(requested.pending_id order by requested.pending_id), '{}'::bigint[])
    into v_sorted_pending_ids
  from (
    select distinct pending_id
    from pg_catalog.unnest(coalesce(p_pending_ids, '{}')) as supplied(pending_id)
    where pending_id is not null
  ) as requested;

  v_requested_count := pg_catalog.cardinality(v_sorted_pending_ids);

  if v_requested_count = 0
    or v_requested_count <> pg_catalog.cardinality(coalesce(p_pending_ids, '{}')) then
    raise exception '待补套装来源不能为空，且不能包含空值或重复 ID';
  end if;

  select clothes.*
    into v_clothes
  from public.clothes as clothes
  where clothes.id = p_clothes_id
  for update;

  if not found then
    raise exception '待补套装正式服装不存在';
  end if;

  if v_clothes.suit_id is not null
    or nullif(pg_catalog.btrim(coalesce(v_clothes.temp_suit_name, '')), '') is not null then
    raise exception '已有套装信息的正式服装不能创建待补套装重审项';
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id
  for update;

  select
    pg_catalog.count(*)::integer,
    pg_catalog.count(*) filter (
      where pending.needs_suit_review
        and pending.status in ('pending', 'approved')
        and pending.name is not distinct from v_clothes.name
        and pending.category is not distinct from v_clothes.category
        and pg_catalog.btrim(coalesce(pending.game_id, ''))
          is not distinct from pg_catalog.btrim(coalesce(v_clothes.game_id, ''))
        and pg_catalog.btrim(coalesce(pending.stars::text, ''))
          is not distinct from pg_catalog.btrim(coalesce(v_clothes.stars, ''))
        and pending.scores is not distinct from v_clothes.scores
        and pending.suit_id is null
        and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '') is null
        and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
          is not distinct from nullif(pg_catalog.btrim(coalesce(v_clothes.tags, '')), '')
    )::integer
    into v_requested_count, v_matching_count
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids);

  if v_requested_count <> pg_catalog.cardinality(v_sorted_pending_ids)
    or v_matching_count <> v_requested_count then
    raise exception '待补套装来源与正式服装不一致，已拒绝创建重审项';
  end if;

  select pending.id, pending.submitted_by
    into v_primary_pending_id, v_primary_user_id
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.created_at, pending.id, pending.submitted_by nulls last
  limit 1;

  v_payload := pg_catalog.to_jsonb(v_clothes)
    || pg_catalog.jsonb_build_object('needs_suit_review', true);

  select pg_catalog.count(*)::integer
    into v_existing_item_count
  from public.re_review_items as item
  where item.clothes_id = p_clothes_id
    and item.reason = 'missing_suit';

  if v_existing_item_count > 1 then
    raise exception '正式服装存在多个待补套装重审事实，禁止静默修复';
  end if;

  if v_existing_item_count = 1 then
    select item.id
      into v_item_id
    from public.re_review_items as item
    where item.clothes_id = p_clothes_id
      and item.reason = 'missing_suit'
    order by item.created_at, item.id
    limit 1;

    perform item.id
    from public.re_review_items as item
    where item.id = v_item_id
    for update;

    if not exists (
      select 1
      from public.re_review_items as item
      where item.id = v_item_id
        and item.status in ('pending', 'voting')
        and item.source_pending_id = v_primary_pending_id
        and item.payload is not distinct from v_payload
    ) then
      raise exception '既有待补套装重审事实与本次入库不一致，禁止静默补写';
    end if;

    select coalesce(
      pg_catalog.array_agg(source.source_pending_id order by source.source_pending_id),
      '{}'::bigint[]
    )
      into v_existing_source_ids
    from public.re_review_item_sources as source
    where source.re_review_item_id = v_item_id;

    if v_existing_source_ids is distinct from v_sorted_pending_ids then
      raise exception '既有待补套装来源事实不完整，禁止静默补写';
    end if;

    return v_item_id;
  end if;

  if not coalesce(p_allow_create, false) then
    raise exception '待补套装重审事实不存在，禁止在重试时静默补写';
  end if;

  insert into public.re_review_items (
    reason,
    status,
    source_pending_id,
    clothes_id,
    payload,
    submitted_by
  )
  values (
    'missing_suit',
    'pending',
    v_primary_pending_id,
    p_clothes_id,
    v_payload,
    v_primary_user_id
  )
  returning id into v_item_id;

  insert into public.re_review_item_sources (
    re_review_item_id,
    source_pending_id,
    source_user_id
  )
  select
    v_item_id,
    pending.id,
    pending.submitted_by
  from public.pending_clothes as pending
  where pending.id = any(v_sorted_pending_ids)
  order by pending.id;

  get diagnostics v_source_count = row_count;

  if v_source_count <> v_requested_count then
    raise exception '待补套装来源写入数量异常，已回滚本次入库';
  end if;

  return v_item_id;
end;
$$;


ALTER FUNCTION "public"."ensure_missing_suit_re_review_item"("p_clothes_id" "text", "p_pending_ids" bigint[], "p_allow_create" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."ensure_missing_suit_re_review_item"("p_clothes_id" "text", "p_pending_ids" bigint[], "p_allow_create" boolean) IS 'DB-6 内部函数：在正式服装入库事务中创建并核验唯一待补套装重审项及全部 pending 来源；既有事实不完整时拒绝静默补写。';



CREATE OR REPLACE FUNCTION "public"."get_jury_review_queue"() RETURNS "jsonb"
    LANGUAGE "plpgsql" STABLE SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := (select auth.uid());
  v_is_super_admin boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能查看陪审团';
  end if;

  v_is_super_admin := public.is_super_admin();

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        're_review_item_id', item.id,
        'reason', item.reason,
        'item_status', item.status,
        'clothes_id', item.clothes_id,
        'clothes_name', coalesce(base.payload->>'name', '未命名服装'),
        'category', coalesce(base.payload->>'category', ''),
        'game_id', coalesce(base.payload->>'game_id', ''),
        'base_payload', base.payload,
        'base_suit_name', (
          select suit.name
          from public.suits as suit
          where suit.id::text = base.payload->>'suit_id'
        ),
        'issues', issue_data.issues,
        'field_options', issue_data.field_options,
        'candidate_id', candidate.id,
        'candidate_payload', case
          when candidate.id is null then null
          when (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(candidate.payload)) = 1
            and candidate.payload ? 'suit_id'
            then base.payload || candidate.payload || pg_catalog.jsonb_build_object(
              'temp_suit_name', null,
              'needs_suit_review', false
            )
          else candidate.payload
        end,
        'candidate_status', candidate.status,
        'candidate_suit_name', (
          select suit.name
          from public.suits as suit
          where suit.id::text = candidate.payload->>'suit_id'
        ),
        'candidate_created_at', candidate.created_at,
        'approve_count', coalesce(vote_count.approve_count, 0),
        'reject_count', coalesce(vote_count.reject_count, 0),
        'my_vote', my_vote.vote,
        'can_submit_candidate', candidate.id is null and item.status in ('pending', 'failed'),
        'can_vote', candidate.id is not null
          and item.status = 'voting'
          and candidate.submitted_by is distinct from v_user_id
          and my_vote.vote is null,
        'is_candidate_author', candidate.submitted_by is not distinct from v_user_id,
        'can_admin_reject', v_is_super_admin
          and candidate.id is not null
          and candidate.submitted_by is distinct from v_user_id
          and my_vote.vote is null
      )
      order by item.created_at, item.id
    ),
    '[]'::jsonb
  )
    into v_result
  from public.re_review_items as item
  left join lateral (
    select coalesce(
      case
        when item.payload ? 'base_record' then item.payload->'base_record'
        else public.jury_clothes_payload(item.clothes_id)
      end,
      '{}'::jsonb
    ) as payload
  ) as base on true
  left join lateral (
    select
      case
        when item.payload ? 'issues' then item.payload->'issues'
        when item.reason = 'missing_suit' then pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
        )
        else '[]'::jsonb
      end as issues,
      coalesce(item.payload->'field_options', '{}'::jsonb) as field_options
  ) as issue_data on true
  left join lateral (
    select current_candidate.*
    from public.re_review_candidates as current_candidate
    where current_candidate.re_review_item_id = item.id
      and current_candidate.status = 'voting'
    order by current_candidate.created_at desc, current_candidate.id
    limit 1
  ) as candidate on true
  left join lateral (
    select
      pg_catalog.count(*) filter (where vote.vote = 'approve')::integer as approve_count,
      pg_catalog.count(*) filter (where vote.vote = 'reject')::integer as reject_count
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
  ) as vote_count on true
  left join lateral (
    select vote.vote
    from public.jury_votes as vote
    where vote.candidate_id = candidate.id
      and vote.user_id = v_user_id
    limit 1
  ) as my_vote on true
  where item.reason in ('missing_suit', 'field_conflict', 'field_missing', 'correction')
    and item.status in ('pending', 'voting', 'failed')
    and item.submitted_by is distinct from v_user_id
    and not exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    and not exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = item.id
        and source.source_user_id = v_user_id
    );

  return v_result;
end;
$$;


ALTER FUNCTION "public"."get_jury_review_queue"() OWNER TO "postgres";


COMMENT ON FUNCTION "public"."get_jury_review_queue"() IS 'DB-7 补丁：返回全部开放审核类型、完整基础资料、字段问题、投票与终审权限。';



CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
begin
  insert into public.profiles (id, email, nickname, role, role_level, quota)
  values (new.id, new.email, split_part(new.email, '@', 1), 'user', 0, 30);
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_quota"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
BEGIN
  INSERT INTO public.user_quotas (user_id, free_count)
  VALUES (new.id, 30); -- 新用户默认给 20 次
  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user_quota"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin_or_super_admin"() RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."is_admin_or_super_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_super_admin"() RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select exists(
    select 1
    from public.profiles
    where id = auth.uid()
      and (role_level = 2 or role = 'super_admin')
  );
$$;


ALTER FUNCTION "public"."is_super_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_clothes_payload"("p_clothes_id" "text") RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $_$
  select public.jury_record_payload(
    clothes.name,
    clothes.game_id,
    clothes.category,
    case
      when nullif(pg_catalog.btrim(coalesce(clothes.stars, '')), '') ~ '^[0-9]+$'
        then clothes.stars::integer
      else null
    end,
    clothes.scores,
    clothes.suit_id,
    clothes.temp_suit_name,
    clothes.tags,
    false
  )
  from public.clothes as clothes
  where clothes.id = p_clothes_id;
$_$;


ALTER FUNCTION "public"."jury_clothes_payload"("p_clothes_id" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_field_value_is_missing"("p_payload" "jsonb", "p_field" "text") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
declare
  v_left_field text;
  v_right_field text;
  v_left numeric;
  v_right numeric;
begin
  if p_field = 'tags' then
    return false;
  end if;

  if p_field = 'suit' then
    return coalesce(
      case
        when pg_catalog.jsonb_typeof(p_payload->'needs_suit_review') = 'boolean'
          then (p_payload->>'needs_suit_review')::boolean
        else true
      end,
      true
    ) or nullif(pg_catalog.btrim(coalesce(p_payload->>'temp_suit_name', '')), '') is not null;
  end if;

  case p_field
    when 'pair1' then v_left_field := 'simple'; v_right_field := 'gorgeous';
    when 'pair2' then v_left_field := 'active'; v_right_field := 'elegant';
    when 'pair3' then v_left_field := 'cute'; v_right_field := 'mature';
    when 'pair4' then v_left_field := 'pure'; v_right_field := 'sexy';
    when 'pair5' then v_left_field := 'cool'; v_right_field := 'warm';
    else
      return coalesce(p_payload->p_field = 'null'::jsonb, true);
  end case;

  if pg_catalog.jsonb_typeof(p_payload->'scores'->v_left_field) <> 'number'
    or pg_catalog.jsonb_typeof(p_payload->'scores'->v_right_field) <> 'number' then
    return true;
  end if;

  v_left := (p_payload->'scores'->>v_left_field)::numeric;
  v_right := (p_payload->'scores'->>v_right_field)::numeric;
  return not (
    (v_left > 0 and v_right = 0)
    or (v_right > 0 and v_left = 0)
  );
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return true;
end;
$$;


ALTER FUNCTION "public"."jury_field_value_is_missing"("p_payload" "jsonb", "p_field" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_payload_field_value"("p_payload" "jsonb", "p_field" "text") RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select case p_field
    when 'pair1' then pg_catalog.jsonb_build_object(
      'simple', p_payload->'scores'->'simple',
      'gorgeous', p_payload->'scores'->'gorgeous'
    )
    when 'pair2' then pg_catalog.jsonb_build_object(
      'active', p_payload->'scores'->'active',
      'elegant', p_payload->'scores'->'elegant'
    )
    when 'pair3' then pg_catalog.jsonb_build_object(
      'cute', p_payload->'scores'->'cute',
      'mature', p_payload->'scores'->'mature'
    )
    when 'pair4' then pg_catalog.jsonb_build_object(
      'pure', p_payload->'scores'->'pure',
      'sexy', p_payload->'scores'->'sexy'
    )
    when 'pair5' then pg_catalog.jsonb_build_object(
      'cool', p_payload->'scores'->'cool',
      'warm', p_payload->'scores'->'warm'
    )
    when 'suit' then pg_catalog.jsonb_build_object(
      'suit_id', p_payload->'suit_id',
      'temp_suit_name', p_payload->'temp_suit_name',
      'needs_suit_review', p_payload->'needs_suit_review'
    )
    else coalesce(p_payload->p_field, 'null'::jsonb)
  end;
$$;


ALTER FUNCTION "public"."jury_payload_field_value"("p_payload" "jsonb", "p_field" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_payload_is_complete"("p_payload" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $_$
declare
  v_stars numeric;
begin
  if p_payload is null
    or pg_catalog.jsonb_typeof(p_payload) <> 'object'
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) <> 9
    or not (p_payload ?& array[
      'name', 'game_id', 'category', 'stars', 'scores',
      'suit_id', 'temp_suit_name', 'tags', 'needs_suit_review'
    ])
    or pg_catalog.jsonb_typeof(p_payload->'name') <> 'string'
    or nullif(pg_catalog.btrim(p_payload->>'name'), '') is null
    or pg_catalog.jsonb_typeof(p_payload->'game_id') <> 'string'
    or pg_catalog.btrim(p_payload->>'game_id') !~ '^[0-9]+$'
    or pg_catalog.jsonb_typeof(p_payload->'category') <> 'string'
    or nullif(pg_catalog.btrim(p_payload->>'category'), '') is null
    or pg_catalog.jsonb_typeof(p_payload->'stars') <> 'number'
    or not public.jury_scores_are_complete(p_payload->'scores')
    or pg_catalog.jsonb_typeof(p_payload->'needs_suit_review') <> 'boolean'
    or (p_payload->>'needs_suit_review')::boolean
    or p_payload->'temp_suit_name' <> 'null'::jsonb
    or not (
      p_payload->'tags' = 'null'::jsonb
      or pg_catalog.jsonb_typeof(p_payload->'tags') = 'string'
    )
    or not (
      p_payload->'suit_id' = 'null'::jsonb
      or pg_catalog.jsonb_typeof(p_payload->'suit_id') = 'string'
    ) then
    return false;
  end if;

  v_stars := (p_payload->>'stars')::numeric;
  return v_stars = pg_catalog.trunc(v_stars) and v_stars between 1 and 6;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$_$;


ALTER FUNCTION "public"."jury_payload_is_complete"("p_payload" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_pending_payload"("p_pending_id" bigint) RETURNS "jsonb"
    LANGUAGE "sql" STABLE
    SET "search_path" TO ''
    AS $$
  select public.jury_record_payload(
    pending.name,
    pending.game_id,
    pending.category,
    pending.stars,
    pending.scores,
    pending.suit_id,
    pending.temp_suit_name,
    pending.tags,
    pending.needs_suit_review
  )
  from public.pending_clothes as pending
  where pending.id = p_pending_id;
$$;


ALTER FUNCTION "public"."jury_pending_payload"("p_pending_id" bigint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_record_payload"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) RETURNS "jsonb"
    LANGUAGE "sql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
  select pg_catalog.jsonb_build_object(
    'name', nullif(pg_catalog.btrim(coalesce(p_name, '')), ''),
    'game_id', nullif(pg_catalog.btrim(coalesce(p_game_id, '')), ''),
    'category', nullif(pg_catalog.btrim(coalesce(p_category, '')), ''),
    'stars', p_stars,
    'scores', coalesce(p_scores, '{}'::jsonb),
    'suit_id', case when p_suit_id is null then null else p_suit_id::text end,
    'temp_suit_name', nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), ''),
    'tags', nullif(pg_catalog.btrim(coalesce(p_tags, '')), ''),
    'needs_suit_review', coalesce(p_needs_suit_review, false)
  );
$$;


ALTER FUNCTION "public"."jury_record_payload"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."jury_scores_are_complete"("p_scores" "jsonb") RETURNS boolean
    LANGUAGE "plpgsql" IMMUTABLE
    SET "search_path" TO ''
    AS $$
declare
  v_left_fields constant text[] := array['simple', 'active', 'cute', 'pure', 'cool'];
  v_right_fields constant text[] := array['gorgeous', 'elegant', 'mature', 'sexy', 'warm'];
  v_index integer;
  v_left numeric;
  v_right numeric;
begin
  if p_scores is null
    or pg_catalog.jsonb_typeof(p_scores) <> 'object'
    or (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_scores)) <> 10
    or not (p_scores ?& array[
      'simple', 'gorgeous', 'active', 'elegant', 'cute',
      'mature', 'pure', 'sexy', 'cool', 'warm'
    ]) then
    return false;
  end if;

  for v_index in 1..5 loop
    if pg_catalog.jsonb_typeof(p_scores->v_left_fields[v_index]) <> 'number'
      or pg_catalog.jsonb_typeof(p_scores->v_right_fields[v_index]) <> 'number' then
      return false;
    end if;

    v_left := (p_scores->>v_left_fields[v_index])::numeric;
    v_right := (p_scores->>v_right_fields[v_index])::numeric;
    if not (
      (v_left > 0 and v_right = 0)
      or (v_right > 0 and v_left = 0)
    ) then
      return false;
    end if;
  end loop;

  return true;
exception
  when invalid_text_representation or numeric_value_out_of_range then
    return false;
end;
$$;


ALTER FUNCTION "public"."jury_scores_are_complete"("p_scores" "jsonb") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
declare
  known_tags text[] := array[
    '现代流行', '欧式古典', '中式古典', '中式现代', '波西米亚', '森女系列',
    '洛丽塔', '哥特风', '女仆装', '童话系', '未来系', '侠客联盟',
    '民国服饰', '民族风', '英伦', '学院系', '运动系', '居家服',
    '晚礼服', '婚纱', '旗袍', '军装', '工装风', '航海风',
    '乐队风', '舞者', '女神系', '大小姐', '兔女郎', '医务使者',
    '雨季装备', '冬装', '泳装', '沐浴', '围裙', '碎花',
    '防晒', '睡衣', '动物系', '潮酷风', '轻熟风', '异域风',
    '中性风',
    '简约+200', '简约+500', '简约+800', '简约+1200', '简约+1500',
    '华丽+200', '华丽+500', '华丽+800', '华丽+1200', '华丽+1500',
    '活泼+200', '活泼+500', '活泼+800', '活泼+1200', '活泼+1500',
    '优雅+200', '优雅+500', '优雅+800', '优雅+1200', '优雅+1500',
    '可爱+200', '可爱+500', '可爱+800', '可爱+1200', '可爱+1500',
    '成熟+200', '成熟+500', '成熟+800', '成熟+1200', '成熟+1500',
    '清纯+200', '清纯+500', '清纯+800', '清纯+1200', '清纯+1500',
    '性感+200', '性感+500', '性感+800', '性感+1200', '性感+1500',
    '清凉+200', '清凉+500', '清凉+800', '清凉+1200'
  ];
  parts text[];
  part text;
  known_tag text;
  ordered_known_tag text;
  result text[] := array[]::text[];
  matched boolean;
begin
  if nullif(trim(coalesce(p_tags, '')), '') is null then
    return null;
  end if;

  parts := regexp_split_to_array(p_tags, '[,，、;；]+');

  foreach part in array parts loop
    part := trim(part);
    continue when part = '';
    matched := false;

    for ordered_known_tag in
      select tag
      from unnest(known_tags) as tag
      where part = tag or position(tag in part) > 0
      order by position(tag in part), length(tag) desc
    loop
      if not ordered_known_tag = any(result) then
        result := array_append(result, ordered_known_tag);
      end if;
      matched := true;
    end loop;

    if not matched then
      if not part = any(result) then
        result := array_append(result, part);
        end if;
    end if;
  end loop;

  if coalesce(array_length(result, 1), 0) = 0 then
    return null;
  end if;

  return array_to_string(result, ', ');
end;
$$;


ALTER FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) RETURNS "text"
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case p_role_level
    when 2 then 'super_admin'
    when 1 then 'admin'
    else 'user'
  end;
$$;


ALTER FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."profile_role_to_level"("p_role" "text") RETURNS smallint
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select case p_role
    when 'super_admin' then 2::smallint
    when 'admin' then 1::smallint
    else 0::smallint
  end;
$$;


ALTER FUNCTION "public"."profile_role_to_level"("p_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_needs_suit_review" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_user_id uuid := (select auth.uid());
  v_game_id text := pg_catalog.btrim(coalesce(p_game_id, ''));
  v_temp_suit_name text := nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '');
  v_tags text := nullif(pg_catalog.btrim(coalesce(p_tags, '')), '');
  v_needs_suit_review boolean := coalesce(p_needs_suit_review, false);
  v_input_payload jsonb;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_pending_id bigint;
  v_existing_item_id uuid;
  v_re_review_item_id uuid;
  v_existing_user_in_cohort boolean := false;
  v_distinct_user_count integer := 0;
  v_distinct_payload_count integer := 0;
  v_route_to_review boolean := false;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交图鉴申请';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;
  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;
  if nullif(v_game_id, '') is null then
    raise exception '短编号不能为空';
  end if;
  if v_game_id !~ '^[0-9]+$' then
    raise exception '短编号只允许填写数字';
  end if;
  if p_stars is null then
    raise exception '星级不能为空';
  end if;
  if p_scores is null or pg_catalog.jsonb_typeof(p_scores) <> 'object' then
    raise exception '属性分值不能为空';
  end if;
  if v_needs_suit_review and (p_suit_id is not null or v_temp_suit_name is not null) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_input_payload := public.jury_record_payload(
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    v_temp_suit_name,
    v_tags,
    v_needs_suit_review
  );

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|category_game|' || p_category || '|' || v_game_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|name_category|' || p_name || '|' || p_category, 0)
  );

  select pending.id
    into v_pending_id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.submitted_by = v_user_id
    and public.jury_pending_payload(pending.id) is not distinct from v_input_payload
  order by pending.created_at, pending.id
  limit 1
  for update;

  if found then
    select item.id
      into v_existing_item_id
    from public.re_review_item_sources as source
    join public.re_review_items as item
      on item.id = source.re_review_item_id
      and item.status in ('pending', 'voting', 'failed')
    where source.source_pending_id = v_pending_id
    order by item.created_at, item.id
    limit 1;

    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id,
      'review_required', v_existing_item_id is not null,
      're_review_item_id', v_existing_item_id
    );
  end if;

  select clothes.*
    into v_existing_clothes
  from public.clothes as clothes
  where (
      clothes.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id
    )
    or (
      clothes.name is not distinct from p_name
      and clothes.category is not distinct from p_category
    )
  order by
    case
      when clothes.category is not distinct from p_category
        and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id then 0
      else 1
    end,
    clothes.id
  limit 1
  for update;

  v_clothes_exists := found;

  if v_clothes_exists
    and (
      public.jury_clothes_payload(v_existing_clothes.id)
      || pg_catalog.jsonb_build_object('needs_suit_review', v_needs_suit_review)
    ) is distinct from v_input_payload then
    v_route_to_review := true;
  end if;

  select item.id
    into v_existing_item_id
  from public.re_review_items as item
  where item.status in ('pending', 'voting', 'failed')
    and (
      (v_clothes_exists and item.identity_key = 'clothes|' || v_existing_clothes.id)
      or item.identity_key = 'entry|game|' || p_category || '|' || v_game_id
      or item.identity_key = 'entry|name|' || p_category || '|'
        || pg_catalog.lower(pg_catalog.btrim(p_name))
    )
  order by item.created_at, item.id
  limit 1
  for update;

  if v_existing_item_id is not null then
    v_route_to_review := true;
  end if;

  if not v_clothes_exists and not v_route_to_review then
    with earliest_per_user as (
      select distinct on (pending.submitted_by)
        pending.submitted_by,
        public.jury_pending_payload(pending.id) as payload
      from public.pending_clothes as pending
      where pending.status = 'pending'
        and pending.submitted_by is not null
        and (
          (
            pending.category is not distinct from p_category
            and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
          )
          or (
            pending.name is not distinct from p_name
            and pending.category is not distinct from p_category
          )
        )
      order by pending.submitted_by, pending.created_at, pending.id
    ), cohort as (
      select earliest.submitted_by, earliest.payload
      from earliest_per_user as earliest

      union all

      select v_user_id, v_input_payload
      where not exists (
        select 1
        from earliest_per_user as earliest
        where earliest.submitted_by = v_user_id
      )
    )
    select
      pg_catalog.count(*)::integer,
      pg_catalog.count(distinct cohort.payload::text)::integer,
      exists (
        select 1
        from earliest_per_user as earliest
        where earliest.submitted_by = v_user_id
      )
      into v_distinct_user_count, v_distinct_payload_count, v_existing_user_in_cohort
    from cohort;

    if v_distinct_user_count >= 5 and v_distinct_payload_count > 1 then
      v_route_to_review := true;
    end if;
  end if;

  if v_route_to_review then
    insert into public.pending_clothes (
      name,
      game_id,
      category,
      stars,
      scores,
      suit_id,
      temp_suit_name,
      tags,
      submitted_by,
      status,
      needs_suit_review
    )
    values (
      p_name,
      v_game_id,
      p_category,
      p_stars,
      p_scores,
      p_suit_id,
      v_temp_suit_name,
      v_tags,
      v_user_id,
      'pending',
      v_needs_suit_review
    )
    returning id into v_pending_id;

    if p_suit_id is null and v_temp_suit_name is not null then
      insert into public.pending_suits (name, submitted_by, status)
      values (v_temp_suit_name, v_user_id, 'pending');
    end if;

    v_re_review_item_id := public.ensure_full_jury_review_item(
      v_pending_id,
      case when v_clothes_exists then v_existing_clothes.id else null end,
      not v_clothes_exists
    );

    if v_re_review_item_id is null then
      raise exception '审核事项创建失败，已回滚本次提交';
    end if;

    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id,
      'review_required', true,
      're_review_item_id', v_re_review_item_id
    );
  end if;

  v_result := public.submit_clothing_contribution_db7_core(
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    v_temp_suit_name,
    v_tags,
    v_needs_suit_review
  );

  return v_result || pg_catalog.jsonb_build_object(
    'review_required', (v_result->>'re_review_item_id') is not null,
    're_review_item_id', v_result->'re_review_item_id'
  );
end;
$_$;


ALTER FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) IS 'DB-7 补丁：五位不同用户仍不一致或与正式资料冲突时，原子转入整件全字段审核；兼容原参数与返回字段。';



CREATE OR REPLACE FUNCTION "public"."submit_clothing_contribution_db7_core"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_needs_suit_review" boolean DEFAULT false) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $_$
declare
  v_user_id uuid := (select auth.uid());
  v_game_id text := pg_catalog.btrim(coalesce(p_game_id, ''));
  v_normalized_temp_suit_name text := nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '');
  v_normalized_tags text := nullif(pg_catalog.btrim(coalesce(p_tags, '')), '');
  v_needs_suit_review boolean := coalesce(p_needs_suit_review, false);
  v_can_auto_approve boolean;
  v_pending_id bigint;
  v_matching_pending_ids bigint[] := '{}'::bigint[];
  v_matching_count integer := 0;
  v_effective_user_ids uuid[] := '{}'::uuid[];
  v_effective_pending_ids bigint[] := '{}'::bigint[];
  v_effective_created_ats timestamptz[] := '{}'::timestamptz[];
  v_effective_contributor_count integer := 0;
  v_clothes_id text;
  v_existing_clothes public.clothes%rowtype;
  v_clothes_exists boolean := false;
  v_event_hash text;
  v_event_id uuid;
  v_contribution_id uuid;
  v_contribution_count integer := 0;
  v_points_count integer := 0;
  v_wardrobe_count integer := 0;
  v_approved_pending_count integer := 0;
  v_existing_event_count integer := 0;
  v_matching_contribution_count integer := 0;
  v_matching_points_count integer := 0;
  v_matching_wardrobe_count integer := 0;
  v_re_review_item_id uuid;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交图鉴申请';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(v_game_id, '') is null then
    raise exception '短编号不能为空';
  end if;

  if v_game_id !~ '^[0-9]+$' then
    raise exception '短编号只允许填写数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  if v_needs_suit_review
    and (p_suit_id is not null or v_normalized_temp_suit_name is not null) then
    raise exception '所属套装待确认不能同时填写已有套装或新套装名称';
  end if;

  v_can_auto_approve := p_suit_id is not null
    or v_normalized_temp_suit_name is not null
    or v_needs_suit_review;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|category_game|' || p_category || '|' || v_game_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('db5|name_category|' || p_name || '|' || p_category, 0)
  );

  select clothes.*
    into v_existing_clothes
  from public.clothes as clothes
  where clothes.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(clothes.game_id, '')) = v_game_id
  order by clothes.id
  limit 1
  for update;

  v_clothes_exists := found;

  if not v_clothes_exists then
    select clothes.*
      into v_existing_clothes
    from public.clothes as clothes
    where clothes.name is not distinct from p_name
      and clothes.category is not distinct from p_category
    order by clothes.id
    limit 1
    for update;

    v_clothes_exists := found;
  end if;

  if v_clothes_exists then
    if v_existing_clothes.name is distinct from p_name
      or v_existing_clothes.category is distinct from p_category
      or pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')) is distinct from v_game_id
      or pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')) is distinct from p_stars::text
      or v_existing_clothes.scores is distinct from p_scores
      or v_existing_clothes.suit_id is distinct from p_suit_id
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '')
        is distinct from v_normalized_temp_suit_name
      or nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '')
        is distinct from v_normalized_tags then
      raise exception '正式库已存在同分类短编号或同名记录，但数据与本次提交不一致';
    end if;

    perform pending.id
    from public.pending_clothes as pending
    where pending.status = 'approved'
      and pending.needs_suit_review = v_needs_suit_review
      and pending.name is not distinct from p_name
      and pending.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
      and pending.stars is not distinct from p_stars
      and pending.scores is not distinct from p_scores
      and pending.suit_id is not distinct from p_suit_id
      and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
        is not distinct from v_normalized_temp_suit_name
      and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
        is not distinct from v_normalized_tags
    order by pending.id
    for update;

    select
      coalesce(pg_catalog.array_agg(pending.id order by pending.id), '{}'::bigint[]),
      pg_catalog.count(*)::integer
      into v_matching_pending_ids, v_matching_count
    from public.pending_clothes as pending
    where pending.status = 'approved'
      and pending.needs_suit_review = v_needs_suit_review
      and pending.name is not distinct from p_name
      and pending.category is not distinct from p_category
      and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
      and pending.stars is not distinct from p_stars
      and pending.scores is not distinct from p_scores
      and pending.suit_id is not distinct from p_suit_id
      and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
        is not distinct from v_normalized_temp_suit_name
      and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
        is not distinct from v_normalized_tags;

    with earliest_per_user as (
      select distinct on (pending.submitted_by)
        pending.submitted_by as user_id,
        pending.id as source_pending_id,
        pending.created_at as source_created_at
      from public.pending_clothes as pending
      where pending.id = any(v_matching_pending_ids)
        and pending.submitted_by is not null
      order by pending.submitted_by, pending.created_at, pending.id
    ),
    effective_contributors as (
      select
        earliest.user_id,
        earliest.source_pending_id,
        earliest.source_created_at,
        pg_catalog.row_number() over (
          order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
        )::smallint as contribution_rank
      from earliest_per_user as earliest
      order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      limit 5
    )
    select
      coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
      coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
      coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
      into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
    from effective_contributors as effective;

    v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

    if v_effective_contributor_count = 5 then
      v_event_hash := pg_catalog.md5(
        'auto_entry|'
        || v_existing_clothes.id
        || '|'
        || pg_catalog.array_to_string(v_matching_pending_ids, ',')
      );
      v_event_id := (
        pg_catalog.substr(v_event_hash, 1, 8) || '-'
        || pg_catalog.substr(v_event_hash, 9, 4) || '-'
        || pg_catalog.substr(v_event_hash, 13, 4) || '-'
        || pg_catalog.substr(v_event_hash, 17, 4) || '-'
        || pg_catalog.substr(v_event_hash, 21, 12)
      )::uuid;

      select pg_catalog.count(*)::integer
        into v_existing_event_count
      from public.clothing_contributions as contribution
      where contribution.event_id = v_event_id;

      select pg_catalog.count(*)::integer
        into v_matching_contribution_count
      from pg_catalog.generate_subscripts(v_effective_user_ids, 1) as expected(array_index)
      join public.clothing_contributions as contribution
        on contribution.event_id = v_event_id
        and contribution.clothes_id = v_existing_clothes.id
        and contribution.user_id = v_effective_user_ids[expected.array_index]
        and contribution.source_pending_id = v_effective_pending_ids[expected.array_index]
        and contribution.source_created_at = v_effective_created_ats[expected.array_index]
        and contribution.contribution_rank = expected.array_index::smallint
        and contribution.contribution_type = 'auto_entry';

      select pg_catalog.count(*)::integer
        into v_matching_points_count
      from public.clothing_contributions as contribution
      join public.points_ledger as ledger
        on ledger.source_id = contribution.id
        and ledger.user_id = contribution.user_id
        and ledger.delta = 10
        and ledger.status = 'awarded'
        and ledger.source_type = 'clothing_contribution'
        and ledger.reversal_of is null
      where contribution.event_id = v_event_id;

      select pg_catalog.count(*)::integer
        into v_matching_wardrobe_count
      from pg_catalog.unnest(v_effective_user_ids) as expected(user_id)
      join public.user_wardrobes as wardrobe
        on wardrobe.user_id = expected.user_id
        and coalesce(wardrobe.owned_clothes, '[]'::jsonb)
          @> pg_catalog.jsonb_build_array(v_existing_clothes.id);

      if v_existing_event_count = v_effective_contributor_count
        and v_matching_contribution_count = v_effective_contributor_count
        and v_matching_points_count = v_effective_contributor_count
        and v_matching_wardrobe_count = v_effective_contributor_count then
        if v_needs_suit_review then
          v_re_review_item_id := public.ensure_missing_suit_re_review_item(
            v_existing_clothes.id,
            v_matching_pending_ids,
            false
          );
        end if;

        return pg_catalog.jsonb_build_object(
          'auto_approved', true,
          'clothes_id', v_existing_clothes.id,
          'matched_pending_count', v_matching_count,
          'wardrobe_updated_count', v_matching_wardrobe_count,
          're_review_item_id', v_re_review_item_id
        );
      end if;
    end if;

    if exists (
      select 1
      from public.clothing_contributions as contribution
      where contribution.clothes_id = v_existing_clothes.id
        and contribution.contribution_type = 'auto_entry'
    ) then
      raise exception '自动入库正式服装已存在，但来源、贡献、积分、衣柜或重审事实不完整；禁止静默补写';
    end if;

    raise exception '正式库已存在该服装，请刷新页面后使用现有图鉴条目';
  end if;

  select pending.id
    into v_pending_id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.submitted_by = v_user_id
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags
  order by pending.created_at, pending.id
  limit 1
  for update;

  if found then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  insert into public.pending_clothes (
    name,
    game_id,
    category,
    stars,
    scores,
    suit_id,
    temp_suit_name,
    tags,
    submitted_by,
    status,
    needs_suit_review
  )
  values (
    p_name,
    v_game_id,
    p_category,
    p_stars,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags,
    v_user_id,
    'pending',
    v_needs_suit_review
  )
  returning id into v_pending_id;

  if p_suit_id is null and v_normalized_temp_suit_name is not null then
    insert into public.pending_suits (name, submitted_by, status)
    values (p_temp_suit_name, v_user_id, 'pending');
  end if;

  if not v_can_auto_approve then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  perform pending.id
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags
  order by pending.id
  for update;

  select
    coalesce(pg_catalog.array_agg(pending.id order by pending.id), '{}'::bigint[]),
    pg_catalog.count(*)::integer
    into v_matching_pending_ids, v_matching_count
  from public.pending_clothes as pending
  where pending.status = 'pending'
    and pending.needs_suit_review = v_needs_suit_review
    and pending.name is not distinct from p_name
    and pending.category is not distinct from p_category
    and pg_catalog.btrim(coalesce(pending.game_id, '')) = v_game_id
    and pending.stars is not distinct from p_stars
    and pending.scores is not distinct from p_scores
    and pending.suit_id is not distinct from p_suit_id
    and nullif(pg_catalog.btrim(coalesce(pending.temp_suit_name, '')), '')
      is not distinct from v_normalized_temp_suit_name
    and nullif(pg_catalog.btrim(coalesce(pending.tags, '')), '')
      is not distinct from v_normalized_tags;

  with earliest_per_user as (
    select distinct on (pending.submitted_by)
      pending.submitted_by as user_id,
      pending.id as source_pending_id,
      pending.created_at as source_created_at
    from public.pending_clothes as pending
    where pending.id = any(v_matching_pending_ids)
      and pending.submitted_by is not null
    order by pending.submitted_by, pending.created_at, pending.id
  ),
  effective_contributors as (
    select
      earliest.user_id,
      earliest.source_pending_id,
      earliest.source_created_at,
      pg_catalog.row_number() over (
        order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
      )::smallint as contribution_rank
    from earliest_per_user as earliest
    order by earliest.source_created_at, earliest.source_pending_id, earliest.user_id
    limit 5
  )
  select
    coalesce(pg_catalog.array_agg(effective.user_id order by effective.contribution_rank), '{}'::uuid[]),
    coalesce(pg_catalog.array_agg(effective.source_pending_id order by effective.contribution_rank), '{}'::bigint[]),
    coalesce(pg_catalog.array_agg(effective.source_created_at order by effective.contribution_rank), '{}'::timestamptz[])
    into v_effective_user_ids, v_effective_pending_ids, v_effective_created_ats
  from effective_contributors as effective;

  v_effective_contributor_count := pg_catalog.cardinality(v_effective_user_ids);

  if v_effective_contributor_count < 5 then
    return pg_catalog.jsonb_build_object(
      'auto_approved', false,
      'pending_id', v_pending_id
    );
  end if;

  v_clothes_id := 'custom_' || pg_catalog.replace(pg_catalog.gen_random_uuid()::text, '-', '');
  v_event_hash := pg_catalog.md5(
    'auto_entry|'
    || v_clothes_id
    || '|'
    || pg_catalog.array_to_string(v_matching_pending_ids, ',')
  );
  v_event_id := (
    pg_catalog.substr(v_event_hash, 1, 8) || '-'
    || pg_catalog.substr(v_event_hash, 9, 4) || '-'
    || pg_catalog.substr(v_event_hash, 13, 4) || '-'
    || pg_catalog.substr(v_event_hash, 17, 4) || '-'
    || pg_catalog.substr(v_event_hash, 21, 12)
  )::uuid;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_matching_pending_ids)
  ) then
    raise exception '本次自动入库来源已存在贡献事实，但 pending 尚未完成；请人工核对';
  end if;

  insert into public.clothes (
    id,
    name,
    game_id,
    category,
    stars,
    scores,
    suit_id,
    temp_suit_name,
    tags
  )
  values (
    v_clothes_id,
    p_name,
    v_game_id,
    p_category,
    p_stars::text,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags
  );

  if v_needs_suit_review then
    v_re_review_item_id := public.ensure_missing_suit_re_review_item(
      v_clothes_id,
      v_matching_pending_ids,
      true
    );
  end if;

  for v_index in 1..v_effective_contributor_count loop
    insert into public.clothing_contributions (
      event_id,
      clothes_id,
      user_id,
      source_pending_id,
      contribution_type,
      contribution_rank,
      source_created_at
    )
    values (
      v_event_id,
      v_clothes_id,
      v_effective_user_ids[v_index],
      v_effective_pending_ids[v_index],
      'auto_entry',
      v_index::smallint,
      v_effective_created_ats[v_index]
    )
    returning id into v_contribution_id;

    v_contribution_count := v_contribution_count + 1;

    insert into public.points_ledger (
      user_id,
      delta,
      status,
      source_type,
      source_id
    )
    values (
      v_effective_user_ids[v_index],
      10,
      'awarded',
      'clothing_contribution',
      v_contribution_id
    );

    v_points_count := v_points_count + 1;
  end loop;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(
    v_effective_user_ids,
    v_clothes_id
  );

  if v_contribution_count <> v_effective_contributor_count
    or v_points_count <> v_effective_contributor_count
    or v_wardrobe_count <> v_effective_contributor_count then
    raise exception '贡献、积分或衣柜写回数量异常，已回滚本次自动入库';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_matching_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_matching_count then
    raise exception 'pending 通过数量异常，已回滚本次自动入库';
  end if;

  return pg_catalog.jsonb_build_object(
    'auto_approved', true,
    'clothes_id', v_clothes_id,
    'matched_pending_count', v_approved_pending_count,
    'wardrobe_updated_count', v_wardrobe_count,
    're_review_item_id', v_re_review_item_id
  );
end;
$_$;


ALTER FUNCTION "public"."submit_clothing_contribution_db7_core"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."submit_clothing_contribution_db7_core"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) IS 'DB-6：兼容原提交参数；五位不同用户提交“所属套装待确认”的一致完整资料后，同事务自动入库、创建待补套装重审来源链并完成贡献、积分和衣柜写回。';



CREATE OR REPLACE FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO ''
    AS $$
declare
  v_user_id uuid := (select auth.uid());
  v_item public.re_review_items%rowtype;
  v_candidate public.re_review_candidates%rowtype;
  v_base_payload jsonb;
  v_issues jsonb;
  v_candidate_payload jsonb;
  v_field text;
  v_suit_id uuid;
  v_is_legacy_missing_suit boolean := false;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交补充内容';
  end if;

  select item.*
    into v_item
  from public.re_review_items as item
  where item.id = p_re_review_item_id
  for update;

  if not found then
    raise exception '审核事项不存在';
  end if;

  if v_item.submitted_by is not distinct from v_user_id
    or exists (
      select 1
      from public.pending_clothes as primary_source
      where primary_source.id = v_item.source_pending_id
        and primary_source.submitted_by = v_user_id
    )
    or exists (
      select 1
      from public.re_review_item_sources as source
      where source.re_review_item_id = v_item.id
        and source.source_user_id = v_user_id
    ) then
    raise exception using
      errcode = '42501',
      message = '不能处理自己提交或参与过的数据';
  end if;

  select candidate.*
    into v_candidate
  from public.re_review_candidates as candidate
  where candidate.re_review_item_id = v_item.id
    and candidate.status = 'voting'
  order by candidate.created_at desc, candidate.id
  limit 1
  for update;

  if found then
    if v_candidate.submitted_by is not distinct from v_user_id
      and (
        v_candidate.payload is not distinct from p_payload
        or (
          v_item.reason = 'missing_suit'
          and pg_catalog.jsonb_typeof(p_payload) = 'object'
          and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) = 1
          and p_payload ? 'suit_id'
          and v_candidate.payload->'suit_id' is not distinct from p_payload->'suit_id'
        )
      ) then
      return pg_catalog.jsonb_build_object(
        're_review_item_id', v_item.id,
        'candidate_id', v_candidate.id,
        'candidate_status', v_candidate.status,
        'item_status', v_item.status,
        'idempotent', true
      );
    end if;
    raise exception '该事项已经有待审核内容';
  end if;

  if v_item.status not in ('pending', 'failed') then
    raise exception '当前事项不能提交新的补充内容';
  end if;

  if v_item.payload ? 'base_record' then
    v_base_payload := v_item.payload->'base_record';
    v_issues := coalesce(v_item.payload->'issues', '[]'::jsonb);
  else
    v_base_payload := public.jury_clothes_payload(v_item.clothes_id);
    v_issues := case
      when v_item.reason = 'missing_suit' then
        pg_catalog.jsonb_build_array(
          pg_catalog.jsonb_build_object('field', 'suit', 'kind', 'missing')
        )
      else '[]'::jsonb
    end;
  end if;

  if v_base_payload is null or pg_catalog.jsonb_array_length(v_issues) = 0 then
    raise exception '该事项没有可补充或需要核对的字段';
  end if;

  v_is_legacy_missing_suit := v_item.reason = 'missing_suit'
    and pg_catalog.jsonb_typeof(p_payload) = 'object'
    and (select pg_catalog.count(*) from pg_catalog.jsonb_object_keys(p_payload)) = 1
    and p_payload ? 'suit_id';

  v_candidate_payload := case
    when v_is_legacy_missing_suit
      then v_base_payload || p_payload || pg_catalog.jsonb_build_object(
        'temp_suit_name', null,
        'needs_suit_review', false
      )
    else p_payload
  end;

  if not v_is_legacy_missing_suit
    and not public.jury_payload_is_complete(v_candidate_payload) then
    raise exception '请补充完整的服装资料后再提交';
  end if;

  if v_candidate_payload->'suit_id' <> 'null'::jsonb then
    begin
      v_suit_id := (v_candidate_payload->>'suit_id')::uuid;
    exception when invalid_text_representation then
      raise exception '所属套装格式无效';
    end;

    if not exists (select 1 from public.suits as suit where suit.id = v_suit_id) then
      raise exception '所选套装不存在，请刷新后重试';
    end if;
  end if;

  foreach v_field in array array[
    'name', 'game_id', 'category', 'stars',
    'pair1', 'pair2', 'pair3', 'pair4', 'pair5',
    'suit', 'tags'
  ] loop
    if not exists (
      select 1
      from pg_catalog.jsonb_array_elements(v_issues) as issue(value)
      where issue.value->>'field' = v_field
    ) and public.jury_payload_field_value(v_candidate_payload, v_field)
      is distinct from public.jury_payload_field_value(v_base_payload, v_field) then
      raise exception '只能修改页面列出的缺失或冲突字段';
    end if;
  end loop;

  insert into public.re_review_candidates (
    re_review_item_id,
    payload,
    submitted_by,
    status
  )
  values (
    v_item.id,
    case when v_is_legacy_missing_suit then p_payload else v_candidate_payload end,
    v_user_id,
    'voting'
  )
  returning * into v_candidate;

  update public.re_review_items
  set
    status = 'voting',
    updated_at = pg_catalog.now(),
    resolved_by = null,
    resolved_at = null
  where id = v_item.id;

  return pg_catalog.jsonb_build_object(
    're_review_item_id', v_item.id,
    'candidate_id', v_candidate.id,
    'candidate_status', v_candidate.status,
    'item_status', 'voting',
    'idempotent', false
  );
end;
$$;


ALTER FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") OWNER TO "postgres";


COMMENT ON FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") IS 'DB-7 补丁：提交完整服装资料，只允许修改审核事项列出的缺失或冲突字段；相同重试幂等。';



CREATE OR REPLACE FUNCTION "public"."sync_profile_role_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
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


ALTER FUNCTION "public"."sync_profile_role_fields"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "email" "text",
    "nickname" "text",
    "role" "text" DEFAULT 'user'::"text",
    "quota" integer DEFAULT 30,
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()),
    "username" "text",
    "total_points" integer DEFAULT 0,
    "current_month_points" integer DEFAULT 0,
    "monthly_action_count" integer DEFAULT 0,
    "role_level" smallint DEFAULT 0 NOT NULL,
    CONSTRAINT "profiles_role_level_check" CHECK (("role_level" = ANY (ARRAY[0, 1, 2])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."update_profile_username"("p_username" "text") RETURNS "public"."profiles"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_username text := trim(coalesce(p_username, ''));
  v_profile public.profiles;
begin
  if v_user_id is null then
    raise exception '请先登录后再修改代号';
  end if;

  if v_username = '' then
    raise exception '用户名不能为空';
  end if;

  if char_length(v_username) > 24 then
    raise exception '用户名最多 24 个字符';
  end if;

  if v_username like '匿名搭配师\_%' escape '\' then
    raise exception '不能使用系统保留的匿名格式';
  end if;

  update public.profiles
  set username = v_username,
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  if not found then
    raise exception '未找到当前用户档案';
  end if;

  return v_profile;
end;
$$;


ALTER FUNCTION "public"."update_profile_username"("p_username" "text") OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."app_errors" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "timezone"('utc'::"text", "now"()) NOT NULL,
    "user_id" "uuid",
    "action_name" "text",
    "error_message" "text",
    "error_stack" "text",
    "user_agent" "text"
);


ALTER TABLE "public"."app_errors" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clothes" (
    "id" character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "category" "text",
    "stars" "text",
    "tags" "text",
    "scores" "jsonb",
    "game_id" "text",
    "suit_id" "uuid",
    "temp_suit_name" "text"
);


ALTER TABLE "public"."clothes" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."clothing_contributions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "event_id" "uuid" NOT NULL,
    "clothes_id" character varying NOT NULL,
    "user_id" "uuid",
    "source_pending_id" bigint NOT NULL,
    "contribution_type" "text" NOT NULL,
    "contribution_rank" smallint NOT NULL,
    "source_created_at" timestamp with time zone NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "clothing_contributions_rank_check" CHECK ((("contribution_rank" >= 1) AND ("contribution_rank" <= 5))),
    CONSTRAINT "clothing_contributions_type_check" CHECK (("contribution_type" = ANY (ARRAY['auto_entry'::"text", 'admin_arbitration'::"text", 'existing_field_completion'::"text", 'jury_resolution'::"text"])))
);


ALTER TABLE "public"."clothing_contributions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."clothing_contributors_public" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "clothes_id",
    "contribution_rank",
    "display_name",
    "contributed_at"
   FROM "private_db2"."public_initial_contributors"() "result"("clothes_id", "contribution_rank", "display_name", "contributed_at");


ALTER VIEW "public"."clothing_contributors_public" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."jury_admin_decisions" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "candidate_id" "uuid" NOT NULL,
    "re_review_item_id" "uuid" NOT NULL,
    "admin_user_id" "uuid",
    "decision" "text" NOT NULL,
    "reason" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "jury_admin_decisions_decision_check" CHECK (("decision" = 'rejected'::"text")),
    CONSTRAINT "jury_admin_decisions_reason_check" CHECK ((NULLIF("btrim"("reason"), ''::"text") IS NOT NULL))
);


ALTER TABLE "public"."jury_admin_decisions" OWNER TO "postgres";


COMMENT ON TABLE "public"."jury_admin_decisions" IS 'DB-7 管理员独立终审事实；第一版只记录超级管理员的永久驳回。';



CREATE TABLE IF NOT EXISTS "public"."jury_votes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "candidate_id" "uuid" NOT NULL,
    "user_id" "uuid",
    "vote" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "jury_votes_vote_check" CHECK (("vote" = ANY (ARRAY['approve'::"text", 'reject'::"text"])))
);


ALTER TABLE "public"."jury_votes" OWNER TO "postgres";


COMMENT ON TABLE "public"."jury_votes" IS 'DB-7 陪审团不可变投票事实；同一用户对同一冻结候选只能投一票。';



CREATE TABLE IF NOT EXISTS "public"."pending_clothes" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "category" "text",
    "stars" integer,
    "scores" "jsonb",
    "tags" "text",
    "suit_name" "text",
    "game_id" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "submitted_by" "uuid",
    "suit_id" "uuid",
    "temp_suit_name" "text",
    "needs_suit_review" boolean DEFAULT false NOT NULL,
    CONSTRAINT "pending_clothes_needs_suit_review_check" CHECK (((NOT "needs_suit_review") OR (("suit_id" IS NULL) AND (NULLIF("btrim"(COALESCE("temp_suit_name", ''::"text")), ''::"text") IS NULL))))
);


ALTER TABLE "public"."pending_clothes" OWNER TO "postgres";


COMMENT ON COLUMN "public"."pending_clothes"."needs_suit_review" IS 'true 表示用户明确选择“所属套装待确认”；历史与默认 false 继续表示已有套装、申请新套装或纯散件。';



ALTER TABLE "public"."pending_clothes" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."pending_clothes_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."pending_suits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "submitted_by" "uuid",
    "status" "text" DEFAULT 'pending'::"text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."pending_suits" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."points_ledger" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "user_id" "uuid",
    "delta" integer NOT NULL,
    "status" "text" DEFAULT 'awarded'::"text" NOT NULL,
    "source_type" "text" NOT NULL,
    "source_id" "uuid",
    "reversal_of" "uuid",
    "occurred_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "re_review_candidate_id" "uuid",
    "jury_vote_id" "uuid",
    CONSTRAINT "points_ledger_delta_check" CHECK (("delta" <> 0)),
    CONSTRAINT "points_ledger_entry_shape_check" CHECK (((("source_type" = 'clothing_contribution'::"text") AND ("source_id" IS NOT NULL) AND ("re_review_candidate_id" IS NULL) AND ("jury_vote_id" IS NULL) AND ("reversal_of" IS NULL) AND ("delta" > 0)) OR (("source_type" = 're_review_candidate'::"text") AND ("source_id" IS NULL) AND ("re_review_candidate_id" IS NOT NULL) AND ("jury_vote_id" IS NULL) AND ("reversal_of" IS NULL) AND ("delta" > 0)) OR (("source_type" = 'jury_vote'::"text") AND ("source_id" IS NULL) AND ("re_review_candidate_id" IS NULL) AND ("jury_vote_id" IS NOT NULL) AND ("reversal_of" IS NULL) AND ("delta" = 1)) OR (("source_type" = 'reversal'::"text") AND ("source_id" IS NULL) AND ("re_review_candidate_id" IS NULL) AND ("jury_vote_id" IS NULL) AND ("reversal_of" IS NOT NULL) AND ("delta" < 0)))),
    CONSTRAINT "points_ledger_source_type_check" CHECK (("source_type" = ANY (ARRAY['clothing_contribution'::"text", 're_review_candidate'::"text", 'jury_vote'::"text", 'reversal'::"text"]))),
    CONSTRAINT "points_ledger_status_check" CHECK (("status" = 'awarded'::"text"))
);


ALTER TABLE "public"."points_ledger" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."points_leaderboard_current_month" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "leaderboard_rank",
    "display_name",
    "points",
    "is_current_user"
   FROM "private_db2"."current_month_points_leaderboard"() "result"("leaderboard_rank", "display_name", "points", "is_current_user");


ALTER VIEW "public"."points_leaderboard_current_month" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."points_leaderboard_total" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "leaderboard_rank",
    "display_name",
    "points",
    "is_current_user"
   FROM "private_db2"."total_points_leaderboard"() "result"("leaderboard_rank", "display_name", "points", "is_current_user");


ALTER VIEW "public"."points_leaderboard_total" OWNER TO "postgres";


COMMENT ON COLUMN "public"."points_ledger"."re_review_candidate_id" IS '重审候选通过产生的积分来源；与 clothing_contribution 来源互斥。';



COMMENT ON COLUMN "public"."points_ledger"."jury_vote_id" IS '陪审员首次有效投票的唯一 +1 积分来源。';



CREATE TABLE IF NOT EXISTS "public"."re_review_candidates" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "re_review_item_id" "uuid" NOT NULL,
    "payload" "jsonb" NOT NULL,
    "submitted_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "status" "text" DEFAULT 'voting'::"text" NOT NULL,
    "resolved_at" timestamp with time zone,
    CONSTRAINT "re_review_candidates_payload_object_check" CHECK ((("jsonb_typeof"("payload") = 'object'::"text") AND ("payload" <> '{}'::"jsonb"))),
    CONSTRAINT "re_review_candidates_status_check" CHECK (("status" = ANY (ARRAY['voting'::"text", 'approved'::"text", 'returned'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."re_review_candidates" OWNER TO "postgres";


COMMENT ON TABLE "public"."re_review_candidates" IS '登录用户只能提交重审项、候选内容和本人身份；候选 ID 与创建时间由数据库生成，候选不可修改或删除。';



COMMENT ON COLUMN "public"."re_review_candidates"."status" IS '候选轮次状态：voting 投票中、approved 通过、returned 退回重审、rejected 管理员永久驳回。';



CREATE TABLE IF NOT EXISTS "public"."re_review_item_sources" (
    "re_review_item_id" "uuid" NOT NULL,
    "source_pending_id" bigint NOT NULL,
    "source_user_id" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL
);


ALTER TABLE "public"."re_review_item_sources" OWNER TO "postgres";


COMMENT ON TABLE "public"."re_review_item_sources" IS '重审项的全部 pending 来源；用于审计和数据库层防止用户参与自己提交的数据。';



CREATE TABLE IF NOT EXISTS "public"."re_review_items" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "reason" "text" NOT NULL,
    "status" "text" DEFAULT 'pending'::"text" NOT NULL,
    "source_pending_id" bigint,
    "clothes_id" character varying,
    "payload" "jsonb" NOT NULL,
    "submitted_by" "uuid",
    "resolved_by" "uuid",
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "resolved_at" timestamp with time zone,
    "identity_key" "text",
    CONSTRAINT "re_review_items_payload_object_check" CHECK ((("jsonb_typeof"("payload") = 'object'::"text") AND ("payload" <> '{}'::"jsonb"))),
    CONSTRAINT "re_review_items_reason_check" CHECK (("reason" = ANY (ARRAY['missing_suit'::"text", 'field_conflict'::"text", 'field_missing'::"text", 'correction'::"text"]))),
    CONSTRAINT "re_review_items_reason_source_check" CHECK (((("reason" = 'missing_suit'::"text") AND ("clothes_id" IS NOT NULL)) OR (("reason" = ANY (ARRAY['field_conflict'::"text", 'field_missing'::"text"])) AND ("source_pending_id" IS NOT NULL)) OR (("reason" = 'correction'::"text") AND ("clothes_id" IS NOT NULL)))),
    CONSTRAINT "re_review_items_source_check" CHECK ((("source_pending_id" IS NOT NULL) OR ("clothes_id" IS NOT NULL))),
    CONSTRAINT "re_review_items_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'voting'::"text", 'approved'::"text", 'rejected'::"text", 'failed'::"text"])))
);


ALTER TABLE "public"."re_review_items" OWNER TO "postgres";


COMMENT ON TABLE "public"."re_review_items" IS 'DB-6 重审池：追踪缺套装、字段冲突、字段缺失和报错修正；社区参与、系统处理、管理员兜底。';



COMMENT ON COLUMN "public"."re_review_items"."payload" IS '进入重审时的数据快照；必须是 JSON 对象，不替代来源 pending 或正式服装关联。';



COMMENT ON COLUMN "public"."re_review_items"."identity_key" IS '同一服装同时只允许一个开放审核事项的稳定身份键。';



CREATE TABLE IF NOT EXISTS "public"."stages" (
    "id" bigint NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "name" "text",
    "weights" "jsonb"
);


ALTER TABLE "public"."stages" OWNER TO "postgres";


ALTER TABLE "public"."stages" ALTER COLUMN "id" ADD GENERATED BY DEFAULT AS IDENTITY (
    SEQUENCE NAME "public"."stages_id_seq"
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);



CREATE TABLE IF NOT EXISTS "public"."suits" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" "text" NOT NULL,
    "description" "text",
    "source" "text",
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."suits" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."user_points_summary" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "total_points"
   FROM "private_db2"."current_user_points"() "result"("total_points");


ALTER VIEW "public"."user_points_summary" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_quotas" (
    "user_id" "uuid" NOT NULL,
    "free_count" integer DEFAULT 20
);


ALTER TABLE "public"."user_quotas" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."user_wardrobes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "user_id" "uuid" DEFAULT "gen_random_uuid"(),
    "owned_clothes" "jsonb"
);


ALTER TABLE "public"."user_wardrobes" OWNER TO "postgres";


ALTER TABLE ONLY "public"."app_errors"
    ADD CONSTRAINT "app_errors_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clothes"
    ADD CONSTRAINT "clothes_name_category_unique" UNIQUE ("name", "category");



ALTER TABLE ONLY "public"."clothes"
    ADD CONSTRAINT "clothes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_event_rank_key" UNIQUE ("event_id", "contribution_rank");



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_event_user_key" UNIQUE ("event_id", "user_id");



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_source_pending_id_key" UNIQUE ("source_pending_id");



ALTER TABLE ONLY "public"."jury_admin_decisions"
    ADD CONSTRAINT "jury_admin_decisions_candidate_key" UNIQUE ("candidate_id");



ALTER TABLE ONLY "public"."jury_admin_decisions"
    ADD CONSTRAINT "jury_admin_decisions_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."jury_votes"
    ADD CONSTRAINT "jury_votes_candidate_user_key" UNIQUE ("candidate_id", "user_id");



ALTER TABLE ONLY "public"."jury_votes"
    ADD CONSTRAINT "jury_votes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pending_suits"
    ADD CONSTRAINT "pending_suits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_username_key" UNIQUE ("username");



ALTER TABLE ONLY "public"."re_review_candidates"
    ADD CONSTRAINT "re_review_candidates_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."re_review_item_sources"
    ADD CONSTRAINT "re_review_item_sources_pkey" PRIMARY KEY ("re_review_item_id", "source_pending_id");



ALTER TABLE ONLY "public"."re_review_items"
    ADD CONSTRAINT "re_review_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."stages"
    ADD CONSTRAINT "stages_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."stages"
    ADD CONSTRAINT "stages_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."suits"
    ADD CONSTRAINT "suits_name_key" UNIQUE ("name");



ALTER TABLE ONLY "public"."suits"
    ADD CONSTRAINT "suits_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_quotas"
    ADD CONSTRAINT "user_quotas_pkey" PRIMARY KEY ("user_id");



ALTER TABLE ONLY "public"."user_wardrobes"
    ADD CONSTRAINT "user_wardrobes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."user_wardrobes"
    ADD CONSTRAINT "user_wardrobes_user_id_key" UNIQUE ("user_id");



CREATE INDEX "clothing_contributions_clothes_id_idx" ON "public"."clothing_contributions" USING "btree" ("clothes_id");



CREATE UNIQUE INDEX "clothing_contributions_initial_reward_key" ON "public"."clothing_contributions" USING "btree" ("clothes_id", "user_id") WHERE (("user_id" IS NOT NULL) AND ("contribution_type" = ANY (ARRAY['auto_entry'::"text", 'admin_arbitration'::"text"])));



CREATE INDEX "clothing_contributions_user_id_idx" ON "public"."clothing_contributions" USING "btree" ("user_id");



CREATE INDEX "idx_clothes_suit_id" ON "public"."clothes" USING "btree" ("suit_id");



CREATE INDEX "idx_pending_clothes_status" ON "public"."pending_clothes" USING "btree" ("status");



CREATE INDEX "idx_pending_clothes_submitted_by" ON "public"."pending_clothes" USING "btree" ("submitted_by");



CREATE INDEX "idx_pending_suits_status" ON "public"."pending_suits" USING "btree" ("status");



CREATE INDEX "idx_profiles_username" ON "public"."profiles" USING "btree" ("username");



CREATE INDEX "idx_suits_name" ON "public"."suits" USING "btree" ("name");



CREATE INDEX "jury_admin_decisions_admin_user_id_idx" ON "public"."jury_admin_decisions" USING "btree" ("admin_user_id") WHERE ("admin_user_id" IS NOT NULL);



COMMENT ON INDEX "public"."jury_admin_decisions_admin_user_id_idx" IS 'DB-7 覆盖管理员终审记录的用户外键，避免删除用户或按管理员追溯时扫描整表。';



CREATE INDEX "jury_admin_decisions_item_created_at_idx" ON "public"."jury_admin_decisions" USING "btree" ("re_review_item_id", "created_at" DESC);



CREATE INDEX "jury_votes_user_created_at_idx" ON "public"."jury_votes" USING "btree" ("user_id", "created_at" DESC) WHERE ("user_id" IS NOT NULL);



CREATE UNIQUE INDEX "points_ledger_jury_vote_id_key" ON "public"."points_ledger" USING "btree" ("jury_vote_id") WHERE ("jury_vote_id" IS NOT NULL);



CREATE UNIQUE INDEX "points_ledger_re_review_candidate_id_key" ON "public"."points_ledger" USING "btree" ("re_review_candidate_id") WHERE ("re_review_candidate_id" IS NOT NULL);



CREATE UNIQUE INDEX "points_ledger_reversal_of_key" ON "public"."points_ledger" USING "btree" ("reversal_of") WHERE ("reversal_of" IS NOT NULL);



CREATE UNIQUE INDEX "points_ledger_source_id_key" ON "public"."points_ledger" USING "btree" ("source_id") WHERE ("source_id" IS NOT NULL);



CREATE INDEX "points_ledger_user_occurred_at_idx" ON "public"."points_ledger" USING "btree" ("user_id", "occurred_at" DESC);



CREATE UNIQUE INDEX "re_review_candidates_active_item_key" ON "public"."re_review_candidates" USING "btree" ("re_review_item_id") WHERE ("status" = 'voting'::"text");



CREATE INDEX "re_review_candidates_item_created_at_idx" ON "public"."re_review_candidates" USING "btree" ("re_review_item_id", "created_at" DESC);



CREATE INDEX "re_review_candidates_submitted_by_idx" ON "public"."re_review_candidates" USING "btree" ("submitted_by") WHERE ("submitted_by" IS NOT NULL);



CREATE INDEX "re_review_item_sources_pending_id_idx" ON "public"."re_review_item_sources" USING "btree" ("source_pending_id");



CREATE INDEX "re_review_item_sources_user_id_idx" ON "public"."re_review_item_sources" USING "btree" ("source_user_id", "re_review_item_id") WHERE ("source_user_id" IS NOT NULL);



CREATE UNIQUE INDEX "re_review_items_active_identity_key" ON "public"."re_review_items" USING "btree" ("identity_key") WHERE (("identity_key" IS NOT NULL) AND ("status" = ANY (ARRAY['pending'::"text", 'voting'::"text", 'failed'::"text"])));



CREATE UNIQUE INDEX "re_review_items_active_missing_suit_key" ON "public"."re_review_items" USING "btree" ("clothes_id") WHERE (("reason" = 'missing_suit'::"text") AND ("status" = ANY (ARRAY['pending'::"text", 'voting'::"text", 'failed'::"text"])));



CREATE UNIQUE INDEX "re_review_items_active_pending_reason_key" ON "public"."re_review_items" USING "btree" ("source_pending_id", "reason") WHERE (("source_pending_id" IS NOT NULL) AND ("status" = ANY (ARRAY['pending'::"text", 'voting'::"text", 'failed'::"text"])));



CREATE INDEX "re_review_items_clothes_id_idx" ON "public"."re_review_items" USING "btree" ("clothes_id") WHERE ("clothes_id" IS NOT NULL);



CREATE INDEX "re_review_items_resolved_by_idx" ON "public"."re_review_items" USING "btree" ("resolved_by") WHERE ("resolved_by" IS NOT NULL);



CREATE INDEX "re_review_items_source_pending_id_idx" ON "public"."re_review_items" USING "btree" ("source_pending_id") WHERE ("source_pending_id" IS NOT NULL);



CREATE INDEX "re_review_items_status_created_at_idx" ON "public"."re_review_items" USING "btree" ("status", "created_at");



CREATE INDEX "re_review_items_submitted_by_idx" ON "public"."re_review_items" USING "btree" ("submitted_by") WHERE ("submitted_by" IS NOT NULL);



CREATE OR REPLACE TRIGGER "close_missing_suit_re_review_after_link" AFTER UPDATE OF "suit_id" ON "public"."clothes" FOR EACH ROW WHEN ((("new"."suit_id" IS NOT NULL) AND ("old"."suit_id" IS DISTINCT FROM "new"."suit_id"))) EXECUTE FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"();



CREATE OR REPLACE TRIGGER "sync_profile_role_fields" BEFORE INSERT OR UPDATE OF "role", "role_level" ON "public"."profiles" FOR EACH ROW EXECUTE FUNCTION "public"."sync_profile_role_fields"();



CREATE OR REPLACE TRIGGER "trigger_auto_link_shadow_suits" AFTER INSERT ON "public"."suits" FOR EACH ROW EXECUTE FUNCTION "public"."auto_link_shadow_suits"();



ALTER TABLE ONLY "public"."clothes"
    ADD CONSTRAINT "clothes_suit_id_fkey" FOREIGN KEY ("suit_id") REFERENCES "public"."suits"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_clothes_id_fkey" FOREIGN KEY ("clothes_id") REFERENCES "public"."clothes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_source_pending_id_fkey" FOREIGN KEY ("source_pending_id") REFERENCES "public"."pending_clothes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."clothing_contributions"
    ADD CONSTRAINT "clothing_contributions_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."jury_admin_decisions"
    ADD CONSTRAINT "jury_admin_decisions_admin_user_id_fkey" FOREIGN KEY ("admin_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."jury_admin_decisions"
    ADD CONSTRAINT "jury_admin_decisions_candidate_id_fkey" FOREIGN KEY ("candidate_id") REFERENCES "public"."re_review_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jury_admin_decisions"
    ADD CONSTRAINT "jury_admin_decisions_item_id_fkey" FOREIGN KEY ("re_review_item_id") REFERENCES "public"."re_review_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jury_votes"
    ADD CONSTRAINT "jury_votes_candidate_id_fkey" FOREIGN KEY ("candidate_id") REFERENCES "public"."re_review_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."jury_votes"
    ADD CONSTRAINT "jury_votes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_suit_id_fkey" FOREIGN KEY ("suit_id") REFERENCES "public"."suits"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pending_suits"
    ADD CONSTRAINT "pending_suits_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_jury_vote_id_fkey" FOREIGN KEY ("jury_vote_id") REFERENCES "public"."jury_votes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_re_review_candidate_id_fkey" FOREIGN KEY ("re_review_candidate_id") REFERENCES "public"."re_review_candidates"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_reversal_of_fkey" FOREIGN KEY ("reversal_of") REFERENCES "public"."points_ledger"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."clothing_contributions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."re_review_candidates"
    ADD CONSTRAINT "re_review_candidates_item_id_fkey" FOREIGN KEY ("re_review_item_id") REFERENCES "public"."re_review_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."re_review_candidates"
    ADD CONSTRAINT "re_review_candidates_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."re_review_item_sources"
    ADD CONSTRAINT "re_review_item_sources_item_id_fkey" FOREIGN KEY ("re_review_item_id") REFERENCES "public"."re_review_items"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."re_review_item_sources"
    ADD CONSTRAINT "re_review_item_sources_pending_id_fkey" FOREIGN KEY ("source_pending_id") REFERENCES "public"."pending_clothes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."re_review_item_sources"
    ADD CONSTRAINT "re_review_item_sources_user_id_fkey" FOREIGN KEY ("source_user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."re_review_items"
    ADD CONSTRAINT "re_review_items_clothes_id_fkey" FOREIGN KEY ("clothes_id") REFERENCES "public"."clothes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."re_review_items"
    ADD CONSTRAINT "re_review_items_resolved_by_fkey" FOREIGN KEY ("resolved_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."re_review_items"
    ADD CONSTRAINT "re_review_items_source_pending_id_fkey" FOREIGN KEY ("source_pending_id") REFERENCES "public"."pending_clothes"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."re_review_items"
    ADD CONSTRAINT "re_review_items_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."user_quotas"
    ADD CONSTRAINT "user_quotas_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."user_wardrobes"
    ADD CONSTRAINT "user_wardrobes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



CREATE POLICY "Anyone can insert pending suits" ON "public"."pending_suits" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can select and update pending suits" ON "public"."pending_suits" USING (true);



CREATE POLICY "Enable read access for all users" ON "public"."clothes" FOR SELECT USING (true);



ALTER TABLE "public"."app_errors" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."clothes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."clothing_contributions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."jury_admin_decisions" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."jury_votes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pending_clothes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pending_suits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."points_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."re_review_candidates" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."re_review_item_sources" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."re_review_items" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_quotas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_wardrobes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "仅管理员可操作图鉴" ON "public"."clothes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'admin'::"text")))));



CREATE POLICY "允许任何人上报错误" ON "public"."app_errors" FOR INSERT WITH CHECK (true);



CREATE POLICY "允许已登录用户读取档案" ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "允许用户操作自己的衣柜" ON "public"."user_wardrobes" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "允许用户查看自己的额度" ON "public"."user_quotas" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "允许超管修改档案" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ("public"."is_super_admin"());



CREATE POLICY "用户只能操作自己的衣柜" ON "public"."user_wardrobes" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "用户可以查看自己的画像" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "登录用户只能查看自己的重审来源标记" ON "public"."re_review_item_sources" FOR SELECT TO "authenticated" USING (("source_user_id" = ( SELECT "auth"."uid"() AS "uid")));



CREATE POLICY "登录用户可查看未参与的重审项" ON "public"."re_review_items" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND ("submitted_by" IS DISTINCT FROM ( SELECT "auth"."uid"() AS "uid")) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."pending_clothes" "primary_source"
  WHERE (("primary_source"."id" = "re_review_items"."source_pending_id") AND ("primary_source"."submitted_by" = ( SELECT "auth"."uid"() AS "uid")))))) AND (NOT (EXISTS ( SELECT 1
   FROM "public"."re_review_item_sources" "source"
  WHERE (("source"."re_review_item_id" = "re_review_items"."id") AND ("source"."source_user_id" = ( SELECT "auth"."uid"() AS "uid"))))))));



CREATE POLICY "登录用户可查看未参与重审项的候选修正版" ON "public"."re_review_candidates" FOR SELECT TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."re_review_items" "item"
  WHERE ("item"."id" = "re_review_candidates"."re_review_item_id"))));



CREATE POLICY "管理员可更新申请状态" ON "public"."pending_clothes" FOR UPDATE TO "authenticated" USING (( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin")) WITH CHECK (( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin"));



CREATE POLICY "管理员权限" ON "public"."clothes" TO "authenticated" USING (("auth"."email"() = '2230909994@qq.com'::"text")) WITH CHECK (("auth"."email"() = '2230909994@qq.com'::"text"));



CREATE POLICY "认证用户只能提交自己的待审核申请" ON "public"."pending_clothes" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND ("submitted_by" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'pending'::"text")));



CREATE POLICY "认证用户可查看自己的申请及管理员可查看全部" ON "public"."pending_clothes" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND (("submitted_by" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin"))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."admin_reject_jury_candidate"("p_candidate_id" "uuid", "p_reason" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."apply_approved_jury_candidate"("p_re_review_item_id" "uuid", "p_candidate_id" "uuid", "p_resolved_by" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."apply_approved_jury_candidate"("p_re_review_item_id" "uuid", "p_candidate_id" "uuid", "p_resolved_by" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[], "p_needs_suit_review" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[], "p_needs_suit_review" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[], "p_needs_suit_review" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_pending_clothes_arbitration_db4_core"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_pending_clothes_arbitration_db4_core"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."build_jury_review_payload"("p_pending_ids" bigint[], "p_clothes_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."build_jury_review_payload"("p_pending_ids" bigint[], "p_clothes_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."cast_jury_vote"("p_candidate_id" "uuid", "p_vote" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."close_missing_suit_re_review_on_clothes_link"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_existing_clothes_from_pending_db3_core"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_existing_clothes_from_pending_db3_core"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_full_jury_review_item"("p_pending_id" bigint, "p_clothes_id" "text", "p_require_five_sources" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_full_jury_review_item"("p_pending_id" bigint, "p_clothes_id" "text", "p_require_five_sources" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."ensure_missing_suit_re_review_item"("p_clothes_id" "text", "p_pending_ids" bigint[], "p_allow_create" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."ensure_missing_suit_re_review_item"("p_clothes_id" "text", "p_pending_ids" bigint[], "p_allow_create" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."get_jury_review_queue"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."get_jury_review_queue"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."get_jury_review_queue"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."handle_new_user_quota"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."handle_new_user_quota"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_admin_or_super_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_admin_or_super_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin_or_super_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."is_super_admin"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_clothes_payload"("p_clothes_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_clothes_payload"("p_clothes_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_field_value_is_missing"("p_payload" "jsonb", "p_field" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_field_value_is_missing"("p_payload" "jsonb", "p_field" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_payload_field_value"("p_payload" "jsonb", "p_field" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_payload_field_value"("p_payload" "jsonb", "p_field" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_payload_is_complete"("p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_payload_is_complete"("p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_pending_payload"("p_pending_id" bigint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_pending_payload"("p_pending_id" bigint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_record_payload"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_record_payload"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."jury_scores_are_complete"("p_scores" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."jury_scores_are_complete"("p_scores" "jsonb") TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) TO "anon";
GRANT ALL ON FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) TO "authenticated";
GRANT ALL ON FUNCTION "public"."profile_role_level_to_text"("p_role_level" smallint) TO "service_role";



REVOKE ALL ON FUNCTION "public"."profile_role_to_level"("p_role" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."profile_role_to_level"("p_role" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."profile_role_to_level"("p_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."profile_role_to_level"("p_role" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_clothing_contribution_db7_core"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution_db7_core"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_needs_suit_review" boolean) TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_jury_candidate"("p_re_review_item_id" "uuid", "p_payload" "jsonb") TO "service_role";



REVOKE ALL ON FUNCTION "public"."sync_profile_role_fields"() FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."sync_profile_role_fields"() TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



REVOKE ALL ON FUNCTION "public"."update_profile_username"("p_username" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."update_profile_username"("p_username" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."update_profile_username"("p_username" "text") TO "service_role";



GRANT ALL ON TABLE "public"."app_errors" TO "anon";
GRANT ALL ON TABLE "public"."app_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."app_errors" TO "service_role";



GRANT ALL ON TABLE "public"."clothes" TO "anon";
GRANT ALL ON TABLE "public"."clothes" TO "authenticated";
GRANT ALL ON TABLE "public"."clothes" TO "service_role";



GRANT SELECT,INSERT ON TABLE "public"."clothing_contributions" TO "service_role";



GRANT SELECT ON TABLE "public"."clothing_contributors_public" TO "anon";
GRANT SELECT ON TABLE "public"."clothing_contributors_public" TO "authenticated";



GRANT SELECT,INSERT ON TABLE "public"."jury_admin_decisions" TO "service_role";



GRANT SELECT,INSERT ON TABLE "public"."jury_votes" TO "service_role";



GRANT ALL ON TABLE "public"."pending_clothes" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."pending_clothes" TO "authenticated";



GRANT UPDATE("status") ON TABLE "public"."pending_clothes" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."pending_clothes_id_seq" TO "service_role";
GRANT SELECT,USAGE ON SEQUENCE "public"."pending_clothes_id_seq" TO "authenticated";



GRANT ALL ON TABLE "public"."pending_suits" TO "anon";
GRANT ALL ON TABLE "public"."pending_suits" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_suits" TO "service_role";



GRANT SELECT,INSERT ON TABLE "public"."points_ledger" TO "service_role";



GRANT SELECT ON TABLE "public"."points_leaderboard_current_month" TO "authenticated";



GRANT SELECT ON TABLE "public"."points_leaderboard_total" TO "authenticated";



GRANT SELECT,INSERT ON TABLE "public"."re_review_candidates" TO "service_role";
GRANT SELECT ON TABLE "public"."re_review_candidates" TO "authenticated";



GRANT SELECT,INSERT ON TABLE "public"."re_review_item_sources" TO "service_role";
GRANT SELECT ON TABLE "public"."re_review_item_sources" TO "authenticated";



GRANT SELECT,INSERT ON TABLE "public"."re_review_items" TO "service_role";
GRANT SELECT ON TABLE "public"."re_review_items" TO "authenticated";



GRANT UPDATE("status") ON TABLE "public"."re_review_items" TO "service_role";



GRANT UPDATE("resolved_by") ON TABLE "public"."re_review_items" TO "service_role";



GRANT UPDATE("updated_at") ON TABLE "public"."re_review_items" TO "service_role";



GRANT UPDATE("resolved_at") ON TABLE "public"."re_review_items" TO "service_role";



GRANT ALL ON TABLE "public"."stages" TO "anon";
GRANT ALL ON TABLE "public"."stages" TO "authenticated";
GRANT ALL ON TABLE "public"."stages" TO "service_role";



GRANT ALL ON SEQUENCE "public"."stages_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."stages_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."stages_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."suits" TO "anon";
GRANT ALL ON TABLE "public"."suits" TO "authenticated";
GRANT ALL ON TABLE "public"."suits" TO "service_role";



GRANT SELECT ON TABLE "public"."user_points_summary" TO "authenticated";



GRANT ALL ON TABLE "public"."user_quotas" TO "anon";
GRANT ALL ON TABLE "public"."user_quotas" TO "authenticated";
GRANT ALL ON TABLE "public"."user_quotas" TO "service_role";



GRANT ALL ON TABLE "public"."user_wardrobes" TO "anon";
GRANT ALL ON TABLE "public"."user_wardrobes" TO "authenticated";
GRANT ALL ON TABLE "public"."user_wardrobes" TO "service_role";



ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";
