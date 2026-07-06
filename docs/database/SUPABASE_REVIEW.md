# Supabase Review Setup

This repo keeps database review context in source control so code and schema can be checked together.

## PR #17 database audit note

Audit time: 2026-07-06 23:01 UTC+8.

PR #17, `db-contributions-points-schema`, is a database migration draft for contribution and points schema work. It should not be merged in its current state because the PR base is `main`, while database migrations must be validated through `develop` and the development Supabase project first.

Current recommendation:

- Mark PR #17 as blocked / paused.
- Pause the database feature until Supabase security advisor findings around RLS, grants, and `SECURITY DEFINER` functions are reviewed and addressed.
- If the contribution / points schema continues, retarget to `develop` only as a blocked draft, or close PR #17 and reopen from `develop`.
- Split the work into multiple database PRs instead of one combined migration: duplicate-key precheck and index, base tables, RLS / grants, public views / RPC, write-path RPC integration, and historical backfill.

Required checks before any migration apply:

- Run a development duplicate-key precheck for `clothes(category, game_id)` before adding the partial unique index.
- Verify RLS and table grants for `clothing_contributions` and `points_ledger` with anon, authenticated user, admin, and super admin paths.
- Verify whether `security_invoker` views remain readable when underlying table grants are revoked; the proposed contributor public view / RPC may be unreadable for anon / authenticated users without explicit underlying access.
- Decide whether `source_pending_id` is required in `clothing_contributions`; omitting it weakens traceability, rollback, and dispute handling.
- Prepare rollback notes before development execution.

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
