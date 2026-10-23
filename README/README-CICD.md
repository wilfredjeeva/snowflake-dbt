# snowflake-dbt CI/CD

This repository implements a multi-environment CI/CD pipeline for dbt on Snowflake using GitHub Actions.

---

## Branching Strategy

```
feature/*  ──PR──►  test  ──[promote] PR──►  main
                      │                         │
                   TEST +                     PROD
                  PREPROD
```

| Branch | Deploys to | Trigger |
|---|---|---|
| `feature/*` | DEV (optional, manual) | `manual-selective-deploy-to-dev` — `workflow_dispatch` |
| `feature/*` | — | PR validation only (`pr-build-validate.yml`) |
| `test` | TEST → PREPROD → opens promote PR to `main` | PR merged into `test` (merge commit), or `workflow_dispatch` |
| `main` | PROD | Push / merge to `main` only (never a `promote-*` branch) |

**Rules of thumb**

- Feature PRs merge into **`test`** (prefer merge commits, not squash — promote needs both parents).
- After PREPROD succeeds, CI opens a **`[promote]`** PR into `main` with only that PR’s files (same size or smaller if some files already exist on `main`).
- PROD runs only when code lands on **`main`**. The Actions branch column must show `main`, not `promote-*`.

---

## Workflow Files

| File | Purpose | Trigger |
|---|---|---|
| `pr-build-validate.yml` | dbt compile + lint on every PR | `pull_request` to `test` or `main` |
| `deploy-to-test-preprod.yml` | Selective build → TEST → PREPROD (approval) → open promote PR to `main` | PR closed/merged into `test`, or `workflow_dispatch` |
| `deploy-to-prod.yml` | Selective build → PROD (approval gate) | Push to `main`, or `workflow_dispatch` on `main` |
| `manual-selective-deploy-to-dev.yml` | Targeted (or full) `dbt build` → DEV from a **feature branch** | `workflow_dispatch` only |
| `manual-selective-deploy-to-test.yml` | Targeted `dbt build --select` → TEST | `workflow_dispatch` only |
| `manual-selective-deploy-to-preprod.yml` | Targeted `dbt build --select` → PREPROD | `workflow_dispatch` only |
| `manual-selective-deploy-to-prod.yml` | Targeted `dbt build --select` → PROD (**always checks out `main`**) | `workflow_dispatch` from `main` only |
| `manual-full-build-deploy-to-test.yml` | Full build of `test` → TEST | `workflow_dispatch` only |
| `manual-full-build-deploy-to-preprod.yml` | Full build of `test` → PREPROD | `workflow_dispatch` only |
| `manual-full-build-deploy-to-prod.yml` | Full build of `main` → PROD | `workflow_dispatch` only |

> **Manual full-build workflows** — enable only when needed (baseline / reset / major refactor), then disable again.  
> **Manual selective workflows** — recovery / targeted rebuild. Prefer keeping unused ones disabled. PROD selective never checks out a `promote-*` or feature branch.

---

## Selective Build Approach

Automated TEST, PREPROD, and PROD builds are **selective**: only model/snapshot `.sql` files changed by **that PR/merge** are built. No `state:modified` against a stale env manifest (that previously pulled in unrelated failing models). No downstream `+` cascade.

### How selectors are chosen

| Stage | How models are selected |
|---|---|
| TEST / PREPROD | Diff of this PR’s merge into `test`: `HEAD^1...HEAD` (same file set as GitHub’s PR “Files changed”). Converted to `path:models/...sql` / `path:snapshots/...sql` relative to the dbt project. |
| PROD | Diff of the merge into `main`: `HEAD^1...HEAD` (or `HEAD~1...HEAD` if not a merge commit). Same `path:` style. Git always runs from repo root (`git -C $GITHUB_WORKSPACE`) so paths match. |
| Manual selective | Operator-supplied `dbt --select` expression only. |

dbt orders selected nodes by **DAG** (`ref` / `source`): bronze → silver → gold → snapshot/tests in one `dbt build`. You do not need separate runs per layer.

