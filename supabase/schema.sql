


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


create or replace function public.approve_pending_clothes_arbitration(
  p_id text,
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null,
  p_pending_ids bigint[] default '{}'
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
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
    raise exception '娌℃湁浠茶鍏ュ簱鏉冮檺';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_id, '')), '') is null then
    raise exception '鏈嶈 ID 涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '鏈嶈鍚嶇О涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '鍒嗙被閮ㄤ綅涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_game_id, '')), '') is null
    or pg_catalog.btrim(p_game_id) !~ '^[0-9]+$' then
    raise exception '鐭紪鍙峰繀椤讳负鏁板瓧';
  end if;

  if p_stars is null then
    raise exception '鏄熺骇涓嶈兘涓虹┖';
  end if;

  if p_scores is null then
    raise exception '灞炴€у垎鍊间笉鑳戒负绌?;
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
    raise exception '寰呭鏍歌褰曚笉鑳戒负绌?;
  end if;

  if v_requested_pending_count <> pg_catalog.cardinality(v_pending_ids) then
    raise exception '寰呭鏍歌褰曞寘鍚┖鍊兼垨閲嶅 ID';
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
    raise exception '瀛樺湪鎵句笉鍒扮殑寰呭鏍歌褰?;
  end if;

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '瀛樺湪涓庢湰娆＄鐞嗗憳浠茶鏈€缁堟暟鎹笉涓€鑷寸殑寰呭鏍歌褰曪紝宸叉嫆缁濆叆搴?;
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
      raise exception '寰呭鏍歌褰曞凡閫氳繃锛屼絾姝ｅ紡鏈嶈浜嬪疄涓庢湰娆′徊瑁佷笉涓€鑷达紱绂佹鑷姩鍥炲～';
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
      raise exception '寰呭鏍歌褰曞凡閫氳繃锛屼絾璐＄尞銆佺Н鍒嗘垨琛ｆ煖浜嬪疄涓嶅畬鏁达紱绂佹鑷姩鍥炲～锛岃浜哄伐鏍稿';
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
    raise exception '寰呭鏍歌褰曠姸鎬佷笉涓€鑷达紝璇峰埛鏂板鏍搁〉鍚庨噸璇?;
  end if;

  if v_clothes_exists then
    raise exception '姝ｅ紡搴撳凡瀛樺湪璇ユ湇瑁咃紝璇峰埛鏂板悗鍙板悗浣跨敤姝ｅ紡搴撹ˉ鍏ㄦ垨閲嶅娴佺▼';
  end if;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_sorted_pending_ids)
  ) then
    raise exception '鏈鏉ユ簮宸插瓨鍦ㄨ础鐚簨瀹烇紝浣嗗緟瀹℃牳鐘舵€佹湭瀹屾垚锛涜浜哄伐鏍稿';
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
    raise exception '璐＄尞銆佺Н鍒嗘垨琛ｆ煖鍐欏洖鏁伴噺寮傚父锛屽凡鍥炴粴鏈浠茶';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_sorted_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '寰呭鏍歌褰曢€氳繃鏁伴噺寮傚父锛屽凡鍥炴粴鏈浠茶';
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
$$;

alter function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) owner to postgres;

comment on function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) is 'DB-4：管理员仲裁入库，同事务记录前 5 位有效贡献者、每人 10 分、衣柜写回和 pending 通过；服务端核对候选且重复请求幂等。';


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


