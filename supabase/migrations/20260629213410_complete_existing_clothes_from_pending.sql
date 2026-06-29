create or replace function public.complete_existing_clothes_from_pending(
  p_existing_id text,
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

  update public.clothes
  set
    game_id = trim(p_game_id),
    stars = p_stars::text,
    scores = p_scores,
    suit_id = p_suit_id,
    temp_suit_name = p_temp_suit_name,
    tags = p_tags
  where id = p_existing_id
    and name is not distinct from p_name
    and category is not distinct from p_category;

  if not found then
    raise exception '正式库服装不存在，或名称分类与待审核记录不一致';
  end if;

  select coalesce(array_agg(distinct submitted_by), '{}')::uuid[]
    into v_submitter_ids
  from public.pending_clothes
  where id = any(v_pending_ids)
    and submitted_by is not null;

  v_wardrobe_count := public.add_clothes_to_submitter_wardrobes(v_submitter_ids, p_existing_id);

  if array_length(v_pending_ids, 1) is not null then
    update public.pending_clothes
    set status = 'approved'
    where id = any(v_pending_ids)
      and status = 'pending';
  end if;

  return jsonb_build_object(
    'completed_existing', true,
    'clothes_id', p_existing_id,
    'submitter_count', coalesce(array_length(v_submitter_ids, 1), 0),
    'wardrobe_updated_count', v_wardrobe_count
  );
end;
$$;

revoke all on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) from public;
grant execute on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) to authenticated;
