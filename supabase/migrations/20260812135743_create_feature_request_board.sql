begin;

create table public.feature_requests (
  id uuid primary key default extensions.gen_random_uuid(),
  submitted_by uuid references auth.users (id) on delete set null,
  title text not null,
  description text not null,
  content_fingerprint text not null,
  status text not null default 'pending',
  visibility text not null default 'public',
  public_response text,
  duplicate_of uuid references public.feature_requests (id) on delete restrict,
  handled_by uuid references auth.users (id) on delete set null,
  handled_at timestamptz,
  created_at timestamptz not null default pg_catalog.now(),
  updated_at timestamptz not null default pg_catalog.now(),

  constraint feature_requests_title_check
    check (pg_catalog.char_length(pg_catalog.btrim(title)) between 5 and 80),
  constraint feature_requests_description_check
    check (pg_catalog.char_length(pg_catalog.btrim(description)) between 10 and 1000),
  constraint feature_requests_fingerprint_check
    check (content_fingerprint ~ '^[0-9a-f]{32}$'),
  constraint feature_requests_status_check
    check (status in ('pending', 'planned', 'not_feasible')),
  constraint feature_requests_visibility_check
    check (visibility in ('public', 'withdrawn', 'duplicate', 'hidden')),
  constraint feature_requests_duplicate_shape_check
    check (
      (visibility = 'duplicate' and duplicate_of is not null)
      or (visibility <> 'duplicate' and duplicate_of is null)
    ),
  constraint feature_requests_not_self_duplicate_check
    check (duplicate_of is null or duplicate_of <> id),
  constraint feature_requests_handling_shape_check
    check (
      (status = 'pending' and handled_at is null and handled_by is null)
      or (status <> 'pending' and handled_at is not null)
    )
);

create unique index feature_requests_public_content_key
  on public.feature_requests (content_fingerprint)
  where visibility = 'public';

create index feature_requests_public_pending_order_idx
  on public.feature_requests (created_at, id)
  where visibility = 'public' and status = 'pending';

create index feature_requests_public_handled_order_idx
  on public.feature_requests (status, handled_at desc, id)
  where visibility = 'public' and status <> 'pending';

create index feature_requests_submitter_history_idx
  on public.feature_requests (submitted_by, created_at desc, id)
  where submitted_by is not null;

create index feature_requests_duplicate_of_idx
  on public.feature_requests (duplicate_of)
  where duplicate_of is not null;

create index feature_requests_handled_by_idx
  on public.feature_requests (handled_by)
  where handled_by is not null;

create table public.feature_request_likes (
  id uuid primary key default extensions.gen_random_uuid(),
  feature_request_id uuid not null references public.feature_requests (id) on delete restrict,
  user_id uuid references auth.users (id) on delete set null,
  is_active boolean not null default true,
  created_at timestamptz not null default pg_catalog.now(),
  cancelled_at timestamptz,
  updated_at timestamptz not null default pg_catalog.now(),

  constraint feature_request_likes_cancelled_shape_check
    check (
      (is_active and cancelled_at is null)
      or (not is_active and cancelled_at is not null)
    )
);

create unique index feature_request_likes_active_user_key
  on public.feature_request_likes (feature_request_id, user_id)
  where user_id is not null and is_active;

create index feature_request_likes_active_count_idx
  on public.feature_request_likes (feature_request_id)
  where is_active;

create index feature_request_likes_user_history_idx
  on public.feature_request_likes (user_id, updated_at desc)
  where user_id is not null;

create table public.feature_request_events (
  id bigint generated always as identity primary key,
  feature_request_id uuid not null references public.feature_requests (id) on delete restrict,
  actor_user_id uuid references auth.users (id) on delete set null,
  event_type text not null,
  from_status text,
  to_status text,
  from_visibility text,
  to_visibility text,
  reason text,
  public_response text,
  duplicate_of uuid references public.feature_requests (id) on delete restrict,
  created_at timestamptz not null default pg_catalog.now(),

  constraint feature_request_events_type_check
    check (event_type in (
      'submitted',
      'planned',
      'not_feasible',
      'reopened',
      'withdrawn',
      'marked_duplicate',
      'hidden',
      'restored'
    )),
  constraint feature_request_events_status_check
    check (
      (from_status is null or from_status in ('pending', 'planned', 'not_feasible'))
      and (to_status is null or to_status in ('pending', 'planned', 'not_feasible'))
    ),
  constraint feature_request_events_visibility_check
    check (
      (from_visibility is null or from_visibility in ('public', 'withdrawn', 'duplicate', 'hidden'))
      and (to_visibility is null or to_visibility in ('public', 'withdrawn', 'duplicate', 'hidden'))
    )
);