CREATE OR REPLACE FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[]) RETURNS "jsonb"
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
    raise exception '娌℃湁琛ュ叏姝ｅ紡搴撴潈闄?;
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_existing_id, '')), '') is null then
    raise exception '姝ｅ紡搴撴湇瑁?ID 涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_name, '')), '') is null then
    raise exception '鏈嶈鍚嶇О涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_category, '')), '') is null then
    raise exception '鍒嗙被閮ㄤ綅涓嶈兘涓虹┖';
  end if;

  if nullif(pg_catalog.btrim(coalesce(p_game_id, '')), '') is null
    or pg_catalog.btrim(p_game_id) !~ '^[0-9]+$' then
    raise exception '鐭紪鍙峰繀椤讳负鏁板瓧';
  end if;

  if p_stars is null then
    raise exception '鏄熺骇涓嶈兘涓虹┖';
  end if;

  if p_scores is null then
    raise exception '灞炴€у垎鍊间笉鑳戒负绌?;
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
    raise exception '寰呭鏍歌褰曚笉鑳戒负绌?;
  end if;

  if v_requested_pending_count <> pg_catalog.cardinality(v_pending_ids) then
    raise exception '寰呭鏍歌褰曞寘鍚┖鍊兼垨閲嶅 ID';
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
    raise exception '姝ｅ紡搴撴湇瑁呬笉瀛樺湪锛屾垨鍚嶇О鍒嗙被涓庡緟瀹℃牳璁板綍涓嶄竴鑷?;
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.game_id, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.game_id) is distinct from pg_catalog.btrim(p_game_id) then
    raise exception '姝ｅ紡搴撶煭缂栧彿宸叉湁闈炵┖鍊间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.stars, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.stars) is distinct from p_stars::text then
    raise exception '姝ｅ紡搴撴槦绾у凡鏈夐潪绌哄€间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
  end if;

  if v_existing_clothes.scores is not null
    and v_existing_clothes.scores is distinct from p_scores then
    raise exception '姝ｅ紡搴撳睘鎬у垎鍊煎凡鏈夐潪绌哄€间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
  end if;

  if v_existing_clothes.suit_id is not null
    and p_suit_id is not null
    and v_existing_clothes.suit_id is distinct from p_suit_id then
    raise exception '姝ｅ紡搴撳瑁呭叧鑱斿凡鏈夐潪绌哄€间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.temp_suit_name, '')), '') is not null
    and nullif(pg_catalog.btrim(coalesce(p_temp_suit_name, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.temp_suit_name) is distinct from pg_catalog.btrim(p_temp_suit_name) then
    raise exception '姝ｅ紡搴撲复鏃跺瑁呭悕宸叉湁闈炵┖鍊间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
  end if;

  if nullif(pg_catalog.btrim(coalesce(v_existing_clothes.tags, '')), '') is not null
    and nullif(pg_catalog.btrim(coalesce(p_tags, '')), '') is not null
    and pg_catalog.btrim(v_existing_clothes.tags) is distinct from pg_catalog.btrim(p_tags) then
    raise exception '姝ｅ紡搴撴爣绛惧凡鏈夐潪绌哄€间笖涓庡緟琛ュ叏鍐呭涓嶄竴鑷达紝闇€杩涘叆閲嶅 / 闄鍥㈣矾寰?;
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
    raise exception '瀛樺湪鎵句笉鍒扮殑寰呭鏍歌褰?;
  end if;

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '瀛樺湪涓庢湰娆℃寮忓簱琛ュ叏鏈€缁堟暟鎹笉涓€鑷寸殑寰呭鏍歌褰曪紝宸叉嫆缁濊嚜鍔ㄩ€氳繃';
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
      raise exception '寰呭鏍歌褰曞凡閫氳繃锛屼絾璐＄尞銆佺Н鍒嗘垨琛ｆ煖浜嬪疄涓嶅畬鏁达紱绂佹鑷姩鍥炲～锛岃浜哄伐鏍稿';
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
    raise exception '寰呭鏍歌褰曠姸鎬佷笉涓€鑷达紝璇峰埛鏂板鏍搁〉鍚庨噸璇?;
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
    raise exception '姝ｅ紡搴撴病鏈夊彲鐢辨湰娆¤姹傝ˉ鍏ㄧ殑绌哄瓧娈碉紝绂佹閲嶅濂栧姳';
  end if;

  if exists (
    select 1
    from public.clothing_contributions as contribution
    where contribution.event_id = v_event_id
      or contribution.source_pending_id = any(v_sorted_pending_ids)
  ) then
    raise exception '鏈鏉ユ簮宸插瓨鍦ㄨ础鐚簨瀹烇紝浣嗗緟瀹℃牳鐘舵€佹湭瀹屾垚锛涜浜哄伐鏍稿';
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
    raise exception '璐＄尞銆佺Н鍒嗘垨琛ｆ煖鍐欏洖鏁伴噺寮傚父锛屽凡鍥炴粴鏈琛ュ叏';
  end if;

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_sorted_pending_ids)
    and status = 'pending';

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '寰呭鏍歌褰曢€氳繃鏁伴噺寮傚父锛屽凡鍥炴粴鏈琛ュ叏';
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


ALTER FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


COMMENT ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) IS 'DB-3锛氭寮忓簱绌哄瓧娈佃ˉ鍏紝鍚屼簨鍔¤褰曞墠 5 浣嶆湁鏁堣础鐚€呫€佹瘡浜?5 鍒嗐€佽。鏌滃啓鍥炲拰 pending 閫氳繃锛涢噸澶嶈姹傚箓绛夈€?;



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
  VALUES (new.id, 30); -- 鏂扮敤鎴烽粯璁ょ粰 20 娆?  RETURN new;
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


