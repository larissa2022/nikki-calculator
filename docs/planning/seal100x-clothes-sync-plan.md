# seal100x Clothes Data Sync Plan

## 1. Status

This is a planning document for a future clothes data synchronization task. It is based on the PR #49 production SELECT-only audit result.

Current authorization status:

- No database write is authorized.
- No production apply is authorized.
- No migration is authorized.
- No Supabase write operation is authorized.
- No Vercel operation is authorized.
- No business code change is authorized.
- Any actual data synchronization must be handled as a separate `database/data-sync` task.

## 2. Scope

This plan covers:

- `source-only` clothes records.
- `changed` clothes records.
- `DB-only` clothes records.
- `tags` differences.
- `suit_id` and `temp_suit_name` mapping questions.
- Validation strategy.
- Backup and rollback requirements.
- Execution gates before any future data write.

This plan does not cover:

- Supabase advisor security remediation.
- Schema or migration changes.
- Vercel or CI automation rollout.
- Production data write execution.
- Business code changes.

## 3. Audit Inputs

Source PR:

- PR: #49, `工具：支持 seal100x 生产只读审计模式`.
- Merge commit: `c634ce24480f7c171de824d5883895a3c4628a98`.
- Audit mode: production SELECT-only / dry-run read-only.
- Production project ref: `fopyjewbsvusftpqbtml`.
- Target table: production `clothes`.
- Source: seal100x / upstream expanded clothes data.
- JSON report path used during audit: `tmp/seal100x-production-clothes-diff.json`.
- The JSON report was not committed; PR #49 body is the current committed audit summary source.

Production audit summary from PR #49:

- Production clothes total rows: `35241`.
- Upstream expanded count: `36811`.
- `updated_at` exists: `false`.
- Actual clothes fields: `id, name, category, game_id, stars, tags, scores, suit_id, temp_suit_name, created_at`.

Exact key diff statistics:

| Class | Count |
| --- | ---: |
| source-only | 15472 |
| changed | 21324 |
| DB-only | 13902 |
| source duplicate keys | 0 |
| DB duplicate keys | 0 |
| total conflict keys | 0 |

Normalized key diff statistics:

| Class | Count |
| --- | ---: |
| source-only | 1577 |
| changed | 35216 |
| DB-only | 7 |
| source duplicate keys | 0 |
| DB duplicate keys | 0 |
| total conflict keys | 0 |

Known sample patterns from PR #49:

- Exact `source-only` samples are mainly clothes present in source but not production DB.
- Exact `changed` samples listed in PR #49 have differences in `tags`.
- Exact `DB-only` samples are production DB rows not found in source by exact key.
- Conflict samples: none.

## 4. Proposed Sync Classification

### 4.1 Source-only

Meaning: rows exist in seal100x / upstream source data, but do not exist in production DB under the audit key.

Initial planning direction:

- Treat as candidate inserts only.
- Do not insert automatically from this planning document.
- Build a finalized sync set before any write task.

Unconfirmed strategy:

- Whether all source-only records should be inserted.
- Whether inserts should be split by category, suit, batch size, or risk level.
- Whether high-risk categories need manual review before insertion.
- Whether a development dry-run and sample write must precede any production write.

### 4.2 Changed

Meaning: rows exist in both source and production DB, but at least one audited field differs.

Initial planning direction:

- Treat as candidate updates only.
- Split differences by field before deciding update policy.
- Do not update all changed rows as a single undifferentiated batch.

Field groups:

- Safer metadata candidates: fields whose source of truth is confirmed and whose update does not affect identity or suit mapping.
- `tags`: not safe for default bulk overwrite.
- `suit_id` / `temp_suit_name`: not safe for default bulk overwrite until mapping is confirmed.
- Identity / key fields: require separate audit and approval.

Important constraint:

- PR #49 changed samples are `tags` differences, but this does not by itself authorize bulk `tags` overwrite.

### 4.3 DB-only

Meaning: rows exist in production DB, but do not exist in seal100x / upstream source data under the audit key.

Initial planning direction:

- Default to keep and manually review.
- Do not delete automatically.
- Do not archive, mark, or clean up without a separate confirmed strategy.

Unconfirmed strategy:

- Whether DB-only records are legacy valid rows, local-only rows, source gaps, category/key normalization issues, or cleanup candidates.
- Whether they should be preserved, marked, manually reviewed, or later cleaned.

## 5. Field-level Strategy

### 5.1 tags

Current status:

- `tags` bulk overwrite is not confirmed.
- PR #49 changed samples show `tags` differences, but sample evidence is not an execution decision.

Risk:

