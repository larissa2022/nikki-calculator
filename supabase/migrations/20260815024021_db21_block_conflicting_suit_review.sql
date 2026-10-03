begin;

-- DB-21 forward patch: conflicting approval/rejection is first-writer-wins.
-- Controlled quick creation remains available only when no review history exists.
create or replace function public.review_pending_suit(
  p_name text,
  p_decision text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_name text := pg_catalog.btrim(coalesce(p_name, ''));
  v_decision text := pg_catalog.lower(pg_catalog.btrim(coalesce(p_decision, '')));
  v_suit_id uuid;
  v_pending_count bigint := 0;
  v_approved_count bigint := 0;
  v_rejected_count bigint := 0;
  v_processed_count bigint := 0;
  v_suit_existed boolean := false;
begin
  if coalesce((select auth.jwt())->>'role', '') not in ('authenticated', 'service_role')
    or coalesce((select auth.jwt())->>'is_anonymous', 'false') = 'true'
    or v_actor is null
    or not public.is_super_admin() then
    raise exception using errcode = '42501', message = '仅超级管理员可审核套装';
  end if;
  if v_name = '' then
    raise exception using errcode = '22023', message = '套装名称不能为空';
  end if;
  if v_decision not in ('approve', 'reject', 'create') then
    raise exception using errcode = '22023', message = '套装操作必须是 approve、reject 或 create';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('DB21:suit:' || v_name, 0)
  );

  select
    pg_catalog.count(*) filter (where pending.status = 'pending'),
    pg_catalog.count(*) filter (where pending.status = 'approved'),
    pg_catalog.count(*) filter (where pending.status = 'rejected')
  into v_pending_count, v_approved_count, v_rejected_count
  from public.pending_suits as pending
  where pending.name = v_name;

  select suit.id
  into v_suit_id
  from public.suits as suit
  where suit.name = v_name;
  v_suit_existed := found;

  if v_decision in ('approve', 'create') then
    if v_pending_count = 0 then
      if v_approved_count > 0 then
        if v_suit_id is null then
          raise exception using errcode = '55000', message = '套装批准状态与正式库不一致，请停止操作并检查数据';
        end if;
        return pg_catalog.jsonb_build_object(
          'name', v_name,
          'decision', 'approved',
          'suit_id', v_suit_id,
          'processed_count', 0,
          'idempotent', true
        );
      end if;
      if v_rejected_count > 0 then
        raise exception using errcode = '40001', message = '该名称已有驳回记录，请先由用户重新提交后再审核';
      end if;
      if v_decision = 'approve' then
        raise exception using errcode = 'P0002', message = '没有可批准的待审核套装申请';
      end if;
    end if;

    if v_suit_id is null then
      insert into public.suits (name)
      values (v_name)
      on conflict (name) do nothing
      returning id into v_suit_id;

      if v_suit_id is null then
        select suit.id into strict v_suit_id
        from public.suits as suit
        where suit.name = v_name;
      end if;
    end if;

    update public.pending_suits
    set status = 'approved'
    where name = v_name
      and status = 'pending';
    get diagnostics v_processed_count = row_count;

    return pg_catalog.jsonb_build_object(
      'name', v_name,
      'decision', 'approved',
      'suit_id', v_suit_id,
      'processed_count', v_processed_count,
      'idempotent', v_suit_existed and v_processed_count = 0
    );
  end if;

  update public.pending_suits
  set status = 'rejected'
  where name = v_name
    and status = 'pending';
  get diagnostics v_processed_count = row_count;

  if v_processed_count = 0 then
    if v_rejected_count > 0 and v_approved_count = 0 then
      return pg_catalog.jsonb_build_object(
        'name', v_name,
        'decision', 'rejected',
        'suit_id', null,
        'processed_count', 0,
        'idempotent', true
      );
    end if;
    if v_approved_count > 0 then
      raise exception using errcode = '40001', message = '该套装申请已批准，不能改为驳回';
    end if;
    raise exception using errcode = 'P0002', message = '没有可驳回的待审核套装申请';
  end if;

  return pg_catalog.jsonb_build_object(
    'name', v_name,
    'decision', 'rejected',
    'suit_id', null,
    'processed_count', v_processed_count,
    'idempotent', false
  );
end;
$$;

revoke all on function public.review_pending_suit(text, text)
  from public, anon, authenticated, service_role;
grant execute on function public.review_pending_suit(text, text)
  to authenticated, service_role;

comment on function public.review_pending_suit(text, text) is
  'DB-21 atomic super-admin suit review and controlled quick creation; conflicting decisions are first-writer-wins and retries are idempotent.';

commit;
