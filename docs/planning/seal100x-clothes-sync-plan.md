# seal100x Clothes Data Sync Plan

## 1. Status

This is a planning document for the seal100x clothes data synchronization task.

Core task:

- Sync Nikki UP2U3 / 奇迹暖暖 clothing item data from `https://seal100x.github.io/nikkiup2u3/` into Nikki Calculator's database.
- The current upstream implementation target is `https://seal100x.github.io/nikkiup2u3_data/wardrobe.js`, which is the compressed / encoded wardrobe data source used by the existing audit script.
- The primary database target is `public.clothes`.

Current authorization status:

- No database write is authorized.
- No production apply is authorized.
- No migration is authorized.
- No Supabase write operation is authorized.
- No Vercel operation is authorized.
- No business code change is authorized.
- Any actual data synchronization must be handled as a separate `database/data-sync` task.

## 2. Confirmed Source-of-Truth Decision

Confirmed user decision:

- seal100x is the content source of truth for clothing item data.
- If seal100x clothing item data conflicts with existing Nikki Calculator `public.clothes` data, seal100x should win.
- The current database originally came from the same upstream family, but it is now behind game progress and may contain inaccurate player-entered or locally maintained records.

Important boundary:

- seal100x is the clothing item content source of truth.
- seal100x is not automatically the source of truth for database schema, RLS, Supabase policies, Vercel configuration, user wardrobe ownership data, pending review workflow, or local governance documents.
- Schema changes, RLS changes, user data changes, and deployment configuration changes require separate task classification and approval.

## 3. Scope

This plan covers:

- `source-only` clothes records.
- `changed` clothes records.
- `DB-only` clothes records.
- Field mapping from seal100x upstream data into current `public.clothes` fields.
- `tags` differences.
- `scores` differences.
- `stars` differences.
- `name` differences.
- `category` matching / mapping.
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
- User wardrobe ownership migration.
- Pending review workflow redesign.

## 4. Audit Inputs

Source PRs:

- PR #48: added the first seal100x clothes diff read-only audit script.
- PR #49: added explicit production SELECT-only audit mode.
- PR #50: added the initial planning document.

Current audit script:

```text
scripts/audit/seal100x-clothes-diff.mjs
```

Current npm script:

```text
npm run audit:seal100x-clothes
```

Audit mode currently available:

- development read-only audit.
- production SELECT-only audit, requiring explicit `--target production --confirm-production-readonly`.

Production audit source:

- Production project ref: `fopyjewbsvusftpqbtml`.
- Target table: production `clothes`.
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

Initial interpretation:

- The exact key result is too noisy to use directly as an insert/update plan.
- The normalized key result is a better first-pass analysis layer, but it is still not an authorized write set.
- A finalized sync set must be generated before any write task.

## 5. Current Script Capability

The current audit script can:

- Fetch seal100x upstream `wardrobe.js`.
- Expand upstream wardrobe data.
- Normalize upstream rows into mapped fields.
- Read Supabase `public.clothes` using SELECT only.
- Compare source and DB rows using exact key and normalized key.
- Report source-only, changed, DB-only, duplicate, and conflict counts.
- Output JSON under `tmp/` or `.cache/`.
- Refuse obvious service-role keys.
- Refuse development audit against the production project ref.
- Require explicit confirmation for production SELECT-only audit.

The current audit script cannot yet:

- Generate a finalized sync set.
- Apply inserts.
- Apply updates.
- Generate rollback SQL or inverse patches.
- Backup production.
- Validate development sample writes.
- Map suit identity safely into `suit_id` / `temp_suit_name` without additional strategy.
- Decide whether DB-only records should be kept, marked, or removed.

## 6. Proposed Sync Classification

### 6.1 Source-only

Meaning: rows exist in seal100x upstream source data, but do not exist in production DB under the selected matching key.

Initial planning direction:

- Treat as candidate inserts only.
- Do not insert automatically from this planning document.
- Prefer normalized-key analysis before exact-key insertion decisions.
- Build a finalized sync set before any write task.

Unconfirmed strategy:

- Whether all normalized source-only records should be inserted.
- Whether inserts should be split by category, suit, batch size, or risk level.
- Whether high-risk categories need manual review before insertion.
- Whether a development dry-run and sample write must precede any production write.

### 6.2 Changed

Meaning: rows exist in both source and production DB, but at least one audited field differs.

Confirmed principle:

- For clothing item content conflicts, seal100x should win.