CREATE OR REPLACE FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") RETURNS "text"
    LANGUAGE "plpgsql" IMMUTABLE
    AS $$
declare
  known_tags text[] := array[
    '鐜颁唬娴佽', '娆у紡鍙ゅ吀', '涓紡鍙ゅ吀', '涓紡鐜颁唬', '娉㈣タ绫充簹', '妫コ绯诲垪',
    '娲涗附濉?, '鍝ョ壒椋?, '濂充粏瑁?, '绔ヨ瘽绯?, '鏈潵绯?, '渚犲鑱旂洘',
    '姘戝浗鏈嶉グ', '姘戞棌椋?, '鑻变鸡', '瀛﹂櫌绯?, '杩愬姩绯?, '灞呭鏈?,
    '鏅氱ぜ鏈?, '濠氱罕', '鏃楄', '鍐涜', '宸ヨ椋?, '鑸捣椋?,
    '涔愰槦椋?, '鑸炶€?, '濂崇绯?, '澶у皬濮?, '鍏斿コ閮?, '鍖诲姟浣胯€?,
    '闆ㄥ瑁呭', '鍐', '娉宠', '娌愭荡', '鍥磋', '纰庤姳',
    '闃叉檼', '鐫¤。', '鍔ㄧ墿绯?, '娼叿椋?, '杞荤啛椋?, '寮傚煙椋?,
    '涓€ч',
    '绠€绾?200', '绠€绾?500', '绠€绾?800', '绠€绾?1200', '绠€绾?1500',
    '鍗庝附+200', '鍗庝附+500', '鍗庝附+800', '鍗庝附+1200', '鍗庝附+1500',
    '娲绘臣+200', '娲绘臣+500', '娲绘臣+800', '娲绘臣+1200', '娲绘臣+1500',
    '浼橀泤+200', '浼橀泤+500', '浼橀泤+800', '浼橀泤+1200', '浼橀泤+1500',
    '鍙埍+200', '鍙埍+500', '鍙埍+800', '鍙埍+1200', '鍙埍+1500',
    '鎴愮啛+200', '鎴愮啛+500', '鎴愮啛+800', '鎴愮啛+1200', '鎴愮啛+1500',
    '娓呯函+200', '娓呯函+500', '娓呯函+800', '娓呯函+1200', '娓呯函+1500',
    '鎬ф劅+200', '鎬ф劅+500', '鎬ф劅+800', '鎬ф劅+1200', '鎬ф劅+1500',
    '娓呭噳+200', '娓呭噳+500', '娓呭噳+800', '娓呭噳+1200'
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

  parts := regexp_split_to_array(p_tags, '[,锛屻€?锛沒+');

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


CREATE OR REPLACE FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare
  v_user_id uuid := auth.uid();
  v_game_id text := trim(coalesce(p_game_id, ''));
  v_clothes_id text;
  v_pending_id bigint;
  v_matching_pending_ids bigint[];
  v_matching_count integer := 0;
  v_can_auto_approve boolean;
  v_submitter_ids uuid[];
  v_wardrobe_count integer := 0;
begin
  if v_user_id is null then
    raise exception '闇€瑕佺櫥褰曞悗鎵嶈兘鎻愪氦鍥鹃壌鐢宠';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception '鏈嶈鍚嶇О涓嶈兘涓虹┖';
  end if;

  if nullif(v_game_id, '') is null then
    raise exception '鐭紪鍙蜂笉鑳戒负绌?;
  end if;

  if v_game_id !~ '^[0-9]+$' then
    raise exception '鐭紪鍙峰彧鍏佽濉啓鏁板瓧';
  end if;

  v_can_auto_approve := p_suit_id is not null or nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null;

  if v_can_auto_approve then
    select coalesce(array_agg(id order by created_at asc), '{}')::bigint[], count(*)::integer
      into v_matching_pending_ids, v_matching_count
    from public.pending_clothes
    where status = 'pending'
      and name is not distinct from p_name
      and game_id is not distinct from v_game_id
      and category is not distinct from p_category
      and stars is not distinct from p_stars
      and tags is not distinct from p_tags
      and suit_id is not distinct from p_suit_id
      and temp_suit_name is not distinct from p_temp_suit_name
      and scores = p_scores;

    if v_matching_count >= 4 then
      v_clothes_id := 'custom_' || replace(gen_random_uuid()::text, '-', '');

      select coalesce(array_agg(distinct submitted_by), '{}')::uuid[] || array[v_user_id]
        into v_submitter_ids
      from public.pending_clothes
      where id = any(v_matching_pending_ids)
        and submitted_by is not null;

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

      v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(v_submitter_ids, v_clothes_id);

      delete from public.pending_clothes
      where id = any(v_matching_pending_ids);

      if p_suit_id is null and nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null then
        insert into public.pending_suits (name, submitted_by, status)
        values (p_temp_suit_name, v_user_id, 'pending');
      end if;

      return jsonb_build_object(
        'auto_approved', true,
        'clothes_id', v_clothes_id,
        'matched_pending_count', v_matching_count,
        'wardrobe_updated_count', v_wardrobe_count
      );
    end if;
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
    status
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
    'pending'
  )
  returning id into v_pending_id;

  if p_suit_id is null and nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null then
    insert into public.pending_suits (name, submitted_by, status)
    values (p_temp_suit_name, v_user_id, 'pending');
  end if;

  return jsonb_build_object(
    'auto_approved', false,
    'pending_id', v_pending_id
  );
