# snowflake-dbt CI/CD

This repository implements a multi-environment CI/CD pipeline for dbt on Snowflake using GitHub Actions.

---

## Branching Strategy

```
feature/*  ──PR──►  test  ──PR──►  main
                      │               │
                   TEST +          PROD
                  PREPROD
```

| Branch | Deploys to | Trigger |
|---|---|---|
| `feature/*` | — | PR validation only (`pr-build-validate.yml`) |
| `test` | TEST → PREPROD | Push / merge to `test` |
| `main` | PROD | Push / merge to `main` (via test→main PR) |

---

## Workflow Files

| File | Purpose | Trigger |
|---|---|---|
| `pr-build-validate.yml` | dbt compile + lint on every PR | `pull_request` to `test` or `main` |
| `deploy-to-test-preprod.yml` | Selective dbt build → TEST, then PREPROD (approval gate) | Push to `test` |
| `deploy-to-prod.yml` | Selective dbt build → PROD (approval gate) | Push to `main` |
| `manual-full-build-deploy-to-test.yml` | Full build of `test` branch → TEST | `workflow_dispatch` only |
| `manual-full-build-deploy-to-preprod.yml` | Full build of `test` branch → PREPROD | `workflow_dispatch` only |
| `manual-full-build-deploy-to-prod.yml` | Full build of `main` branch → PROD | `workflow_dispatch` only |

> **Manual full-build workflows** are disabled by default. Enable them from the GitHub Actions UI when a full baseline rebuild is needed (e.g. first-ever environment setup, environment reset, major macro refactor). After the run completes, disable again. The resulting manifest is saved to cache so the next automated selective build can do accurate state comparison.

---

## Selective Build Approach

All automated deployment workflows use **selective builds** — only the models that directly changed are built and tested. No downstream cascade.

### How it works

```
dbt build
  --select "state:modified.body state:modified.macros"
  --state  ./previous-manifest/
```

| Selector | What it builds |
|---|---|
| `state:modified.body` | Models whose SQL body changed vs. the previous manifest |
| `state:modified.macros` | Models whose compiled output changed due to a macro change |

> **No `+` suffix** — downstream models are NOT automatically rebuilt. This prevents a single bronze model change from cascading to rebuild 500+ models. PREPROD and PROD also follow the same approach.

### Build types

The pipeline supports two build modes, determined by the PR title prefix:

| PR title prefix | Build type | What runs |
|---|---|---|
| `[promote]` | **selective** | `state:modified.body state:modified.macros` |
| `[full-build]` | **full** | `path:models+` (all models, with `--full-refresh`) |

When no prefix matches, the pipeline defaults to **selective**.

### Manifest caching

After each successful build, the `manifest.json` is saved to GitHub Actions cache keyed by `run_id`. The next selective build restores the most recent manifest to compare against, enabling accurate `state:modified` detection.

If no manifest is found in cache, the pipeline falls back to a **git-diff selector** — extracting changed `.sql` filenames and building those models directly (still selective, not a full build).

### Permanent excludes

Applied on every build (selective and full) across all environments:

| Exclude | Reason |
|---|---|
| `platinum_ai_mosaic_poc_temp_mosaicicssubgroupdetails`<br>`platinum_ai_mosaic_poc_temp_mosaicicsworkflowendsteps`<br>`platinum_ai_mosaic_poc_temp_mosaicicsworkflownextactions`<br>`platinum_ai_mosaic_poc_temp_mosaicicsworkflowsteps`<br>`platinum_ai_mosaic_poc_temp_mosaicorganisations`<br>`platinum_ai_mosaic_poc_temp_mosaicworkers` | POC/temp platinum models — fail column masking policy governance validation. Excluded until production-ready. |
| `silver_Ezytreev_ordworks,test_name:expression_is_true` | `expression_is_true` test returns failing rows pending upstream data fix. |

---

## Pipeline Flow

### TEST + PREPROD (`deploy-to-test-preprod.yml`)

```
Push to test
    │
    ▼
[build job]
  dbt parse / compile
  Determine build type (selective / full) from PR title
    │
    ▼
[deploy_test job]  ── environment: test (no approval)
  Restore manifest from cache
  dbt build (selective or full)
  Save manifest to cache
  snow dbt deploy → TEST_DATATRANSFORMATIONS
    │
    ▼
[deploy_preprod job]  ── environment: preprod (approval required)
  Restore manifest from cache
  dbt build (selective or full, mirrors TEST)
  Save manifest to cache
  snow dbt deploy → PREPROD_DATATRANSFORMATIONS
```

### PROD (`deploy-to-prod.yml`)

