# Supabase Review Setup

This repo keeps database review context in source control so code and schema can be checked together.

## One-time local setup

1. Install the Supabase CLI.

   ```powershell
   npm install -g supabase
   ```

2. Log in and link the development project.

   ```powershell
   supabase login
   supabase link --project-ref tfwejruvdahonacyldrg
   ```

3. Create `.env.local` from `.env.example` and fill in the values from Supabase Project Settings.

   ```powershell
   Copy-Item .env.example .env.local
   ```

## Keep review files fresh

Before running database commands, confirm the linked project:

```powershell
supabase status
```

Default local development should use `nikki-calculator-dev`:

```text
Project ref: tfwejruvdahonacyldrg
```

Production ref `fopyjewbsvusftpqbtml` must only be linked for approved production operations.

Run these after changing tables, policies, functions, triggers, or storage rules:

```powershell
npm run db:dump
npm run db:types
```

`npm run db:types` defaults to the development project. Use `npm run db:types:prod` only for approved
production operations. `npm run db:types` can run against the hosted project without Docker and is enough for checking
table/column/type mismatches.

`npm run db:dump` uses the currently linked Supabase project. Always run `supabase status` before
dumping. `npm run db:dump` may require Docker Desktop on Windows because the
Supabase CLI runs database tooling from a Postgres image. If Docker is not running, `schema.sql`
can be created as an empty file; do not commit a zero-byte dump.

To fix `db:dump` on Windows:

```powershell
docker version
# Start Docker Desktop and wait until the engine is running, then retry:
npm run db:dump
```

If Docker is not available, export SQL from the Supabase dashboard SQL/schema tools and save it as
`supabase/schema.sql`.

Commit these generated files when they change:

```text
supabase/migrations/
supabase/schema.sql
src/types/supabase.ts
docs/database/schema.md
```

## What Codex can review from these files

- Frontend Supabase calls vs real table/column names
- RLS policy gaps
- Missing indexes and uniqueness constraints
- Business-rule drift between `docs/requirements/需求文档.md`, Vue code, and SQL
- Type mismatches before runtime

Do not commit `.env.local`, service-role keys, access tokens, or real user data.
