# Branch and Environment Policy

## Purpose

This document restores the intended branch and environment governance before any further business feature work.

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