- Bulk overwrite may affect filtering, display behavior, classification support, and user-facing search logic.
- If local tags contain corrections or app-specific semantics, upstream overwrite may regress behavior.

Default strategy:

- Do not auto-overwrite `tags`.
- Generate a tags diff review first.
- Confirm whether source or production DB is the source of truth for each tags class.

### 5.2 suit_id and temp_suit_name

Current status:

- Mapping strategy is not confirmed.
- Source-of-truth relationship between upstream suit data and local `suit_id` / `temp_suit_name` is not confirmed in this plan.

Risk:

- Incorrect suit mapping can break suit grouping, outfit attribution, and future data reconciliation.
- `temp_suit_name` may represent temporary or local fallback semantics rather than final upstream suit identity.

Default strategy:

- Do not auto-overwrite `suit_id` or `temp_suit_name`.
- Generate a mapping review before any update.
- Confirm how upstream suit identity maps to local fields.

### 5.3 Identity and key fields

Identity-sensitive fields include at least:

- `id`
- `game_id`
- `category`
- any compound key used by the audit or app lookup path

Default strategy:

- Do not modify identity or key fields casually.
- If identity/key changes are needed, split them into a separate audit and approval step.
- Confirm duplicate detection and rollback before any identity/key write.

## 6. Execution Gates Before Any database/data-sync Task

Before any real `database/data-sync` task, the following must be confirmed:

1. Whether to generate a finalized sync set from the production audit result.
2. Whether source-only rows are inserted all at once or by category / suit / batch.
3. Which changed fields are allowed to update.
4. Whether `tags` can be bulk-overwritten.
5. Whether DB-only rows are preserved, marked, manually reviewed, or later cleaned.
6. How `suit_id` and `temp_suit_name` map to upstream suit data.
7. Whether to build and run a development dry-run / sample-write tool first.
8. Production backup method.
9. Production rollback method.
10. Production validation checklist.
11. Explicit approver for production write.
12. Whether to create a separate CI PR. First version recommendation: `workflow_dispatch` + development only.

## 7. Recommended Next Task Split

Recommended follow-up tasks:

1. `database/data-sync` planning confirmation.
2. Development dry-run tooling.
3. Development sample write.
4. Production backup and read-only preflight.
5. Production apply, only after explicit approval.
6. Optional CI PR using `workflow_dispatch` and development-only scope first.
7. Separate `database/security` task for Supabase advisor risks.

## 8. Validation Plan

### 8.1 Read-only validation

Before any write task:

- Re-run count comparison.
- Recompute source-only / changed / DB-only counts.
- Confirm duplicate key count remains `0` for selected keys.
- Review category distribution.
- Review tags diff summary.
- Review suit mapping consistency.
- Generate sample rows for each planned operation class.

### 8.2 Development validation

Before production write:

- Run dry-run apply against development.
- Run a small sample write against development if approved.
- Verify generated row counts and field diffs.
- Rehearse rollback on the development sample.
- Perform UI smoke check if affected queries or display paths depend on changed data.

### 8.3 Production validation

Only after explicit production approval:

- Confirm backup exists before apply.
- Confirm production project ref before any command.
- Apply only the approved sync set.
- Record inserted row list.
- Record updated rows with before/after snapshots.
- Run post-apply diff.
- Verify random samples from source-only, changed, and DB-only classes.
- Confirm rollback readiness after apply.

## 9. Rollback Plan

### 9.1 Rollback for this docs-only PR

If this planning document is wrong or premature:

- Before merge: close the PR or push a correction commit.
- After merge to `develop`: open a revert PR that removes or corrects `docs/planning/seal100x-clothes-sync-plan.md`.

### 9.2 Required rollback design for future database/data-sync

A future data-sync task must define rollback before any write:

- Backup before write.
- Inserted rows list.
- Updated rows before/after snapshot.
- Row-level update log.
- Generated inverse patch if applicable.
- Separate rollback validation.
- No destructive DB-only cleanup without separate approval.

## 10. Open Questions

1. Should a finalized sync set be generated from the PR #49 production audit result?
2. Should source-only rows be inserted all at once or split by category / suit / batch?
3. Which changed fields are allowed to update?
4. Are `tags` differences allowed to be bulk-overwritten?
5. Should DB-only rows be preserved, marked, manually reviewed, or later cleaned?
6. What is the approved mapping strategy for `suit_id` and `temp_suit_name`?
7. Should development dry-run / sample-write tooling be built before any production plan?
8. What backup, rollback, and validation method is required for production write?
9. Should CI be added in a separate PR, starting with `workflow_dispatch` + development only?
10. Should Supabase advisor security risks be handled as a separate `database/security` task before or after clothes sync planning?
