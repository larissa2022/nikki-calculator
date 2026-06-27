create or replace function public.add_clothes_to_submitter_wardrobes(
  p_user_ids uuid[],
  p_clothes_id text
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
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

revoke all on function public.add_clothes_to_submitter_wardrobes(uuid[], text) from public;

create or replace function public.is_admin_or_super_admin()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(
    select 1
    from public.profiles
    where id = auth.uid()
      and role in ('admin', 'super_admin')
  );
$$;

revoke all on function public.is_admin_or_super_admin() from public;
grant execute on function public.is_admin_or_super_admin() to authenticated;

create or replace function public.submit_clothing_contribution(
  p_name text,
  p_game_id text,
  p_category text,
  p_stars integer,
  p_scores jsonb,
  p_suit_id uuid default null,
  p_temp_suit_name text default null,
  p_tags text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
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
$$;

revoke all on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) from public;
grant execute on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) to authenticated;

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
set search_path = public
as $$
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
$$;

revoke all on function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) from public;
grant execute on function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) to authenticated;
