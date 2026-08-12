begin;

alter table public.points_ledger
  add column reversal_correction_request_id uuid;

alter table public.points_ledger
  add constraint points_ledger_reversal_correction_request_id_fkey
    foreign key (reversal_correction_request_id)
    references public.correction_requests (id)
    on delete restrict,
  add constraint points_ledger_reversal_correction_shape_check
    check (
      reversal_correction_request_id is null
      or (
        source_type = 'reversal'
        and reversal_of is not null
        and delta < 0
      )
    );

create index points_ledger_reversal_correction_request_id_idx
  on public.points_ledger (reversal_correction_request_id)
  where reversal_correction_request_id is not null;

comment on column public.points_ledger.reversal_correction_request_id is
  '触发完整积分扣回的已通过报错；原正向流水由 reversal_of 保留，等级奖励扣回沿用同一报错来源。';

create or replace function private_db2.append_level_bonus_or_reversal()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_bonus public.points_ledger%rowtype;
  v_bonus_delta integer;
begin
  if new.source_type in ('clothing_contribution', 're_review_candidate', 'correction_request') then
    v_bonus_delta := private_db2.level_bonus_for_level(new.level_snapshot);
    if v_bonus_delta > 0 then
      insert into public.points_ledger (
        user_id, delta, status, source_type, bonus_of, level_snapshot, occurred_at
      ) values (
        new.user_id, v_bonus_delta, 'awarded', 'level_bonus', new.id,
        new.level_snapshot, new.occurred_at
      )
      on conflict (bonus_of) where bonus_of is not null do nothing;
    end if;
  elsif new.source_type = 'reversal' then
    select bonus.* into v_bonus
    from public.points_ledger as bonus
    where bonus.bonus_of = new.reversal_of
      and bonus.source_type = 'level_bonus';

    if found then
      insert into public.points_ledger (
        user_id,
        delta,
        status,
        source_type,
        reversal_of,
        reversal_correction_request_id,
        occurred_at
      ) values (
        v_bonus.user_id,
        -v_bonus.delta,
        'awarded',
        'reversal',
        v_bonus.id,
        new.reversal_correction_request_id,
        new.occurred_at
      )
      on conflict (reversal_of) where reversal_of is not null do nothing;
    end if;
  end if;

  return null;
end;
$$;

revoke all on function private_db2.append_level_bonus_or_reversal()
  from public, anon, authenticated, service_role;

create function private_db2.append_overturned_contribution_reversals()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_accepted_value jsonb;
  v_old_value jsonb;
begin
  if new.status <> 'approved'
    or new.status is not distinct from old.status
    or new.accepted_patch is null then
    return new;
  end if;

  v_old_value := public.correction_field_value(new.clothes_snapshot, new.field_key);
  v_accepted_value := new.accepted_patch->new.field_key;

  -- 空字段补全不推翻原贡献事实；值未变化也不得产生扣回。
  if public.correction_field_is_directly_completable(
      new.clothes_snapshot,
      new.field_key
    )
    or v_accepted_value is null
    or v_accepted_value is not distinct from v_old_value then
    return new;
  end if;

  insert into public.points_ledger (
    user_id,
    delta,
    status,
    source_type,
    reversal_of,
    reversal_correction_request_id,
    occurred_at
  )
  select
    original.user_id,
    -original.delta,
    'awarded',
    'reversal',
    original.id,
    new.id,
    pg_catalog.now()
  from public.clothing_contributions as contribution
  join public.points_ledger as original
    on original.source_id = contribution.id
    and original.source_type = 'clothing_contribution'
    and original.status = 'awarded'
    and original.delta > 0
    and original.reversal_of is null
  where contribution.clothes_id = new.clothes_id
    and public.correction_field_value(
      public.jury_pending_payload(contribution.source_pending_id),
      new.field_key
    ) is not distinct from v_old_value
  on conflict (reversal_of)
    where reversal_of is not null do nothing;

  return new;
end;
$$;

revoke all on function private_db2.append_overturned_contribution_reversals()
  from public, anon, authenticated, service_role;

create trigger correction_requests_reverse_overturned_points
after update of status on public.correction_requests
for each row
when (
  new.status = 'approved'
  and old.status is distinct from new.status
)
execute function private_db2.append_overturned_contribution_reversals();

comment on function private_db2.append_overturned_contribution_reversals() is
  '报错正式通过且替换非空旧值时，只完整扣回来源 pending 该字段与旧值一致的原贡献奖励；空字段补全、无关贡献和既有历史均不处理。';

commit;