YAML / source files travel with the promote PR when they still differ from `main`, but they are **not** passed to `--select`. Extra lines in a shared `_src_*.yml` do not add other PRs’ models to the build.

### Promote PR creation (`deploy-to-test-preprod.yml`)

After PREPROD succeeds:

1. Start from `origin/main`.
2. Prefer `git cherry-pick -m 1` of the TEST merge (this PR’s patch only).
3. If that conflicts (shared yml / delete-modify), resolve **unmerged paths** with the TEST merge version so the PR still opens — other PRs’ SQL is not added.
4. Title: `{original PR title} [promote]`.
5. If `gh pr create` hits a GitHub 504, the job retries, then prints a compare URL (branch is already pushed).

Replay a merged TEST PR without a new engineer PR: **Actions → dandi-datahub-dbt-to-test-preprod → Run workflow** on branch `test`, with:

- `merge_sha` — full merge commit SHA into `test`
- `pr_title` — original PR title

Do **not** dispatch from a feature branch for replay (loads old YAML / wrong diff).

### What is *not* used for automated selection anymore

| Old approach | Why it was dropped |
|---|---|
| `state:modified` vs env manifest for TEST/PREPROD model pick | Stale PREPROD/PROD manifests rebuilt models from earlier failed PRs |
| Two-dot `git diff base head` for scope | Listed hundreds of files when the feature branch lagged `test` |
| Job-output file lists as `--select` | Corrupted multiline paths → dbt matched 0 nodes |
| PROD trigger on `pull_request` closed into `main` | Actions attributed the run to the `promote-*` head branch |

### Permanent excludes (automated pipelines only)

Still applied on **automated** TEST / PREPROD / PROD and **manual full-build** workflows:

| Exclude | Reason |
|---|---|
| `platinum_ai_mosaic_poc_temp_*` (listed models) | POC/temp — masking policy governance |
| `silver_Ezytreev_ordworks,test_name:expression_is_true` | Pending upstream data fix |

**Manual selective** workflows have **no** `--exclude` — the operator’s selector is the full scope.

---

## Pipeline Flow

### TEST + PREPROD (`deploy-to-test-preprod.yml`)

```
PR merged into test  (or workflow_dispatch with merge_sha)
    │
    ▼
[build]  compile + governance + compute this PR's model list
    │
    ▼
[deploy_test]  ── environment: test
  dbt build --select path:<this PR's sql...>
  HTML report (models + snapshots + tests)
  snow dbt deploy → TEST_DATATRANSFORMATIONS
    │
    ▼
[deploy_preprod]  ── environment: preprod (approval)
  Same commit + same selectors as TEST
  snow dbt deploy → PREPROD_DATATRANSFORMATIONS
    │
    ▼
[promote_tested_commit_to_main]
  Branch promote-<sha> from main + this PR's files only
  Open PR → main  title: "... [promote]"
```

### PROD (`deploy-to-prod.yml`)

```
Push to main  (merge of a [promote] PR)  — github.ref must be refs/heads/main
    │
    ▼
[prod_deploy_run]  ── environment: prod (approval)
  Selective path: selectors from this main merge's SQL files
  If no SQL (yml-only promote): skip dbt build/report; still snow dbt deploy
  snow dbt deploy → PROD_DATATRANSFORMATIONS
```

Notes:

- Missing artifact `pipeline-build-meta` on PROD is **expected** (different workflow run). Job defaults to selective.
- Re-running an old failed PROD job does **not** pick up a newer `deploy-to-prod.yml` (pinned to the original commit SHA). Put the workflow on `main` first, then start a **new** run.

### Manual selective DEV (feature branches)

Use **`manual-selective-deploy-to-dev`** when a developer would otherwise run models in the Snowflake/dbt DEV VM. Actions keeps going if the laptop/VM disconnects.

