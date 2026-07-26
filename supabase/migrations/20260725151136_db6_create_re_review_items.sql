begin;

create table public.re_review_items (
  id uuid primary key default gen_random_uuid(),
  reason text not null,
  status text not null default 'pending',
  source_pending_id bigint,
  clothes_id character varying,
  payload jsonb not null,
  submitted_by uuid,
  resolved_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz,

  constraint re_review_items_reason_check
    check (
      reason in (
        'missing_suit',
        'field_conflict',
        'field_missing',
        'correction'
      )
    ),
  constraint re_review_items_status_check
    check (
      status in (
        'pending',
        'voting',
        'approved',
        'rejected',
        'failed'
      )
    ),
  constraint re_review_items_payload_object_check
    check (
      jsonb_typeof(payload) = 'object'
      and payload <> '{}'::jsonb
    ),
  constraint re_review_items_source_check
    check (
      source_pending_id is not null
      or clothes_id is not null
    ),
  constraint re_review_items_reason_source_check
    check (
      (reason = 'missing_suit' and clothes_id is not null)
      or
      (
        reason in ('field_conflict', 'field_missing')
        and source_pending_id is not null
      )
      or
      (reason = 'correction' and clothes_id is not null)
    ),
  constraint re_review_items_source_pending_id_fkey
    foreign key (source_pending_id)
    references public.pending_clothes (id)
    on delete restrict,
  constraint re_review_items_clothes_id_fkey
    foreign key (clothes_id)
    references public.clothes (id)
    on delete restrict,
  constraint re_review_items_submitted_by_fkey
    foreign key (submitted_by)
    references auth.users (id)
    on delete set null,
  constraint re_review_items_resolved_by_fkey
    foreign key (resolved_by)
    references auth.users (id)
    on delete set null
);

create table public.re_review_item_sources (
  re_review_item_id uuid not null,
  source_pending_id bigint not null,
  source_user_id uuid,
  created_at timestamptz not null default now(),

  constraint re_review_item_sources_pkey
    primary key (re_review_item_id, source_pending_id),
  constraint re_review_item_sources_item_id_fkey
    foreign key (re_review_item_id)
    references public.re_review_items (id)
    on delete restrict,
  constraint re_review_item_sources_pending_id_fkey
    foreign key (source_pending_id)
    references public.pending_clothes (id)
    on delete restrict,
  constraint re_review_item_sources_user_id_fkey
    foreign key (source_user_id)
    references auth.users (id)
    on delete set null
);

create table public.re_review_candidates (
  id uuid primary key default gen_random_uuid(),
  re_review_item_id uuid not null,
  payload jsonb not null,
  submitted_by uuid,
  created_at timestamptz not null default now(),

  constraint re_review_candidates_item_id_fkey
    foreign key (re_review_item_id)
    references public.re_review_items (id)
    on delete restrict,
  constraint re_review_candidates_submitted_by_fkey
    foreign key (submitted_by)
    references auth.users (id)
    on delete set null,
  constraint re_review_candidates_payload_object_check
    check (
      jsonb_typeof(payload) = 'object'
      and payload <> '{}'::jsonb
    )
);

create unique index re_review_items_active_missing_suit_key
  on public.re_review_items (clothes_id)
  where reason = 'missing_suit'
    and status in ('pending', 'voting', 'failed');

create unique index re_review_items_active_pending_reason_key
  on public.re_review_items (source_pending_id, reason)
  where source_pending_id is not null
    and status in ('pending', 'voting', 'failed');

create index re_review_items_status_created_at_idx
  on public.re_review_items (status, created_at);

create index re_review_items_source_pending_id_idx
  on public.re_review_items (source_pending_id)
  where source_pending_id is not null;

create index re_review_items_clothes_id_idx
  on public.re_review_items (clothes_id)
  where clothes_id is not null;

create index re_review_items_submitted_by_idx
  on public.re_review_items (submitted_by)
  where submitted_by is not null;

create index re_review_items_resolved_by_idx
  on public.re_review_items (resolved_by)
  where resolved_by is not null;

create index re_review_item_sources_pending_id_idx
  on public.re_review_item_sources (source_pending_id);

create index re_review_item_sources_user_id_idx
  on public.re_review_item_sources (source_user_id, re_review_item_id)
  where source_user_id is not null;

create unique index re_review_candidates_item_key
  on public.re_review_candidates (re_review_item_id);

create index re_review_candidates_submitted_by_idx
  on public.re_review_candidates (submitted_by)
  where submitted_by is not null;

alter table public.re_review_items enable row level security;
alter table public.re_review_item_sources enable row level security;
alter table public.re_review_candidates enable row level security;

create policy "登录用户可查看未参与的重审项"
on public.re_review_items
for select
to authenticated
using (
  (select auth.uid()) is not null
  and submitted_by is distinct from (select auth.uid())
  and not exists (
    select 1
    from public.pending_clothes as primary_source
    where primary_source.id = re_review_items.source_pending_id
      and primary_source.submitted_by = (select auth.uid())
  )
  and not exists (
    select 1
    from public.re_review_item_sources as source
    where source.re_review_item_id = re_review_items.id
      and source.source_user_id = (select auth.uid())
  )
);

create policy "登录用户只能查看自己的重审来源标记"
on public.re_review_item_sources
for select
to authenticated
using (
  source_user_id = (select auth.uid())
);

create policy "登录用户可查看未参与重审项的候选修正版"
on public.re_review_candidates
for select
to authenticated
using (
  exists (
    select 1
    from public.re_review_items as item
    where item.id = re_review_candidates.re_review_item_id
  )
);

create policy "登录用户可为未参与重审项提交候选修正版"
on public.re_review_candidates
for insert
to authenticated
with check (
  submitted_by = (select auth.uid())
  and exists (
    select 1
    from public.re_review_items as item
    where item.id = re_review_candidates.re_review_item_id
      and item.status in ('pending', 'failed')
  )
);

revoke all on table public.re_review_items
  from public, anon, authenticated, service_role;
revoke all on table public.re_review_item_sources
  from public, anon, authenticated, service_role;
revoke all on table public.re_review_candidates
  from public, anon, authenticated, service_role;

grant select, insert on table public.re_review_items
  to service_role;

grant update (status, resolved_by, updated_at, resolved_at)
  on table public.re_review_items
  to service_role;

grant select, insert on table public.re_review_item_sources
  to service_role;

grant select, insert on table public.re_review_candidates
  to service_role;

grant select on table public.re_review_items
  to authenticated;

grant select on table public.re_review_item_sources
  to authenticated;

grant select, insert on table public.re_review_candidates
  to authenticated;

comment on table public.re_review_items is
  'DB-6 重审池：追踪缺套装、字段冲突、字段缺失和报错修正；社区参与、系统处理、管理员兜底。';

comment on column public.re_review_items.payload is
  '进入重审时的数据快照；必须是 JSON 对象，不替代来源 pending 或正式服装关联。';

comment on table public.re_review_item_sources is
  '重审项的全部 pending 来源；用于审计和数据库层防止用户参与自己提交的数据。';

comment on table public.re_review_candidates is
  '登录用户为未参与的重审项提交的候选修正版；每个重审项只允许一份且不可修改或删除。';

commit;