create index feature_request_events_request_history_idx
  on public.feature_request_events (feature_request_id, created_at, id);

create index feature_request_events_actor_idx
  on public.feature_request_events (actor_user_id)
  where actor_user_id is not null;

create index feature_request_events_duplicate_of_idx
  on public.feature_request_events (duplicate_of)
  where duplicate_of is not null;

alter table public.feature_requests enable row level security;
alter table public.feature_requests force row level security;
alter table public.feature_request_likes enable row level security;
alter table public.feature_request_likes force row level security;
alter table public.feature_request_events enable row level security;
alter table public.feature_request_events force row level security;

revoke all on table public.feature_requests
  from public, anon, authenticated, service_role;
revoke all on table public.feature_request_likes
  from public, anon, authenticated, service_role;
revoke all on table public.feature_request_events
  from public, anon, authenticated, service_role;
revoke all on sequence public.feature_request_events_id_seq
  from public, anon, authenticated, service_role;

grant select, insert, update on table public.feature_requests to service_role;
grant select, insert, update on table public.feature_request_likes to service_role;
grant select, insert on table public.feature_request_events to service_role;

create function private_db2.feature_request_fingerprint(
  p_title text,
  p_description text
)
returns text
language sql
immutable
security invoker
set search_path = ''
as $$
  select pg_catalog.md5(
    pg_catalog.lower(
      pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_title, '')), '\s+', ' ', 'g')
    ) || E'\n' ||
    pg_catalog.lower(
      pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_description, '')), '\s+', ' ', 'g')
    )
  );
$$;

create function private_db2.feature_request_like_count(p_request_id uuid)
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select pg_catalog.count(*)
  from public.feature_request_likes as feature_like
  where feature_like.feature_request_id = p_request_id
    and feature_like.is_active;
$$;

revoke all on function private_db2.feature_request_fingerprint(text, text)
  from public, anon, authenticated, service_role;
revoke all on function private_db2.feature_request_like_count(uuid)
  from public, anon, authenticated, service_role;

