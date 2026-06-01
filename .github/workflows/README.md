# CI/CD Workflows

This folder contains the GitHub Actions workflows that handle automated dbt deployments across the three environments.

## How it works

Changes flow through environments in this order:

**Feature branch -> test branch -> main branch**

Each stage has its own workflow that handles the dbt build and Snowflake deployment for that environment.

---

## Workflows

### test-deploy.yml
Triggers on push to the `test` branch.

Runs a selective build where possible, comparing changed models against the last cached manifest. If no manifest is available or nothing is detected as changed, it falls back to a full build. The manifest is saved at the end of each run so the next run can use it.

### preprod-deploy.yml
Triggers automatically after the TEST workflow completes successfully on the `test` branch. It can also be run manually via workflow dispatch.

The deployment will not start until someone with reviewer access approves it from the GitHub Actions UI. This is controlled by the required reviewers configured on the `preprod` GitHub environment.

### prod-deploy.yml
Triggers on push to the `main` branch, which happens when a pull request from `test` to `main` is reviewed, approved, and merged.

Same as preprod, the deployment waits for approval before it runs. Reviewers are configured on the `prod` GitHub environment in GitHub Settings.

---

## What each workflow does

All three workflows follow the same steps:

1. Check out the code
2. Install dbt and dependencies
3. Write the Snowflake private key from the environment secret
4. Detect build scope (selective or full)
5. Restore the previous manifest for selective builds
6. Validate governance metadata - every model must have tags, owner and classification set
7. Install dbt packages
8. Write the CI profiles.yml
9. Run dbt build
10. Generate and upload the HTML build report
11. Save the manifest to cache for the next run

If governance validation fails, the workflow stops and the deployment does not proceed.

---

## Environment secrets

Each GitHub environment (`test`, `preprod`, `prod`) has its own set of secrets configured separately. The workflows do not share credentials across environments.

The main secrets used are:

| Secret | Description |
|---|---|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier |
| `SNOWFLAKE_USER` | CI service account username |
| `SNOWFLAKE_PRIVATE_KEY` | Private key for key-pair authentication |
| `SNOWFLAKE_ROLE` | Role used during the dbt run |
| `SNOWFLAKE_WAREHOUSE` | Warehouse used for compute |
| `SNOWFLAKE_DBT_DATABASE` | Target database for dbt objects |
| `SNOWFLAKE_DBT_SCHEMA` | Target schema for dbt objects |

---

## Model exclusions

All model exclusion groups have been removed from the TEST, PREPROD and PROD workflows following confirmation from Abayomi Elebute (architect). Any model failures will now surface directly in the pipeline and should be raised with the data engineering team or Snowflake admin depending on the root cause.

If new exclusions need to be added temporarily in the future, document the reason inline in the workflow file and link to the relevant Jira ticket.
