begin;

create schema if not exists private authorization postgres;
revoke all on schema private from public, anon, authenticated, service_role;
grant usage on schema private to authenticated, service_role;

create or replace function private.can_read_correction_evidence(
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

create or replace function private.can_delete_correction_evidence(
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

revoke all on function private.can_read_correction_evidence(text)
  from public, anon, authenticated, service_role;
revoke all on function private.can_delete_correction_evidence(text)
  from public, anon, authenticated, service_role;
grant execute on function private.can_read_correction_evidence(text)
  to authenticated, service_role;
grant execute on function private.can_delete_correction_evidence(text)
  to authenticated, service_role;

drop policy if exists correction_evidence_select_authenticated on storage.objects;
create policy correction_evidence_select_authenticated
on storage.objects
for select
to authenticated
using (
  bucket_id = 'correction-evidence'
  and (
    owner_id = (select auth.uid())::text
    or (select private.can_read_correction_evidence(name))
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
  and (select private.can_delete_correction_evidence(name))
);

revoke execute on function public.submit_correction_request(varchar, text, jsonb)
  from authenticated;
grant execute on function public.submit_correction_request(varchar, text, jsonb)
  to service_role;

drop function public.can_read_correction_evidence(text);
drop function public.can_delete_correction_evidence(text);

comment on function private.can_read_correction_evidence(text) is
  'Storage RLS 内部判断：仅报错提交者或当前可参与该事项的陪审员可读取引用图片。';
comment on function private.can_delete_correction_evidence(text) is
  'Storage RLS 内部判断：仅允许删除尚未绑定报错记录的图片。';

commit;