```
Push to main (via [promote] PR from test)
    │
    ▼
[prod_deploy_run job]  ── environment: prod (approval required)
  Download build type from unified pipeline artifact
  Restore PROD manifest from cache
  dbt build (selective or full, mirrors TEST/PREPROD)
  Save PROD manifest to cache
  snow dbt deploy → PROD_DATATRANSFORMATIONS
```

---

## Timeouts

| Scope | Timeout |
|---|---|
| `deploy_test` job | 360 min |
| `deploy_preprod` job | 360 min |
| `prod_deploy_run` job | 360 min |
| dbt build step (all environments) | 340 min |
| Manual full-build job + step | 360 / 340 min |

---

## Project Structure

```
snowflake-dbt/
├── .github/workflows/          GitHub Actions workflows
├── datahub_refinery/           dbt project root
│   ├── dbt_project.yml         dbt project configuration
│   ├── profiles.yml            Snowflake connection profiles
│   ├── packages.yml            dbt package dependencies
│   ├── models/                 dbt models (bronze_adf, silver, gold, platinum)
│   ├── macros/                 custom dbt macros
│   ├── seeds/                  seed data files
│   ├── snapshots/              snapshot models
│   └── tests/                  custom data tests
├── scripts/
│   ├── validate_metadata.py    governance metadata validator (tags, owner, classification)
│   └── dbt_report.py           generates HTML test report from run_results.json
└── README/                     documentation
```

---

## Database-per-Layer Architecture

Each environment follows this pattern:

| Layer | Database pattern |
|---|---|
| Landing | `<ENV>_LANDING_ADF` |
| Bronze | `<ENV>_BRONZE_ADF` |
| Silver | `<ENV>_SILVER` |
| Gold | `<ENV>_GOLD` |
| Platinum | `<ENV>_PLATINUM` |

Where `<ENV>` is `TEST`, `PREPROD`, or `PROD`.

The `generate_schema_name` macro enforces that the schema = the 2nd folder name under `models/` (e.g. `models/bronze_adf/airbnb/` → schema `AIRBNB`).

---

## GitHub Configuration

### Environments

| Environment | Approval required |
|---|---|
| `test` | No |
| `preprod` | Yes — set reviewers under Settings → Environments |
| `prod` | Yes — set reviewers under Settings → Environments |

### Secrets (per environment)

| Secret | Description |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | Service account username |
| `SNOWFLAKE_ROLE` | Role for the user |
| `SNOWFLAKE_WAREHOUSE` | Warehouse to use |
| `SNOWFLAKE_DB` | Target database (e.g. `TEST_SILVER`) |
| `SNOWFLAKE_SCHEMA` | Default schema |
| `SNOWFLAKE_PRIVATE_KEY` | PEM-encoded RSA private key (not base64) |
| `SNOWFLAKE_KEY_PASSPHRASE` | RSA key passphrase (if encrypted) |
| `SNOWFLAKE_DBT_DATABASE` | dbt project store database (e.g. `DBTCENTRAL`) |
| `SNOWFLAKE_DBT_SCHEMA` | dbt project store schema (e.g. `TEST_DATATRANSFORMATIONS`) |

---

## Governance Validation

Every workflow runs `scripts/validate_metadata.py` before any dbt build. This script enforces that every model YAML has:
- `tags:` — at least one tag
- `owner:` — model owner defined in `meta:`
- `classification:` — data classification defined in `meta:`

Builds are blocked if any model fails governance validation.

---

## Troubleshooting

### Selective build rebuilds too many models

**Cause:** The manifest in cache is stale (old run) or no manifest was found, causing git-diff fallback.

**Solution:** If the git-diff fallback selector produces more models than expected, check whether a widely-used source YAML file was modified (source changes can cascade). For a full baseline reset, run the manual full-build workflow.

### "Nothing to do" on selective build

**Cause:** The changed files are YAML-only (schema, descriptions, tests) with no SQL body changes. The `state:modified.body` selector correctly finds nothing.

**Solution:** This is expected behaviour. The pipeline falls back to the git-diff selector automatically. If the git-diff also finds no `.sql` files changed, the build exits cleanly.

### "Does not match any enabled nodes"

**Cause:** A model name in the `--select` or `--exclude` flag doesn't exist in the current project (renamed, deleted, or path issue).

**Solution:** Verify the model name matches exactly (case-sensitive). Check that `dbt_project.yml` `model-paths` is set to `["models"]`.

### Manual full-build workflow — when to use

Use the manual full-build workflows when:
- Setting up a new environment from scratch
- After a long period of selective-only builds and data drift is suspected
- After a major macro refactor that affects many models
- Recovering from a corrupted environment

Enable from GitHub Actions → select workflow → Enable workflow. Disable again after the run completes.