| Input | Purpose |
|---|---|
| **Use workflow from** (branch dropdown) | The feature branch that is checked out and built. This workflow file must exist on that branch — merge/rebase `test` into the feature branch once after this YAML lands. |
| `run_title` | Becomes the Actions **run name** in the list (and the job label). |
| `dbt_selector` | `dbt --select`. Blank = entire project. Prefer exact model/snapshot names or `.sql` paths. Do not list YAML / singular test files. |
| `dbt_exclude` | Optional `dbt --exclude` (hitchhiker tests). |
| `reason` | Audit note (ticket / what you are testing). |

This job **does not** run `snow dbt deploy` (that would overwrite a shared DEV dbt project object from unfinished feature branches). It only `dbt build`s into Snowflake DEV.

DEV is a **shared** warehouse/database. Two developers running at once can collide. This is not a replacement for merging to `test`.

### Manual selective recovery

| Workflow | Checkout | Use when |
|---|---|---|
| `manual-selective-deploy-to-dev` | Branch dropdown (**Use workflow from**) | Feature-branch models in Snowflake DEV |
| `manual-selective-deploy-to-test` | Input `branch` (prefer `test`) | Targeted TEST rebuild |
| `manual-selective-deploy-to-preprod` | Input `branch` | Targeted PREPROD rebuild |
| `manual-selective-deploy-to-prod` | **Always `main`** | Rebuild models already on `main` after a missed selective PROD run |

Example PROD selector (one line, specific files — avoid directory wildcards unless intentional):

```text
path:models/bronze_adf/.../foo.sql path:models/silver/.../bar.sql path:models/gold/.../baz.sql path:snapshots/.../snp_....sql
```

Or model names: `bronze_... silver_... gold_... snp_...`

`path:snapshots/some_folder/` selects **all** snapshots in that folder — prefer the specific `.sql` file.

---

## HTML build report (`scripts/dbt_report.py`)

Generates `dbt_test_report.html` from `run_results.json` / `manifest.json`.

Includes **models, snapshots, seeds, and tests**. Snapshot failures mark the report **FAILED** (not a green report that only listed models/tests).

If no `run_results.json` exists (nothing was built — e.g. yml-only promote), the script exits 0 / report steps are skipped so PROD can still finish `snow dbt deploy`.

The report also shows:

- Run context (title, env, branch, SHA, actor, selector, exclude, elapsed time)
- **Needs attention** panel at the top (FAIL vs ERROR, with the SQL message)
- Relation (`database.schema.table`), materialization, layer, rows affected
- Test **failing-row count** and a separate test **Errors** card (compile / missing object vs assertion FAIL)
- Search + filters (all / problems / FAIL / ERROR)

DEV runs also upload `run_results.json` + `manifest.json` as an artifact.

---

## Timeouts

| Scope | Timeout |
|---|---|
| `deploy_test` / `deploy_preprod` / `prod_deploy_run` | 360 min |
| dbt build step (all environments) | 340 min |
| Manual full-build / selective jobs (incl. DEV) | 360 min (build step 340) |

---

## Project Structure

```
snowflake-dbt/
├── .github/workflows/          GitHub Actions workflows
├── datahub_refinery/           dbt project root
│   ├── dbt_project.yml
│   ├── profiles.yml
│   ├── packages.yml
│   ├── models/                 bronze_adf, silver, gold, platinum
│   ├── macros/
│   ├── seeds/
│   ├── snapshots/
│   └── tests/
├── scripts/
│   ├── validate_metadata.py    governance (tags, owner, classification)
│   └── dbt_report.py           HTML build report (models + snapshots + tests)
└── README/
    └── README-CICD.md
```

---

## Database-per-Layer Architecture

| Layer | Database pattern |
|---|---|
| Landing | `<ENV>_LANDING_ADF` |
| Bronze | `<ENV>_BRONZE_ADF` |
| Silver | `<ENV>_SILVER` |
| Gold | `<ENV>_GOLD` |
| Platinum | `<ENV>_PLATINUM` |

Where `<ENV>` is `DEV`, `TEST`, `PREPROD`, or `PROD`.

