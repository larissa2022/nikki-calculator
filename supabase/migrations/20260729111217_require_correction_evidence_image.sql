begin;

insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'correction-evidence',
  'correction-evidence',
  false,
  8388608,
  array['image/jpeg', 'image/png', 'image/webp']::text[]
)
on conflict (id) do update
set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

alter table public.correction_requests
  add column evidence_image_path text;

alter table public.correction_requests
  add constraint correction_requests_evidence_image_path_check
  check (
    evidence_image_path is null
    or evidence_image_path ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
  );

create unique index correction_requests_evidence_image_path_unique
  on public.correction_requests (evidence_image_path)
  where evidence_image_path is not null;

comment on column public.correction_requests.evidence_image_path is
  '私有 Storage 桶 correction-evidence 中的游戏内图鉴图片路径；旧报错允许为空，新页面通过专用 RPC 强制上传。';

create or replace function public.can_read_correction_evidence(
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
      select 1
      from public.correction_requests as request
      left join public.re_review_items as item
        on item.id = request.re_review_item_id
      where request.evidence_image_path = p_path
        and (
          request.reported_by = (select auth.uid())
          or (
            (select auth.uid()) is not null
            and item.reason in ('missing_suit', 'field_conflict', 'field_missing', 'correction')
            and item.status in ('pending', 'voting', 'failed')
            and item.submitted_by is distinct from (select auth.uid())
            and not exists (
              select 1
              from public.pending_clothes as primary_source
              where primary_source.id = item.source_pending_id
                and primary_source.submitted_by = (select auth.uid())
            )
            and not exists (
              select 1
              from public.re_review_item_sources as source
              where source.re_review_item_id = item.id
                and source.source_user_id = (select auth.uid())
            )
          )
        )
    );
$$;

create or replace function public.can_delete_correction_evidence(
  p_path text
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select (select auth.uid()) is not null
    and not exists (
      select 1
      from public.correction_requests as request
      where request.evidence_image_path = p_path
    );
$$;

revoke all on function public.can_read_correction_evidence(text)
  from public, anon, authenticated, service_role;
revoke all on function public.can_delete_correction_evidence(text)
  from public, anon, authenticated, service_role;
grant execute on function public.can_read_correction_evidence(text)
  to authenticated, service_role;
grant execute on function public.can_delete_correction_evidence(text)
  to authenticated, service_role;

drop policy if exists correction_evidence_insert_own on storage.objects;
create policy correction_evidence_insert_own
on storage.objects
for insert
to authenticated
with check (
  bucket_id = 'correction-evidence'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

drop policy if exists correction_evidence_select_authenticated on storage.objects;
create policy correction_evidence_select_authenticated
on storage.objects
for select
to authenticated
using (
  bucket_id = 'correction-evidence'
  and (
    owner_id = (select auth.uid())::text
    or (select public.can_read_correction_evidence(name))
  )
);

drop policy if exists correction_evidence_delete_unreferenced_own on storage.objects;
create policy correction_evidence_delete_unreferenced_own
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'correction-evidence'
  and owner_id = (select auth.uid())::text
  and (select public.can_delete_correction_evidence(name))
);

create or replace function public.submit_correction_request_with_evidence(
  p_clothes_id varchar,
  p_proposed_patch jsonb,
  p_evidence_image_path text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_path text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_evidence_image_path, '')));
  v_result jsonb;
  v_request_id uuid;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能提交图鉴报错';
  end if;

  if v_path !~ (
    '^' || v_user_id::text
    || '/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.(jpg|jpeg|png|webp)$'
  ) then
    raise exception '请上传本人目录中的游戏内图鉴图片';
  end if;

  if not exists (
    select 1
    from storage.objects as object
    where object.bucket_id = 'correction-evidence'
      and object.name = v_path
      and object.owner_id = v_user_id::text
      and pg_catalog.lower(coalesce(object.metadata->>'mimetype', ''))
        in ('image/jpeg', 'image/png', 'image/webp')
  ) then
    raise exception '未找到已上传的游戏内图鉴图片，请重新选择图片';
  end if;

  v_result := public.submit_correction_request(
    p_clothes_id,
    '已上传游戏内图鉴图片作为本次报错的核对依据',
    p_proposed_patch
  );
  v_request_id := (v_result->>'request_id')::uuid;

  update public.correction_requests as request
  set
    evidence_image_path = v_path,
    updated_at = pg_catalog.now()
  where request.id = v_request_id
    and request.reported_by = v_user_id
    and (
      request.evidence_image_path is null
      or request.evidence_image_path = v_path
    );

  if not found then
    raise exception '这条报错已经绑定了另一张图鉴图片，不能更换';
  end if;

  return v_result || pg_catalog.jsonb_build_object(
    'evidence_image_path', v_path
  );
