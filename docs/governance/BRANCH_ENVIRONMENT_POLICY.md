# Branch and Environment Policy

## Purpose

This document restores the intended branch and environment governance before any further business feature work.

This file defines branch and environment mapping. Detailed operating procedures live in [`../ai/WORKFLOWS.md`](../ai/WORKFLOWS.md). If workflow instructions conflict with this file or [`../ai/RULES.md`](../ai/RULES.md), the branch/environment mapping and production gates in this file and `RULES.md` take precedence.

## Branch Mapping

| Branch | Environment | Purpose |
| --- | --- | --- |
| `main` | production | Stable production code only |
| `develop` | development / preview | Integration branch for verified development work |
| `feature/*` | preview / development | Feature work branched from `develop` |
| `fix/*` | preview / development | Non-urgent fixes branched from `develop` |
| `docs/*` | preview / development | Documentation work branched from `develop` |
| `hotfix/*` | production hotfix only | Emergency fixes may target `main` with explicit approval |

## Required Flow

1. Create `feature/*`, `fix/*`, and `docs/*` branches from `develop` by default.
2. Merge feature, fix, and docs branches back into `develop`.
3. Validate `develop` through development Supabase and Vercel preview.
4. Promote only verified `develop` content to `main` through a PR.
5. Keep `main` mapped only to production.

## Standard Release Flow

1. Start feature, fix, and docs work from `develop`; keep incomplete or unaccepted features on their task branches.
2. Merge completed and accepted work back into `develop`, then validate `develop` in the development / preview environment.
3. Trigger a non-urgent production release when a major module or complete requirement has been accepted, not on a fixed weekly schedule, elapsed-day threshold, or accumulated PR count.
4. Before creating a `develop -> main` release PR, run a full read-only diff audit and classify changes as documentation, business code, database / Supabase, or configuration / build. List accepted small fixes and optimizations that will ride with the milestone.
5. Present the requirement milestone, bundled small changes, validation evidence, production impact, and rollback in a release decision card. Create one release PR only after the owner confirms this release.
6. If incomplete or unaccepted work is already present in `develop`, stop the release and isolate it before proceeding.
7. Keep high-risk implementation types separated according to `RULES.md`; directly supporting task, defect, acceptance, and database records may travel with their primary PR.
8. Apply database migrations to development first; if an already-applied migration needs correction, create a new patch migration.
9. Before merging to `main`, confirm production environment bindings and rollback steps for the frontend deployment, database migration, and affected data, then obtain separate explicit merge approval.
10. Use an explicitly approved `hotfix/*` flow for urgent production defects; do not bundle non-urgent changes into the hotfix.

## GitHub CLI Checks

- GitHub CLI (`gh`) is the preferred local tool for confirming PR state, mergeability, changed files, and workflow status.
- Typical read-only checks include `gh pr view`, `gh pr diff`, `gh pr list`, `gh run list`, and `gh run view`.
- `gh` does not change the branch and environment mapping: `main` still maps only to production, and `develop` still maps only to development / preview.
- Before any `develop -> main` promotion, the read-only diff audit is still required.
- `gh` output must be judged together with `git diff` and PR changed files. Do not merge based on one tool alone.
- If `gh` is unavailable, fall back to the GitHub web UI or the ChatGPT GitHub connector for confirmation.
- `gh pr merge` is a write action and requires explicit user approval, especially for production-related PRs.
- Do not record `gh auth` tokens, device codes, authorization URLs, or keyring details in repository files, logs, or commits.
- See [`../ai/WORKFLOWS.md`](../ai/WORKFLOWS.md) for the full PR and workflow check procedure.

## Prohibited Flow

- Do not merge `feature/*`, `fix/*`, or `docs/*` directly into `main`.
- Do not use production Supabase for development validation.
- Do not map Vercel production to any branch other than `main`.
- Do not treat Vercel preview as production proof.
- Do not run database commands before confirming the Supabase project ref.

## Vercel Mapping

- Vercel production must correspond to `main`.
- Vercel preview / development must correspond to `develop` or short-lived feature branches.
- If a preview branch must test production-like data, document the reason and get explicit user approval first.

## Supabase Mapping

- Supabase production must correspond to `main` production operation only.
- Supabase development must correspond to `develop`, `feature/*`, `fix/*`, and `docs/*` validation.
- Database-related tasks must confirm the Supabase project ref before any command that can read or write linked project state.
- Production database work requires prior backup, verified development migration, rollback notes, and explicit user approval.

## Current Governance Recommendation

- Pause business feature development until `main`, `develop`, Vercel, and Supabase relationships are confirmed.
- Treat open PRs and branches created before this policy as legacy state requiring manual triage.
- Prefer merging documentation governance into `develop` first, then promote to `main` after review.