`generate_schema_name` sets schema from the 2nd folder under `models/` (e.g. `models/bronze_adf/airbnb/` → `AIRBNB`).

---

## GitHub Configuration

### Environments

| Environment | Approval required |
|---|---|
| `DEV` | No (feature-branch builds) |
| `test` | No |
| `preprod` | Yes |
| `prod` | Yes |

The DEV workflow uses `environment: DEV` to match the GitHub Environment name. If secrets are not found, the environment name in the YAML must match Settings → Environments exactly.

### Secrets (per environment)

| Secret | Description |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Service account username |
| `SNOWFLAKE_ROLE` | Role |
| `SNOWFLAKE_WAREHOUSE` | Warehouse |
| `SNOWFLAKE_DB` | Target database (e.g. `TEST_SILVER`) |
| `SNOWFLAKE_SCHEMA` | Default schema |
| `SNOWFLAKE_PRIVATE_KEY` | PEM RSA private key (not base64) |
| `SNOWFLAKE_KEY_PASSPHRASE` | Key passphrase if encrypted |
| `SNOWFLAKE_DBT_DATABASE` | dbt project store DB (e.g. `DBTCENTRAL`) — **not required for DEV** (no `snow dbt deploy`) |
| `SNOWFLAKE_DBT_SCHEMA` | dbt project store schema — **not required for DEV** |

---

## Governance Validation

Every deploy workflow runs `scripts/validate_metadata.py` before dbt build. Every model YAML must have `tags`, `owner`, and `classification` in `meta`. Failures block the pipeline.

---

## Troubleshooting

### PROD run shows on a `promote-*` branch

**Cause:** Old workflow triggered on `pull_request` closed into `main`.  
**Fix:** `deploy-to-prod.yml` must use `push` to `main` + `if: github.ref == 'refs/heads/main'`. Ensure that file is on `main`.

### PROD says “No model/snapshot SQL changes” but the promote PR has SQL

**Cause:** Selective step ran with `working-directory: datahub_refinery` while grepping for `datahub_refinery/models/...` paths.  
**Fix:** Prod selector must use `git -C "$GITHUB_WORKSPACE"`. Re-run of the **old** failed job will not pick up the fix — put YAML on `main`, then a **new** run (or manual selective PROD with model names).

### Promote job: cherry-pick conflict on shared `_src_*.yml`

**Cause:** Isolated promote onto `main` vs overlapping TEST changes.  
**Fix:** Current promote step resolves conflicts with TEST versions of unmerged paths and still opens the PR. Paste latest `deploy-to-test-preprod.yml` on `test`. Do not “Re-run” an old promote job that still has the old YAML.

### Promote job: `gh pr create` HTTP 504

**Cause:** GitHub API timeout. Branch is usually already pushed.  
**Fix:** Open the compare URL printed in the log, or rely on retries in the latest workflow.

### Replay / dispatch did not create a new promote PR

**Cause:** Those files are already on `main` (“Nothing to promote”), or promote branch already exists.  
**Fix:** For PROD rebuild use `manual-selective-deploy-to-prod` on `main` with an explicit selector (not the promote branch).

### HTML report green but job failed on a snapshot

**Cause:** Older `dbt_report.py` ignored snapshots.  
**Fix:** Current report includes snapshots/seeds; snapshot errors mark FAILED.

### ADF / landing object does not exist in PROD

**Cause:** Upstream landing table not deployed (`PROD_LANDING_ADF...`).  
**Fix:** Deploy ADF/landing first, then re-run PROD. Not a selector bug.

### DEV workflow is missing from the branch dropdown

**Cause:** `manual-selective-deploy-to-dev.yml` is not on that feature branch yet.  
**Fix:** Merge or rebase `test` (once this file is on `test`) into the feature branch, then select it under **Use workflow from**.

### Manual full-build — when to use

- New environment baseline  
- Suspected drift after long selective-only history  
- Major macro refactor  
- Environment recovery  

Enable → run → disable. Prefer **manual selective** when only a few models need a PROD rebuild.
