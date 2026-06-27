-- Development-only test data.
-- Run this only in the Supabase dev project SQL Editor:
-- tfwejruvdahonacyldrg / nikki-calculator-dev
--
-- Do not run this in production.

insert into public.suits (name, description, source)
values
  ('测试套装-A', 'development test suit', 'dev_seed'),
  ('测试套装-B', 'development test suit', 'dev_seed'),
  ('星之海-测试', 'development test suit', 'dev_seed')
on conflict (name) do nothing;

