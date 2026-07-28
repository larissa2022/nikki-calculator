begin;

revoke all on table public.correction_requests from service_role;
grant select, insert, update on table public.correction_requests to service_role;

commit;
