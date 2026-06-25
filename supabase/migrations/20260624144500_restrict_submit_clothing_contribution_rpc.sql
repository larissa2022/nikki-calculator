revoke all on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) from public;
revoke all on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) from anon;
grant execute on function public.submit_clothing_contribution(text, text, text, integer, jsonb, uuid, text, text) to authenticated;
