


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


CREATE OR REPLACE FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") RETURNS boolean
    LANGUAGE "plpgsql" SECURITY DEFINER
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
    AS $$
BEGIN
  INSERT INTO public.profiles (id, email, nickname, role, quota)
  VALUES (new.id, new.email, split_part(new.email, '@', 1), 'user', 30);
  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user_quota"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
BEGIN
  INSERT INTO public.user_quotas (user_id, free_count)
  VALUES (new.id, 30); -- 新用户默认给 20 次
  RETURN new;
END;
$$;


ALTER FUNCTION "public"."handle_new_user_quota"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_super_admin"() RETURNS boolean
    LANGUAGE "sql" SECURITY DEFINER
    AS $$
  select exists(select 1 from public.profiles where id = auth.uid() and role = 'super_admin');
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


CREATE OR REPLACE FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid" DEFAULT NULL::"uuid", "p_temp_suit_name" "text" DEFAULT NULL::"text", "p_tags" "text" DEFAULT NULL::"text") RETURNS "jsonb"
    LANGUAGE "plpgsql" SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
declare
  v_user_id uuid := auth.uid();
  v_clothes_id text;
  v_pending_id bigint;
  v_matching_pending_ids bigint[];
  v_matching_count integer := 0;
  v_can_auto_approve boolean;
begin
  if v_user_id is null then
    raise exception '需要登录后才能提交图鉴申请';
  end if;

  if nullif(trim(coalesce(p_name, '')), '') is null then
    raise exception '服装名称不能为空';
  end if;

  if nullif(trim(coalesce(p_game_id, '')), '') is null then
    raise exception '短编号不能为空';
  end if;

  v_can_auto_approve := p_game_id <> 'N' and (p_suit_id is not null or nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null);

  if v_can_auto_approve then
    select coalesce(array_agg(id order by created_at asc), '{}')::bigint[], count(*)::integer
      into v_matching_pending_ids, v_matching_count
    from public.pending_clothes
    where status = 'pending'
      and name is not distinct from p_name
      and game_id is not distinct from p_game_id
      and category is not distinct from p_category
      and stars is not distinct from p_stars
      and tags is not distinct from p_tags
      and suit_id is not distinct from p_suit_id
      and temp_suit_name is not distinct from p_temp_suit_name
      and scores = p_scores;

    if v_matching_count >= 4 then
      v_clothes_id := 'custom_' || replace(gen_random_uuid()::text, '-', '');

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
        p_game_id,
        p_category,
        p_stars::text,
        p_scores,
        p_suit_id,
        p_temp_suit_name,
        p_tags
      );

      delete from public.pending_clothes
      where id = any(v_matching_pending_ids);

      if p_suit_id is null and nullif(trim(coalesce(p_temp_suit_name, '')), '') is not null then
        insert into public.pending_suits (name, submitted_by, status)
        values (p_temp_suit_name, v_user_id, 'pending');
      end if;

      return jsonb_build_object(
        'auto_approved', true,
        'clothes_id', v_clothes_id,
        'matched_pending_count', v_matching_count
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
    p_game_id,
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
$$;


ALTER FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


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
    "monthly_action_count" integer DEFAULT 0
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


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



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."pending_suits"
    ADD CONSTRAINT "pending_suits_pkey" PRIMARY KEY ("id");



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



CREATE INDEX "idx_clothes_suit_id" ON "public"."clothes" USING "btree" ("suit_id");



CREATE INDEX "idx_pending_clothes_status" ON "public"."pending_clothes" USING "btree" ("status");



CREATE INDEX "idx_pending_suits_status" ON "public"."pending_suits" USING "btree" ("status");



CREATE INDEX "idx_profiles_username" ON "public"."profiles" USING "btree" ("username");



CREATE INDEX "idx_suits_name" ON "public"."suits" USING "btree" ("name");



CREATE OR REPLACE TRIGGER "trigger_auto_link_shadow_suits" AFTER INSERT ON "public"."suits" FOR EACH ROW EXECUTE FUNCTION "public"."auto_link_shadow_suits"();



ALTER TABLE ONLY "public"."clothes"
    ADD CONSTRAINT "clothes_suit_id_fkey" FOREIGN KEY ("suit_id") REFERENCES "public"."suits"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



ALTER TABLE ONLY "public"."pending_clothes"
    ADD CONSTRAINT "pending_clothes_suit_id_fkey" FOREIGN KEY ("suit_id") REFERENCES "public"."suits"("id") ON DELETE SET NULL;



ALTER TABLE ONLY "public"."pending_suits"
    ADD CONSTRAINT "pending_suits_submitted_by_fkey" FOREIGN KEY ("submitted_by") REFERENCES "auth"."users"("id");



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


ALTER TABLE "public"."pending_suits" ENABLE ROW LEVEL SECURITY;


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



CREATE POLICY "允许认证用户提交完整申请" ON "public"."pending_clothes" FOR INSERT TO "authenticated" WITH CHECK (true);



CREATE POLICY "允许超管修改档案" ON "public"."profiles" FOR UPDATE TO "authenticated" USING ("public"."is_super_admin"());



CREATE POLICY "用户只能操作自己的衣柜" ON "public"."user_wardrobes" TO "authenticated" USING (("auth"."uid"() = "user_id")) WITH CHECK (("auth"."uid"() = "user_id"));



CREATE POLICY "用户可以查看自己的画像" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "管理员权限" ON "public"."clothes" TO "authenticated" USING (("auth"."email"() = '2230909994@qq.com'::"text")) WITH CHECK (("auth"."email"() = '2230909994@qq.com'::"text"));



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";



GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "anon";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."auto_link_shadow_suits"() TO "service_role";



GRANT ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") TO "anon";
GRANT ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") TO "authenticated";
GRANT ALL ON FUNCTION "public"."deduct_user_quota"("user_id_param" "uuid") TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user_quota"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_quota"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_quota"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_super_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."normalize_known_clothing_tags"("p_tags" "text") TO "service_role";



REVOKE ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") FROM PUBLIC;
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."submit_clothing_contribution"("p_name" "text", "p_game_id" "text", "p_category" "text", "p_stars" integer, "p_scores" "jsonb", "p_suit_id" "uuid", "p_temp_suit_name" "text", "p_tags" "text") TO "service_role";



GRANT ALL ON TABLE "public"."app_errors" TO "anon";
GRANT ALL ON TABLE "public"."app_errors" TO "authenticated";
GRANT ALL ON TABLE "public"."app_errors" TO "service_role";



GRANT ALL ON TABLE "public"."clothes" TO "anon";
GRANT ALL ON TABLE "public"."clothes" TO "authenticated";
GRANT ALL ON TABLE "public"."clothes" TO "service_role";



GRANT ALL ON TABLE "public"."pending_clothes" TO "anon";
GRANT ALL ON TABLE "public"."pending_clothes" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_clothes" TO "service_role";



GRANT ALL ON SEQUENCE "public"."pending_clothes_id_seq" TO "anon";
GRANT ALL ON SEQUENCE "public"."pending_clothes_id_seq" TO "authenticated";
GRANT ALL ON SEQUENCE "public"."pending_clothes_id_seq" TO "service_role";



GRANT ALL ON TABLE "public"."pending_suits" TO "anon";
GRANT ALL ON TABLE "public"."pending_suits" TO "authenticated";
GRANT ALL ON TABLE "public"."pending_suits" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



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