create function public.list_feature_requests(
  p_filter text default 'pending',
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_filter text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_filter, 'pending')));
  v_limit integer := least(greatest(coalesce(p_limit, 50), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_result jsonb;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('anon', 'authenticated', 'service_role') then
    raise exception using errcode = '42501', message = '无权读取优化建议';
  end if;
  if v_filter not in ('pending', 'planned', 'not_feasible') then
    raise exception using errcode = '22023', message = '不支持的建议筛选状态';
  end if;

  select coalesce(pg_catalog.jsonb_agg(row_payload order by sort_likes desc, sort_time, sort_id), '[]'::jsonb)
  into v_result
  from (
    select
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'title', request.title,
        'description', request.description,
        'status', request.status,
        'public_response', request.public_response,
        'like_count', private_db2.feature_request_like_count(request.id),
        'has_liked', exists (
          select 1
          from public.feature_request_likes as own_like
          where own_like.feature_request_id = request.id
            and own_like.user_id = v_user_id
            and own_like.is_active
        ),
        'can_withdraw', request.status = 'pending'
          and request.submitted_by = v_user_id,
        'created_at', request.created_at,
        'updated_at', request.updated_at,
        'handled_at', request.handled_at
      ) as row_payload,
      case when v_filter = 'pending'
        then private_db2.feature_request_like_count(request.id)
        else 0
      end as sort_likes,
      case when v_filter = 'pending'
        then request.created_at
        else coalesce(request.handled_at, request.updated_at)
      end as sort_time,
      request.id as sort_id
    from public.feature_requests as request
    where request.visibility = 'public'
      and request.status = v_filter
    order by
      case when v_filter = 'pending'
        then private_db2.feature_request_like_count(request.id)
        else 0
      end desc,
      case when v_filter = 'pending'
        then request.created_at
        else coalesce(request.handled_at, request.updated_at)
      end asc,
      request.id
    limit v_limit
    offset v_offset
  ) as listed;

  if v_filter <> 'pending' then
    select coalesce(pg_catalog.jsonb_agg(row_payload order by sort_time desc, sort_id desc), '[]'::jsonb)
    into v_result
    from (
      select
        pg_catalog.jsonb_build_object(
          'request_id', request.id,
          'title', request.title,
          'description', request.description,
          'status', request.status,
          'public_response', request.public_response,
          'like_count', private_db2.feature_request_like_count(request.id),
          'has_liked', exists (
            select 1
            from public.feature_request_likes as own_like
            where own_like.feature_request_id = request.id
              and own_like.user_id = v_user_id
              and own_like.is_active
          ),
          'can_withdraw', false,
          'created_at', request.created_at,
          'updated_at', request.updated_at,
          'handled_at', request.handled_at
        ) as row_payload,
        coalesce(request.handled_at, request.updated_at) as sort_time,
        request.id as sort_id
      from public.feature_requests as request
      where request.visibility = 'public'
        and request.status = v_filter
      order by coalesce(request.handled_at, request.updated_at) desc, request.id desc
      limit v_limit
      offset v_offset
    ) as listed;
  end if;

  return v_result;
end;
$$;

create function public.get_my_feature_requests()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_user_id is null then
    raise exception using errcode = '42501', message = '请先登录后查看自己的建议';
  end if;

  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'request_id', request.id,
      'title', request.title,
      'description', request.description,
      'status', request.status,
      'visibility', request.visibility,
      'public_response', request.public_response,
      'like_count', private_db2.feature_request_like_count(request.id),
      'has_liked', exists (
        select 1
        from public.feature_request_likes as own_like
        where own_like.feature_request_id = request.id
          and own_like.user_id = v_user_id
          and own_like.is_active
      ),
      'can_withdraw', request.visibility = 'public' and request.status = 'pending',
      'duplicate_of', request.duplicate_of,
      'created_at', request.created_at,
      'updated_at', request.updated_at,
      'handled_at', request.handled_at
    ) order by request.created_at desc, request.id desc
  ), '[]'::jsonb)
  into v_result
  from public.feature_requests as request
  where request.submitted_by = v_user_id;

  return v_result;
end;
$$;

create function public.submit_feature_request(
  p_title text,
  p_description text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_title text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_title, '')), '\s+', ' ', 'g');
  v_description text := pg_catalog.regexp_replace(pg_catalog.btrim(coalesce(p_description, '')), '\s+', ' ', 'g');
  v_fingerprint text;
  v_existing public.feature_requests%rowtype;
  v_request public.feature_requests%rowtype;
  v_day_start timestamptz;
  v_day_end timestamptz;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_user_id is null then
    raise exception using errcode = '42501', message = '请先登录后提交优化建议';
  end if;

  if pg_catalog.char_length(v_title) not between 5 and 80 then
    raise exception using errcode = '22023', message = '建议标题需填写 5 到 80 个字';
  end if;
  if pg_catalog.char_length(v_description) not between 10 and 1000 then
    raise exception using errcode = '22023', message = '建议说明需填写 10 到 1000 个字';
  end if;

  v_fingerprint := private_db2.feature_request_fingerprint(v_title, v_description);
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('feature-request-user|' || v_user_id::text, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('feature-request-content|' || v_fingerprint, 0)
  );

  select request.* into v_existing
  from public.feature_requests as request
  where request.content_fingerprint = v_fingerprint
    and request.visibility = 'public'
  order by request.created_at, request.id
  limit 1;

  if found then
    return pg_catalog.jsonb_build_object(
      'request_id', v_existing.id,
      'status', v_existing.status,
      'duplicate', true,
      'message', '已有相同建议，请直接为现有建议点赞'
    );
  end if;

  v_day_start := pg_catalog.date_trunc(
    'day', pg_catalog.timezone('Asia/Shanghai', pg_catalog.now())
  ) at time zone 'Asia/Shanghai';
  v_day_end := v_day_start + interval '1 day';

  if (
    select pg_catalog.count(*)
    from public.feature_requests as request
    where request.submitted_by = v_user_id
      and request.created_at >= v_day_start
      and request.created_at < v_day_end
  ) >= 5 then
    raise exception using errcode = '22023', message = '每个北京自然日最多提交 5 条优化建议';
  end if;

  insert into public.feature_requests (
    submitted_by,
    title,
    description,
    content_fingerprint
  ) values (
    v_user_id,
    v_title,
    v_description,
    v_fingerprint
  )
  returning * into v_request;

  insert into public.feature_request_events (
    feature_request_id,
    actor_user_id,
    event_type,
    to_status,
    to_visibility
  ) values (
    v_request.id,
    v_user_id,
    'submitted',
    v_request.status,
    v_request.visibility
  );

  return pg_catalog.jsonb_build_object(
    'request_id', v_request.id,
    'status', v_request.status,
    'duplicate', false,
    'message', '优化建议已提交'
  );