Execution constraint:

- Even if seal100x should win, updates must be split by field and validated before writing.
- Do not update all changed rows as a single undifferentiated batch.

Field groups:

- `name`
- `stars`
- `scores`
- `tags`
- mixed field changes
- identity / key fields
- suit mapping fields

Initial planning direction:

- Generate a field-level changed summary first.
- Separate safer content fields from identity-sensitive fields.
- Do not bulk-overwrite `tags`, `suit_id`, or `temp_suit_name` until their mapping strategy is confirmed.

### 6.3 DB-only

Meaning: rows exist in production DB, but do not exist in seal100x upstream source data under the selected matching key.

Initial planning direction:

- Default to keep and manually review.
- Do not delete automatically.
- Do not archive, mark, or clean up without a separate confirmed strategy.

Reason:

- DB-only records may be legacy valid rows, local-only rows, source gaps, category/key normalization issues, or cleanup candidates.
- Destructive operations require separate approval and rollback.

## 7. Field-level Strategy

### 7.1 tags

Confirmed principle:

- If `tags` are clothing item content from seal100x and conflict with stale local values, seal100x is the intended source of truth.

Execution constraint:

- `tags` bulk overwrite is not automatically authorized by this planning document.
- Generate a tags diff review first.
- Confirm whether there are local app-specific tags that must be preserved before bulk apply.

Risk:

- Bulk overwrite may affect filtering, display behavior, classification support, and user-facing search logic.

### 7.2 scores

Confirmed principle:

- Scores derived from seal100x wardrobe grades are clothing item content.
- If score data conflicts with stale local values, seal100x-derived scores are the intended content source.

Execution constraint:

- Confirm that current score conversion matrix is correct for all categories before applying score updates.
- Field-level audit must identify score-only rows and mixed-diff rows separately.

### 7.3 stars and name

Confirmed principle:

- `stars` and `name` are clothing item content fields.
- If they conflict with stale local data, seal100x is the intended source of truth.

Execution constraint:

- Name changes may affect matching, display, and duplicate detection.
- Updates must be generated from a finalized sync set, not from raw exact-key noise.

### 7.4 category

Current status:

- `category` participates in exact key matching.
- normalized key collapses broad categories for comparison.

Unconfirmed strategy:

- Whether `category` should be overwritten to seal100x category values.
- Whether category should remain a matching field only.
- Whether category changes need a separate review because user workflows and short-code input depend on category.

### 7.5 suit_id and temp_suit_name

Current status:

- Mapping strategy is not confirmed.
- seal100x upstream exposes suit context, but the current DB uses `suit_id` and `temp_suit_name`.

Risk:

- Incorrect suit mapping can break suit grouping, outfit attribution, and future data reconciliation.
- `temp_suit_name` may represent temporary or local fallback semantics rather than final upstream suit identity.

Default strategy:

- Do not auto-overwrite `suit_id` or `temp_suit_name`.
- Generate a mapping review before any update.
- Confirm how upstream suit identity maps to local fields.

### 7.6 Identity and key fields

Identity-sensitive fields include at least:

- `id`
- `game_id`
- `category`
- any compound key used by the audit or app lookup path

Default strategy:

- Do not modify identity or key fields casually.
- If identity/key changes are needed, split them into a separate audit and approval step.
- Confirm duplicate detection and rollback before any identity/key write.

## 8. Execution Gates Before Any database/data-sync Task

Before any real `database/data-sync` task, the following must be confirmed:

1. Whether to use normalized key as the main matching basis.
2. Whether to generate a finalized sync set from the production audit result.
3. Whether source-only rows are inserted all at once or by category / suit / batch.
4. Which changed fields are allowed to update.
5. Whether `tags` can be bulk-overwritten.
6. Whether `scores` can be bulk-overwritten.
7. Whether `stars` and `name` can be bulk-overwritten.
8. Whether `category` can be overwritten or only used for matching.
9. Whether DB-only rows are preserved, marked, manually reviewed, or later cleaned.
10. How `suit_id` and `temp_suit_name` map to upstream suit data.
11. Whether to build and run a development dry-run / sample-write tool first.
12. Production backup method.
13. Production rollback method.
14. Production validation checklist.
15. Explicit approver for production write.
16. Whether to create a separate CI PR. First version recommendation: `workflow_dispatch` + development only.

## 9. Responsibility Split

### 9.1 User

The user is responsible for:

