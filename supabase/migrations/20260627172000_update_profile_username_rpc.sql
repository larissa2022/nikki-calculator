create or replace function public.update_profile_username(p_username text)
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
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

revoke all on function public.update_profile_username(text) from public;
grant execute on function public.update_profile_username(text) to authenticated;