exception
  when unique_violation then
    select request.* into v_existing
    from public.feature_requests as request
    where request.content_fingerprint = v_fingerprint
      and request.visibility = 'public'
    order by request.created_at, request.id
    limit 1;

    if found then
      return pg_catalog.jsonb_build_object(
        'request_id', v_existing.id,
        'status', v_existing.status,
        'duplicate', true,
        'message', '已有相同建议，请直接为现有建议点赞'
      );
    end if;
    raise;
end;
$$;

create function public.set_feature_request_like(
  p_request_id uuid,
  p_liked boolean
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_request public.feature_requests%rowtype;
  v_active_like public.feature_request_likes%rowtype;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_user_id is null then
    raise exception using errcode = '42501', message = '请先登录后点赞';
  end if;
  if p_request_id is null or p_liked is null then
    raise exception using errcode = '22023', message = '点赞参数不完整';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      'feature-request-like|' || p_request_id::text || '|' || v_user_id::text,
      0
    )
  );

  select request.* into v_request
  from public.feature_requests as request
  where request.id = p_request_id
  for key share;

  if not found or v_request.visibility <> 'public' then
    raise exception using errcode = 'P0002', message = '找不到可点赞的建议';
  end if;

  if p_liked then
    select feature_like.* into v_active_like
    from public.feature_request_likes as feature_like
    where feature_like.feature_request_id = p_request_id
      and feature_like.user_id = v_user_id
      and feature_like.is_active
    for update;

    if not found then
      insert into public.feature_request_likes (
        feature_request_id,
        user_id,
        is_active,
        cancelled_at
      ) values (
        p_request_id,
        v_user_id,
        true,
        null
      );
    end if;
  else
    update public.feature_request_likes as feature_like
    set
      is_active = false,
      cancelled_at = pg_catalog.now(),
      updated_at = pg_catalog.now()
    where feature_like.feature_request_id = p_request_id
      and feature_like.user_id = v_user_id
      and feature_like.is_active;
  end if;

  return pg_catalog.jsonb_build_object(
    'request_id', p_request_id,
    'has_liked', p_liked,
    'like_count', private_db2.feature_request_like_count(p_request_id)
  );
end;
$$;