end;
$_$;


ALTER FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") OWNER TO "postgres";


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
    raise exception '璇峰厛鐧诲綍鍚庡啀淇敼浠ｅ彿';
  end if;

  if v_username = '' then
    raise exception '鐢ㄦ埛鍚嶄笉鑳戒负绌?;
  end if;

  if char_length(v_username) > 24 then
    raise exception '鐢ㄦ埛鍚嶆渶澶?24 涓瓧绗?;
  end if;

  if v_username like '鍖垮悕鎼厤甯圽_%' escape '\' then
    raise exception '涓嶈兘浣跨敤绯荤粺淇濈暀鐨勫尶鍚嶆牸寮?;
  end if;

  update public.profiles
  set username = v_username,
      updated_at = now()
  where id = v_user_id
  returning * into v_profile;

  if not found then
    raise exception '鏈壘鍒板綋鍓嶇敤鎴锋。妗?;
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
    CONSTRAINT "clothing_contributions_type_check" CHECK (("contribution_type" = ANY (ARRAY['auto_entry'::"text", 'admin_arbitration'::"text", 'existing_field_completion'::"text"])))
);


ALTER TABLE "public"."clothing_contributions" OWNER TO "postgres";


CREATE OR REPLACE VIEW "public"."clothing_contributors_public" WITH ("security_invoker"='true', "security_barrier"='true') AS
 SELECT "clothes_id",
    "contribution_rank",
    "display_name",
    "contributed_at"
   FROM "private_db2"."public_initial_contributors"() "result"("clothes_id", "contribution_rank", "display_name", "contributed_at");


ALTER VIEW "public"."clothing_contributors_public" OWNER TO "postgres";


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
    "temp_suit_name" "text"
);


ALTER TABLE "public"."pending_clothes" OWNER TO "postgres";


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
    CONSTRAINT "points_ledger_delta_check" CHECK (("delta" <> 0)),
    CONSTRAINT "points_ledger_entry_shape_check" CHECK (((("source_type" = 'clothing_contribution'::"text") AND ("source_id" IS NOT NULL) AND ("reversal_of" IS NULL) AND ("delta" > 0)) OR (("source_type" = 'reversal'::"text") AND ("source_id" IS NULL) AND ("reversal_of" IS NOT NULL) AND ("delta" < 0)))),
    CONSTRAINT "points_ledger_source_type_check" CHECK (("source_type" = ANY (ARRAY['clothing_contribution'::"text", 'reversal'::"text"]))),
    CONSTRAINT "points_ledger_status_check" CHECK (("status" = 'awarded'::"text"))
);


ALTER TABLE "public"."points_ledger" OWNER TO "postgres";


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



CREATE UNIQUE INDEX "points_ledger_reversal_of_key" ON "public"."points_ledger" USING "btree" ("reversal_of") WHERE ("reversal_of" IS NOT NULL);



CREATE UNIQUE INDEX "points_ledger_source_id_key" ON "public"."points_ledger" USING "btree" ("source_id") WHERE ("source_id" IS NOT NULL);



