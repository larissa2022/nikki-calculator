-- DB-0：收紧 pending_clothes 与现有高权限函数的客户端访问面。
-- 本 migration 不修改业务数据，也不接入积分 / 贡献者表。

alter table public.pending_clothes enable row level security;

drop policy if exists "允许认证用户提交完整申请" on public.pending_clothes;
drop policy if exists "认证用户只能提交自己的待审核申请" on public.pending_clothes;
drop policy if exists "认证用户可查看自己的申请及管理员可查看全部" on public.pending_clothes;
drop policy if exists "管理员可更新申请状态" on public.pending_clothes;

create policy "认证用户只能提交自己的待审核申请"
on public.pending_clothes
for insert
to authenticated
with check (
  (select auth.uid()) is not null
  and submitted_by = (select auth.uid())
  and status = 'pending'
);

create policy "认证用户可查看自己的申请及管理员可查看全部"
on public.pending_clothes
for select
to authenticated
using (
  (select auth.uid()) is not null
  and (
    submitted_by = (select auth.uid())
    or (select public.is_admin_or_super_admin())
  )
);

create policy "管理员可更新申请状态"
on public.pending_clothes
for update
to authenticated
using ((select public.is_admin_or_super_admin()))
with check ((select public.is_admin_or_super_admin()));

-- 匿名请求无表级访问；登录用户只能读取、提交并修改 status。
revoke all on table public.pending_clothes from anon;
revoke all on table public.pending_clothes from authenticated;
grant select, insert on table public.pending_clothes to authenticated;
grant update (status) on table public.pending_clothes to authenticated;

revoke all on sequence public.pending_clothes_id_seq from anon;
revoke all on sequence public.pending_clothes_id_seq from authenticated;
grant usage, select on sequence public.pending_clothes_id_seq to authenticated;

create index if not exists idx_pending_clothes_submitted_by
on public.pending_clothes using btree (submitted_by);

-- 对外 RPC：仅登录用户可调用，函数体继续负责本人 / 管理员校验。
revoke all on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text)
from public, anon;
grant execute on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text)
to authenticated, service_role;

revoke all on function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[])
from public, anon;
grant execute on function public.approve_pending_clothes_arbitration(text, text, text, text, integer, jsonb, uuid, text, text, bigint[])
to authenticated, service_role;

revoke all on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[])
from public, anon;
grant execute on function public.complete_existing_clothes_from_pending(text, text, text, text, integer, jsonb, uuid, text, text, bigint[])
to authenticated, service_role;

revoke all on function public.is_admin_or_super_admin() from public, anon;
grant execute on function public.is_admin_or_super_admin() to authenticated, service_role;

revoke all on function public.is_super_admin() from public, anon;
grant execute on function public.is_super_admin() to authenticated, service_role;

revoke all on function public.update_profile_username(text) from public, anon;
grant execute on function public.update_profile_username(text) to authenticated, service_role;

-- 内部函数 / 触发器函数：不允许 anon 或 authenticated 直接执行。
revoke all on function public.add_clothes_to_submitter_wardrobes(uuid[], text)
from public, anon, authenticated;
grant execute on function public.add_clothes_to_submitter_wardrobes(uuid[], text) to service_role;

revoke all on function public.deduct_user_quota(uuid)
from public, anon, authenticated;
grant execute on function public.deduct_user_quota(uuid) to service_role;
alter function public.deduct_user_quota(uuid) set search_path = public;

revoke all on function public.handle_new_user()
from public, anon, authenticated;
grant execute on function public.handle_new_user() to service_role;

revoke all on function public.handle_new_user_quota()
from public, anon, authenticated;
grant execute on function public.handle_new_user_quota() to service_role;
alter function public.handle_new_user_quota() set search_path = public;

revoke all on function public.sync_profile_role_fields()
from public, anon, authenticated;
grant execute on function public.sync_profile_role_fields() to service_role;
