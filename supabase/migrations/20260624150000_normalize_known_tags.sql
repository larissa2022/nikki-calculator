create or replace function public.normalize_known_clothing_tags(p_tags text)
returns text
language plpgsql
immutable
as $$
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

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'pending_clothes'
      and column_name = 'tags'
  ) then
    update public.pending_clothes
    set tags = public.normalize_known_clothing_tags(tags)
    where tags is not null
      and tags is distinct from public.normalize_known_clothing_tags(tags);
  end if;
end;
$$;

do $$
begin
  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'clothes'
      and column_name = 'tags'
  ) then
    update public.clothes
    set tags = public.normalize_known_clothing_tags(tags)
    where tags is not null
      and tags is distinct from public.normalize_known_clothing_tags(tags);
  end if;
end;
$$;
