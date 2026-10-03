begin;

-- DB-21 forward patch: cover the ownership foreign key used by the new RLS read path.
create index if not exists idx_pending_suits_submitted_by
  on public.pending_suits (submitted_by);

commit;