- Final product judgment.
- Final sync strategy decisions.
- Approval for development write.
- Approval for production write.
- Approval for merge operations.
- Approval for `main`, production, Supabase write, Vercel write, env, migration, or destructive operations.

### 9.2 ChatGPT

ChatGPT is responsible for:

- Reading and aligning governance documents.
- Directly completing docs-only tasks through the GitHub connector.
- Triage and read-only review across GitHub / Vercel / Supabase.
- Separating facts, decisions, preferences, and open questions.
- Classifying tasks as docs / business / database / config / release / incident.
- Producing Codex-ready instructions for non-doc execution tasks.
- Reviewing PR scope and rollback.

ChatGPT must not:

- Approve formal Rules.
- Execute production writes.
- Execute Supabase writes without explicit approval.
- Execute Vercel writes without explicit approval.
- Auto-merge PRs.
- Turn unconfirmed strategy into final decisions.

### 9.3 Codex

Codex is responsible for:

- Running local commands.
- Running the existing audit script.
- Modifying scripts or code when authorized.
- Generating finalized sync set artifacts.
- Building development-only dry-run / sample apply tooling.
- Running tests / build.
- Committing, pushing, and opening PRs for non-doc execution tasks when authorized.

Codex must not:

- Expand scope on its own.
- Write production without explicit approval.
- Commit tmp JSON reports, secrets, keys, tokens, authorization links, or keyring details.
- Mix data-sync work with RLS security remediation.

## 10. Recommended Next Task Split

Recommended follow-up tasks:

1. `database/data-sync planning`: generate finalized sync set draft, read-only.
2. `database/tooling`: build development-only dry-run / sample apply tool.
3. `database/data-sync development`: run approved development sample write.
4. `database/preflight production`: confirm backup and rerun production SELECT-only audit.
5. `database/production`: production apply, only after explicit approval.
6. `config/ci`: optional CI PR using `workflow_dispatch` and development-only scope first.
7. `database/security`: separate Supabase advisor / RLS task.

## 11. Validation Plan

### 11.1 Read-only validation

Before any write task:

- Re-run count comparison.
- Recompute source-only / changed / DB-only counts.
- Confirm duplicate key count remains `0` for selected keys.
- Review category distribution.
- Review tags diff summary.
- Review score diff summary.
- Review suit mapping consistency.
- Generate sample rows for each planned operation class.

### 11.2 Development validation

Before production write:

- Run dry-run apply against development.
- Run a small sample write against development if approved.
- Verify generated row counts and field diffs.
- Rehearse rollback on the development sample.
- Perform UI smoke check if affected queries or display paths depend on changed data.

### 11.3 Production validation

Only after explicit production approval:

- Confirm backup exists before apply.
- Confirm production project ref before any command.
- Apply only the approved sync set.
- Record inserted row list.
- Record updated rows with before/after snapshots.
- Run post-apply diff.
- Verify random samples from source-only, changed, and DB-only classes.
- Confirm rollback readiness after apply.

## 12. Rollback Plan

### 12.1 Rollback for docs-only changes

If this planning document is wrong or premature:

- Before merge: close the PR or push a correction commit.
- After merge to `develop`: open a revert PR that removes or corrects this file.

### 12.2 Required rollback design for future database/data-sync

A future data-sync task must define rollback before any write:

- Backup before write.
- Inserted rows list.
- Updated rows before/after snapshot.
- Row-level update log.
- Generated inverse patch if applicable.
- Separate rollback validation.
- No destructive DB-only cleanup without separate approval.

## 13. Open Questions

1. Should normalized key be the primary matching basis for finalized sync set generation?
2. Should source-only rows be inserted all at once or split by category / suit / batch?
3. Which changed fields are allowed to update first?
4. Are `tags` differences allowed to be bulk-overwritten after diff review?
5. Are `scores`, `stars`, and `name` differences allowed to be bulk-overwritten from seal100x?
6. Should `category` be overwritten from seal100x or used only for matching?
7. Should DB-only rows be preserved, marked, manually reviewed, or later cleaned?
8. What is the approved mapping strategy for `suit_id` and `temp_suit_name`?
9. Should development dry-run / sample-write tooling be built before any production plan?
10. What backup, rollback, and validation method is required for production write?
11. Should CI be added in a separate PR, starting with `workflow_dispatch` + development only?
12. Should Supabase advisor security risks be handled as a separate `database/security` task before or after clothes sync execution?
