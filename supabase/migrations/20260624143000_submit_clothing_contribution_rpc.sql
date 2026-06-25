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

revoke all on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) from public;
grant execute on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) to authenticated;