create function public.withdraw_feature_request(p_request_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_request public.feature_requests%rowtype;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_user_id is null then
    raise exception using errcode = '42501', message = '请先登录后撤回建议';
  end if;

  select request.* into v_request
  from public.feature_requests as request
  where request.id = p_request_id
  for update;

  if not found or v_request.submitted_by <> v_user_id then
    raise exception using errcode = '42501', message = '只能撤回自己提交的建议';
  end if;
  if v_request.visibility <> 'public' or v_request.status <> 'pending' then
    raise exception using errcode = '22023', message = '只有待评估的公开建议可以撤回';
  end if;

  update public.feature_requests
  set visibility = 'withdrawn', updated_at = pg_catalog.now()
  where id = p_request_id;

  insert into public.feature_request_events (
    feature_request_id,
    actor_user_id,
    event_type,
    from_status,
    to_status,
    from_visibility,
    to_visibility,
    reason
  ) values (
    p_request_id,
    v_user_id,
    'withdrawn',
    v_request.status,
    v_request.status,
    v_request.visibility,
    'withdrawn',
    '提交者主动撤回'
  );

  return pg_catalog.jsonb_build_object(
    'request_id', p_request_id,
    'visibility', 'withdrawn'
  );
end;
$$;

create function public.list_feature_requests_for_admin()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可处理优化建议';
  end if;

  select coalesce(pg_catalog.jsonb_agg(
    pg_catalog.jsonb_build_object(
      'request_id', request.id,
      'title', request.title,
      'description', request.description,
      'status', request.status,
      'visibility', request.visibility,
      'public_response', request.public_response,
      'like_count', private_db2.feature_request_like_count(request.id),
      'author_id', request.submitted_by,
      'author_name', case
        when request.submitted_by is null then '已注销用户'
        when nullif(pg_catalog.btrim(profile.username), '') is not null
          then pg_catalog.btrim(profile.username)
        else '匿名搭配师-' || pg_catalog.upper(
          pg_catalog.substr(pg_catalog.md5(request.submitted_by::text), 1, 8)
        )
      end,
      'duplicate_of', request.duplicate_of,
      'handled_at', request.handled_at,
      'created_at', request.created_at,
      'updated_at', request.updated_at
    ) order by
      (request.visibility = 'public' and request.status = 'pending') desc,
      private_db2.feature_request_like_count(request.id) desc,
      request.created_at
  ), '[]'::jsonb)
  into v_result
  from public.feature_requests as request
  left join public.profiles as profile on profile.id = request.submitted_by;

  return v_result;
end;
$$;

create function public.moderate_feature_request(
  p_request_id uuid,
  p_action text,
  p_reason text,
  p_public_response text default null,
  p_duplicate_of uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_action text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_action, '')));
  v_reason text := pg_catalog.btrim(coalesce(p_reason, ''));
  v_response text := nullif(pg_catalog.btrim(coalesce(p_public_response, '')), '');
  v_request public.feature_requests%rowtype;
  v_duplicate public.feature_requests%rowtype;
  v_next_status text;
  v_next_visibility text;
  v_event_type text;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null
    or not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可处理优化建议';
  end if;
  if pg_catalog.char_length(v_reason) not between 2 and 500 then
    raise exception using errcode = '22023', message = '处理原因需填写 2 到 500 个字';
  end if;
  if v_response is not null and pg_catalog.char_length(v_response) > 1000 then
    raise exception using errcode = '22023', message = '公开说明不能超过 1000 个字';
  end if;

  select request.* into v_request
  from public.feature_requests as request
  where request.id = p_request_id
  for update;
  if not found then
    raise exception using errcode = 'P0002', message = '找不到需要处理的优化建议';
  end if;

  v_next_status := v_request.status;
  v_next_visibility := v_request.visibility;

  case v_action
    when 'plan' then
      if v_request.visibility <> 'public' then
        raise exception using errcode = '22023', message = '只有公开建议可以标记计划中';
      end if;
      v_next_status := 'planned';
      v_event_type := 'planned';
    when 'not_feasible' then
      if v_request.visibility <> 'public' or v_response is null then
        raise exception using errcode = '22023', message = '标记技术无法实现需要公开建议和公开说明';
      end if;
      v_next_status := 'not_feasible';
      v_event_type := 'not_feasible';
    when 'reopen' then
      if v_request.visibility <> 'public' or v_request.status = 'pending' then
        raise exception using errcode = '22023', message = '只有已评估的公开建议可以重新评估';
      end if;
      v_next_status := 'pending';
      v_response := null;
      v_event_type := 'reopened';
    when 'mark_duplicate' then
      if v_request.visibility <> 'public' or p_duplicate_of is null or p_duplicate_of = p_request_id then
        raise exception using errcode = '22023', message = '请选择另一个公开建议作为重复目标';
      end if;
      select request.* into v_duplicate
      from public.feature_requests as request
      where request.id = p_duplicate_of
        and request.visibility = 'public'
      for key share;
      if not found then
        raise exception using errcode = '22023', message = '重复目标必须是公开建议';
      end if;
      v_next_visibility := 'duplicate';
      v_event_type := 'marked_duplicate';
    when 'hide' then
      if v_request.visibility <> 'public' then
        raise exception using errcode = '22023', message = '只有公开建议可以隐藏';
      end if;
      v_next_visibility := 'hidden';
      v_event_type := 'hidden';
    when 'restore' then
      if v_request.visibility not in ('hidden', 'duplicate') then
        raise exception using errcode = '22023', message = '只有已隐藏或重复归档建议可以恢复';
      end if;
      if exists (
        select 1
        from public.feature_requests as public_request
        where public_request.content_fingerprint = v_request.content_fingerprint
          and public_request.visibility = 'public'
          and public_request.id <> v_request.id
      ) then
        raise exception using errcode = '23505', message = '已有相同内容的公开建议，不能恢复';
      end if;
      v_next_visibility := 'public';
      v_event_type := 'restored';
    else
      raise exception using errcode = '22023', message = '不支持的建议处理动作';
  end case;

  update public.feature_requests
  set
    status = v_next_status,
    visibility = v_next_visibility,
    public_response = case
      when v_action in ('plan', 'not_feasible') then v_response
      when v_action = 'reopen' then null
      else public_response
    end,
    duplicate_of = case when v_next_visibility = 'duplicate' then p_duplicate_of else null end,
    handled_by = case when v_next_status = 'pending' then null else v_actor end,
    handled_at = case when v_next_status = 'pending' then null else pg_catalog.now() end,
    updated_at = pg_catalog.now()
  where id = p_request_id;

  insert into public.feature_request_events (
    feature_request_id,
    actor_user_id,
    event_type,
    from_status,
    to_status,
    from_visibility,
    to_visibility,
    reason,
    public_response,
    duplicate_of
  ) values (
    p_request_id,
    v_actor,
    v_event_type,
    v_request.status,
    v_next_status,
    v_request.visibility,
    v_next_visibility,
    v_reason,
    v_response,
    case when v_next_visibility = 'duplicate' then p_duplicate_of else null end
  );

  return pg_catalog.jsonb_build_object(
    'request_id', p_request_id,
    'status', v_next_status,
    'visibility', v_next_visibility
  );