end;
$$;

create or replace function public.get_my_correction_requests()
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception using errcode = '42501', message = '需要登录后才能查看图鉴报错';
  end if;

  select coalesce(
    pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'clothes_id', request.clothes_id,
        'clothes_name', coalesce(clothes.name, request.clothes_snapshot->>'name', '已移除服装'),
        'game_id', coalesce(clothes.game_id, request.clothes_snapshot->>'game_id', ''),
        'category', coalesce(clothes.category, request.clothes_snapshot->>'category', ''),
        'field_key', request.field_key,
        'reason', request.reason,
        'evidence_image_path', request.evidence_image_path,
        'proposed_patch', request.proposed_patch,
        'status', request.status,
        'resolution_note', request.resolution_note,
        'created_at', request.created_at,
        'updated_at', request.updated_at
      )
      order by request.created_at desc, request.id desc
    ),
    '[]'::jsonb
  )
    into v_result
  from public.correction_requests as request
  left join public.clothes as clothes on clothes.id = request.clothes_id
  where request.reported_by = v_user_id;

  return v_result;
end;
$$;

create or replace function public.get_jury_review_queue_with_evidence()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_result jsonb;
begin
  select coalesce(
    pg_catalog.jsonb_agg(
      queue.item || pg_catalog.jsonb_build_object(
        'correction_evidence', coalesce(evidence.items, '[]'::jsonb)
      )
      order by queue.ordinality
    ),
    '[]'::jsonb
  )
    into v_result
  from pg_catalog.jsonb_array_elements(public.get_jury_review_queue())
    with ordinality as queue(item, ordinality)
  left join lateral (
    select pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_object(
        'request_id', request.id,
        'field_key', request.field_key,
        'evidence_image_path', request.evidence_image_path
      )
      order by request.created_at, request.id
    ) as items
    from public.correction_requests as request
    where request.re_review_item_id = (queue.item->>'re_review_item_id')::uuid
      and request.evidence_image_path is not null
  ) as evidence on true;

  return v_result;
end;
$$;

revoke all on function public.submit_correction_request_with_evidence(varchar, jsonb, text)
  from public, anon, authenticated, service_role;
revoke all on function public.get_jury_review_queue_with_evidence()
  from public, anon, authenticated, service_role;
revoke all on function public.get_my_correction_requests()
  from public, anon, authenticated, service_role;

grant execute on function public.submit_correction_request_with_evidence(varchar, jsonb, text)
  to authenticated, service_role;
grant execute on function public.get_jury_review_queue_with_evidence()
  to authenticated, service_role;
grant execute on function public.get_my_correction_requests()
  to authenticated, service_role;

comment on function public.submit_correction_request_with_evidence(varchar, jsonb, text) is
  '登录用户提交单字段正式图鉴报错；强制绑定本人上传的私有游戏内图鉴图片，相同内容与图片重试幂等。';
comment on function public.get_jury_review_queue_with_evidence() is
  '返回当前用户可参与的陪审事项，并附带相关报错的私有游戏内图鉴图片路径。';

commit;
