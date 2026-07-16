begin;

create table public.clothing_contributions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null,
  clothes_id character varying not null,
  user_id uuid,
  source_pending_id bigint not null,
  contribution_type text not null,
  contribution_rank smallint not null,
  source_created_at timestamptz not null,
  created_at timestamptz not null default now(),

  constraint clothing_contributions_clothes_id_fkey
    foreign key (clothes_id)
    references public.clothes (id)
    on delete restrict,
  constraint clothing_contributions_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete set null,
  constraint clothing_contributions_source_pending_id_fkey
    foreign key (source_pending_id)
    references public.pending_clothes (id)
    on delete restrict,
  constraint clothing_contributions_type_check
    check (
      contribution_type in (
        'auto_entry',
        'admin_arbitration',
        'existing_field_completion'
      )
    ),
  constraint clothing_contributions_rank_check
    check (contribution_rank between 1 and 5),
  constraint clothing_contributions_source_pending_id_key
    unique (source_pending_id),
  constraint clothing_contributions_event_rank_key
    unique (event_id, contribution_rank),
  constraint clothing_contributions_event_user_key
    unique (event_id, user_id)
);

create unique index clothing_contributions_initial_reward_key
  on public.clothing_contributions (clothes_id, user_id)
  where user_id is not null
    and contribution_type in ('auto_entry', 'admin_arbitration');

create index clothing_contributions_clothes_id_idx
  on public.clothing_contributions (clothes_id);

create index clothing_contributions_user_id_idx
  on public.clothing_contributions (user_id);

create table public.points_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid,
  delta integer not null,
  status text not null default 'awarded',
  source_type text not null,
  source_id uuid,
  reversal_of uuid,
  occurred_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  constraint points_ledger_user_id_fkey
    foreign key (user_id)
    references auth.users (id)
    on delete set null,
  constraint points_ledger_source_id_fkey
    foreign key (source_id)
    references public.clothing_contributions (id)
    on delete restrict,
  constraint points_ledger_reversal_of_fkey
    foreign key (reversal_of)
    references public.points_ledger (id)
    on delete restrict,
  constraint points_ledger_delta_check
    check (delta <> 0),
  constraint points_ledger_status_check
    check (status = 'awarded'),
  constraint points_ledger_source_type_check
    check (source_type in ('clothing_contribution', 'reversal')),
  constraint points_ledger_entry_shape_check
    check (
      (
        source_type = 'clothing_contribution'
        and source_id is not null
        and reversal_of is null
        and delta > 0
      )
      or
      (
        source_type = 'reversal'
        and source_id is null
        and reversal_of is not null
        and delta < 0
      )
    )
);

create unique index points_ledger_source_id_key
  on public.points_ledger (source_id)
  where source_id is not null;

create unique index points_ledger_reversal_of_key
  on public.points_ledger (reversal_of)
  where reversal_of is not null;

create index points_ledger_user_occurred_at_idx
  on public.points_ledger (user_id, occurred_at desc);

alter table public.clothing_contributions enable row level security;
alter table public.points_ledger enable row level security;

revoke all on table public.clothing_contributions
  from public, anon, authenticated, service_role;
revoke all on table public.points_ledger
  from public, anon, authenticated, service_role;

grant select, insert on table public.clothing_contributions to service_role;
grant select, insert on table public.points_ledger to service_role;

commit;