end;
$$;

revoke all on function public.list_feature_requests(text, integer, integer)
  from public, anon, authenticated, service_role;
grant execute on function public.list_feature_requests(text, integer, integer)
  to anon, authenticated, service_role;

revoke all on function public.get_my_feature_requests()
  from public, anon, authenticated, service_role;
grant execute on function public.get_my_feature_requests()
  to authenticated, service_role;

revoke all on function public.submit_feature_request(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.submit_feature_request(text, text)
  to authenticated, service_role;

revoke all on function public.set_feature_request_like(uuid, boolean)
  from public, anon, authenticated, service_role;
grant execute on function public.set_feature_request_like(uuid, boolean)
  to authenticated, service_role;

revoke all on function public.withdraw_feature_request(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.withdraw_feature_request(uuid)
  to authenticated, service_role;

revoke all on function public.list_feature_requests_for_admin()
  from public, anon, authenticated, service_role;
grant execute on function public.list_feature_requests_for_admin()
  to authenticated, service_role;

revoke all on function public.moderate_feature_request(uuid, text, text, text, uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.moderate_feature_request(uuid, text, text, text, uuid)
  to authenticated, service_role;

comment on table public.feature_requests is
  'V1 优化建议事实；正文提交后不可编辑，公开状态只包含待评估、计划中、技术无法实现。';
comment on table public.feature_request_likes is
  'V1 等权点赞事实；取消通过状态和取消时间表达，账号删除后匿名保留历史有效点赞。';
comment on table public.feature_request_events is
  'V1 建议提交、评估、重新评估、撤回、重复归档、隐藏和恢复的追加式审计事件。';

commit;
