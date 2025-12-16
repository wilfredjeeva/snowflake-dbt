# snowflake-workspace CI/CD (dbt on Snowflake)

This template contains the repo files required to implement the multi-environment CI/CD pattern:

- **feature/*** → Deploy+Run to **DEV**
- **test** → Deploy+Run to **TEST**
- After TEST success → Deploy+Run to **PREPROD** (approval gate via GitHub Environment)
- After PREPROD success → auto-PR **test → pre-prod**
- **pre-prod** → Deploy-only to **PROD** (approval gate via GitHub Environment)
- After PROD success → auto-PR **pre-prod → main**
- PROD execution is performed by **ADF** (Snowflake Script activity calling EXECUTE DBT PROJECT)

## Important
The dbt project root is the folder `snowflake-workspace/` inside the repo root.

Workflows use:
- Snowflake CLI (`snow`)
- dbt Core + dbt-snowflake (installed on runner)
- Key-pair auth via `SNOWFLAKE_PRIVATE_KEY_B64` stored in GitHub Environments

## What you must configure
1) GitHub Environments: dev/test/preprod/prod (+ reviewers for preprod & prod)
2) Environment secrets (per env):
- SNOWFLAKE_ACCOUNT
- SNOWFLAKE_USER
- SNOWFLAKE_ROLE
- SNOWFLAKE_WAREHOUSE
- SNOWFLAKE_PROJECT_DB = DBTCENTRAL
- SNOWFLAKE_PROJECT_SCHEMA = DEV_DBTPROJECTNAME / TEST_DBTPROJECTNAME / PREPROD_DBTPROJECTNAME / PROD_DBTPROJECTNAME
- SNOWFLAKE_PRIVATE_KEY_B64

3) Snowflake objects (DB-per-layer & DBTCENTRAL schemas, roles, users, RSA keys)

## dbt naming standard (client)
Database-per-layer:
- <ENV>_LANDING_ADF
- <ENV>_BRONZE_ADF
- <ENV>_SILVER
- <ENV>_GOLD
- <ENV>_PLATINUM

Folder-per-database:
- models/bronze_adf/*
- models/silver/*
- models/gold/*
- models/platinum/*

Subfolder-per-schema:
- models/bronze_adf/SONITUS/*
- models/silver/ONSGEOPORTAL/*
etc.

Macro `macros/generate_schema_name.sql` enforces "schema = 2nd folder name".
