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
$$;

revoke all on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) from public;
grant execute on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[]) to authenticated;