CREATE INDEX "points_ledger_user_occurred_at_idx" ON "public"."points_ledger" USING "btree" ("user_id", "occurred_at" DESC);



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



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_suit_id_fkey" FOREIGN KEY ("suit_id") REFERENCES "public"."suits"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pending_suits"
    ADD CONSTRAINT "pending_suits_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_reversal_of_fkey" FOREIGN KEY ("reversal_of") REFERENCES "public"."points_ledger"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_source_id_fkey" FOREIGN KEY ("source_id") REFERENCES "public"."clothing_contributions"("id") ON DELETE RESTRICT;



ALTER TABLE ONLY "public"."points_ledger"
    ADD CONSTRAINT "points_ledger_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "auth"."users"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id");



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


ALTER TABLE "public"."pending_clothes" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."pending_suits" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."points_ledger" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_quotas" ENABLE ROW LEVEL SECURITY;


ALTER TABLE "public"."user_wardrobes" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "浠呯鐞嗗憳鍙搷浣滃浘閴? ON "public"."clothes" TO "authenticated" USING ((EXISTS ( SELECT 1
   FROM "public"."profiles"
  WHERE (("profiles"."id" = "auth"."uid"()) AND ("profiles"."role" = 'admin'::"text")))));



CREATE POLICY "鍏佽浠讳綍浜轰笂鎶ラ敊璇? ON "public"."app_errors" FOR INSERT WITH CHECK (true);



CREATE POLICY "鍏佽宸茬櫥褰曠敤鎴疯鍙栨。妗? ON "public"."profiles" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "鍏佽鐢ㄦ埛鎿嶄綔鑷繁鐨勮。鏌? ON "public"."user_wardrobes" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "鍏佽鐢ㄦ埛鏌ョ湅鑷繁鐨勯搴? ON "public"."user_quotas" FOR SELECT USING (("auth"."uid"() = "user_id"));



CREATE POLICY "鍏佽瓒呯淇敼妗ｆ" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ("public"."is_super_admin"());



CREATE POLICY "鐢ㄦ埛鍙兘鎿嶄綔鑷繁鐨勮。鏌? ON "public"."user_wardrobes" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "鐢ㄦ埛鍙互鏌ョ湅鑷繁鐨勭敾鍍? ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "绠＄悊鍛樺彲鏇存柊鐢宠鐘舵€? ON "public"."pending_clothes" FOR UPDATE TO "authenticated" USING (( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin")) WITH CHECK (( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin"));



CREATE POLICY "绠＄悊鍛樻潈闄? ON "public"."clothes" TO "authenticated" USING (("auth"."email"() = '2230909994@qq.com'::"text")) WITH CHECK (("auth"."email"() = '2230909994@qq.com'::"text"));



CREATE POLICY "璁よ瘉鐢ㄦ埛鍙兘鎻愪氦鑷繁鐨勫緟瀹℃牳鐢宠" ON "public"."pending_clothes" FOR INSERT TO "authenticated" WITH CHECK (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND ("submitted_by" = ( SELECT "auth"."uid"() AS "uid")) AND ("status" = 'pending'::"text")));



CREATE POLICY "璁よ瘉鐢ㄦ埛鍙煡鐪嬭嚜宸辩殑鐢宠鍙婄鐞嗗憳鍙煡鐪嬪叏閮? ON "public"."pending_clothes" FOR SELECT TO "authenticated" USING (((( SELECT "auth"."uid"() AS "uid") IS NOT NULL) AND (("submitted_by" = ( SELECT "auth"."uid"() AS "uid")) OR ( SELECT "public"."is_admin_or_super_admin"() AS "is_admin_or_super_admin"))));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



REVOKE ALL ON FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."add_clothes_to_submitter_wardrobes"("p_user_ids" "uuid"[], "p_clothes_id" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "service_role";



REVOKE ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "authenticated";
GRANT ALL ON FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) TO "service_role";



REVOKE ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") TO "service_role";



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



REVOKE ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") TO "service_role";



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



GRANT ALL ON TABLE "public"."pending_clothes" TO "service_role";
GRANT SELECT,INSERT ON TABLE "public"."pending_clothes" TO "authenticated";



GRANT UPDATE("status") ON TABLE "public"."pending_clothes" TO "authenticated";



GRANT ALL ON SEQUENCE "public"."pending_clothes_id_seq" TO "service_role";
GRANT SELECT,USAGE ON SEQUENCE "public"."pending_clothes_id_seq" TO "authenticated";



GRANT ALL ON TABLE "public"."pending_suits" TO "anon";
GRANT ALL ON TABLE "public"."pending_suits" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_suits" TO "service_role";



GRANT SELECT,INSERT ON TABLE "public"."points_ledger" TO "service_role";



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
