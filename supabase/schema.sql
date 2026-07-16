


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


CREATE OR REPLACE FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text", "p_pending_ids" bigint[] DEFAULT '{}'::bigint[]) RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $_$
declare
  v_pending_ids bigint[] := coalesce(p_pending_ids, '{}');
  v_submitter_ids uuid[];
  v_wardrobe_count integer := 0;
begin
  if not public.is_admin_or_super_admin() then
    raise exception '没有仲裁入库权限';
  end if;

  if nullif(trim(coalesce(p_id, '')), '') is null then
    raise exception '服装 ID 不能为空';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(trim(coalesce(p_game_id, '')), '') is null then
    raise exception '短编号不能为空';
  end if;

  if trim(p_game_id) !~ '^[0-9]+$' then
    raise exception '短编号只允许填写数字';
  end if;

  select coalesce(array_agg(distinct submitted_by), '{}')::uuid[]
    into v_submitter_ids
  from public.pending_clothes
  where id = any(v_pending_ids)
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
    p_id,
    p_name,
    trim(p_game_id),
    p_category,
    p_stars::text,
    p_scores,
    p_suit_id,
    p_temp_suit_name,
    p_tags
  );

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(v_submitter_ids, p_id);

  if array_length(v_pending_ids, 1) is not null then
    update public.pending_clothes
    set status = 'approved'
    where id = any(v_pending_ids);
  end if;

  return jsonb_build_object(
    'approved', true,
    'clothes_id', p_id,
    'submitter_count', coalesce(array_length(v_submitter_ids, 1), 0),
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$_$;


ALTER FUNCTION "public"."approve_pending_clothes_arbitration"("p_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


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
    SET "search_path" TO 'public'
    AS $_$
declare
  v_pending_ids bigint[] := coalesce(p_pending_ids, '{}');
  v_existing_clothes public.clothes%rowtype;
  v_requested_pending_count integer := 0;
  v_matched_pending_count integer := 0;
  v_approved_pending_count integer := 0;
  v_submitter_ids uuid[];
  v_wardrobe_count integer := 0;
begin
  -- 本 RPC 只用于正式库已有记录的空字段补全。
  -- 不用于覆盖正式库已有非空字段；非空字段修正应进入重审 / 陪审团路径。
  if not public.is_admin_or_super_admin() then
    raise exception '没有补全正式库权限';
  end if;

  if nullif(trim(coalesce(p_existing_id, '')), '') is null then
    raise exception '正式库服装 ID 不能为空';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(trim(coalesce(p_category, '')), '') is null then
    raise exception '分类部位不能为空';
  end if;

  if nullif(trim(coalesce(p_game_id, '')), '') is null or trim(p_game_id) !~ '^[0-9]+$' then
    raise exception '短编号必须为数字';
  end if;

  if p_stars is null then
    raise exception '星级不能为空';
  end if;

  if p_scores is null then
    raise exception '属性分值不能为空';
  end if;

  if array_length(v_pending_ids, 1) is null then
    raise exception '待审核记录不能为空';
  end if;

  select *
    into v_existing_clothes
  from public.clothes
  where id = p_existing_id
    and name is not distinct from p_name
    and category is not distinct from p_category;

  if not found then
    raise exception '正式库服装不存在，或名称分类与待审核记录不一致';
  end if;

  if nullif(trim(coalesce(v_existing_clothes.game_id, '')), '') is not null
    and trim(v_existing_clothes.game_id) is distinct from trim(p_game_id) then
    raise exception '正式库短编号已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if nullif(trim(coalesce(v_existing_clothes.stars, '')), '') is not null
    and trim(v_existing_clothes.stars) is distinct from p_stars::text then
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

  if nullif(trim(coalesce(v_existing_clothes.temp_suit_name, '')), '') is not null
    and nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null
    and trim(v_existing_clothes.temp_suit_name) is distinct from trim(p_temp_suit_name) then
    raise exception '正式库临时套装名已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  if nullif(trim(coalesce(v_existing_clothes.tags, '')), '') is not null
    and nullif(trim(coalesce(p_tags, '')), '') is not null
    and trim(v_existing_clothes.tags) is distinct from trim(p_tags) then
    raise exception '正式库标签已有非空值且与待补全内容不一致，需进入重审 / 陪审团路径';
  end if;

  select count(distinct pending_id)
    into v_requested_pending_count
  from unnest(v_pending_ids) as requested(pending_id)
  where pending_id is not null;

  if v_requested_pending_count <> cardinality(v_pending_ids) then
    raise exception '待审核记录包含空值或重复 ID';
  end if;

  select count(*),
         coalesce(array_agg(distinct submitted_by) filter (where submitted_by is not null), '{}')::uuid[]
    into v_matched_pending_count, v_submitter_ids
  from public.pending_clothes
  where id = any(v_pending_ids)
    and status = 'pending'
    and name is not distinct from p_name
    and category is not distinct from p_category
    and nullif(trim(coalesce(game_id, '')), '') is not null
    and trim(game_id) = trim(p_game_id);

  if v_matched_pending_count <> v_requested_pending_count then
    raise exception '存在不属于本次正式库补全范围的待审核记录，已拒绝自动通过';
  end if;

  update public.clothes
  set
    game_id = case
      when nullif(trim(coalesce(game_id, '')), '') is null then trim(p_game_id)
      else game_id
    end,
    stars = case
      when nullif(trim(coalesce(stars, '')), '') is null then p_stars::text
      else stars
    end,
    scores = case
      when scores is null then p_scores
      else scores
    end,
    suit_id = case
      when suit_id is null then p_suit_id
      else suit_id
    end,
    temp_suit_name = case
      when nullif(trim(coalesce(temp_suit_name, '')), '') is null then p_temp_suit_name
      else temp_suit_name
    end,
    tags = case
      when nullif(trim(coalesce(tags, '')), '') is null then p_tags
      else tags
    end
  where id = v_existing_clothes.id;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(v_submitter_ids, p_existing_id);

  update public.pending_clothes
  set status = 'approved'
  where id = any(v_pending_ids)
    and status = 'pending'
    and name is not distinct from p_name
    and category is not distinct from p_category
    and nullif(trim(coalesce(game_id, '')), '') is not null
    and trim(game_id) = trim(p_game_id);

  get diagnostics v_approved_pending_count = row_count;

  if v_approved_pending_count <> v_requested_pending_count then
    raise exception '待审核记录通过数量异常，已回滚本次补全';
  end if;

  return jsonb_build_object(
    'completed_existing', true,
    'clothes_id', p_existing_id,
    'approved_pending_count', v_approved_pending_count,
    'submitter_count', coalesce(array_length(v_submitter_ids, 1), 0),
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$_$;


ALTER FUNCTION "public"."complete_existing_clothes_from_pending"("p_existing_id" "text", "p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text", "p_pending_ids" bigint[]) OWNER TO "postgres";


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
    raise exception '需要登录后才能提交图鉴申请';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(v_game_id, '') is null then
    raise exception '短编号不能为空';
  end if;

  if v_game_id !~ '^[0-9]+$' then
    raise exception '短编号只允许填写数字';
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
    CONSTRAINT "clothing_contributions_type_check" CHECK (("contribution_type" = ANY (ARRAY['auto_entry'::"text", 'admin_arbitration'::"text", 'existing_field_completion'::"text"])))
);


ALTER TABLE "public"."clothing_contributions" OWNER TO "postgres";


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







