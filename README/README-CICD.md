# snowflake-dbt CI/CD (dbt on Snowflake)

This repository implements a multi-environment CI/CD pattern for dbt on Snowflake:

- **feature/*** → Deploy+Run to **DEV**
- **test** → Deploy+Run to **TEST**
- After TEST success → Deploy+Run to **PREPROD** (approval gate via GitHub Environment)
- After PREPROD success → auto-PR **test → pre-prod**
- **pre-prod** → Deploy-only to **PROD** (approval gate via GitHub Environment)
- After PROD success → auto-PR **pre-prod → main**
- PROD execution is performed by **ADF** (Snowflake Script activity calling EXECUTE DBT PROJECT)

## Project Structure

The dbt project root is in the `datahub_refinery/` directory, which contains:
- `dbt_project.yml` - dbt project configuration
- `profiles.yml` - Snowflake connection profiles
- `packages.yml` - dbt package dependencies
- `models/` - dbt models organized by layer
- `macros/` - custom dbt macros
- `seeds/` - seed data files
- `snapshots/` - snapshot models
- `tests/` - custom data tests

## CI/CD Tools

Workflows use:
- **Snowflake CLI** (`snow`) - Deploys and executes dbt projects in Snowflake
- **dbt Core + dbt-snowflake** - Installed on GitHub Actions runner
- **Key-pair authentication** - Via `SNOWFLAKE_PRIVATE_KEY_B64` stored in GitHub Environments

## Prerequisites

### 1. Snowflake Setup

Create the required databases for each environment:

```sql
-- DEV Environment
CREATE DATABASE IF NOT EXISTS DEV_LANDING_ADF;
CREATE DATABASE IF NOT EXISTS DEV_BRONZE_ADF;
CREATE DATABASE IF NOT EXISTS DEV_SILVER;
CREATE DATABASE IF NOT EXISTS DEV_GOLD;
CREATE DATABASE IF NOT EXISTS DEV_PLATINUM;

-- TEST Environment
CREATE DATABASE IF NOT EXISTS TEST_LANDING_ADF;
CREATE DATABASE IF NOT EXISTS TEST_BRONZE_ADF;
CREATE DATABASE IF NOT EXISTS TEST_SILVER;
CREATE DATABASE IF NOT EXISTS TEST_GOLD;
CREATE DATABASE IF NOT EXISTS TEST_PLATINUM;

-- PREPROD Environment
CREATE DATABASE IF NOT EXISTS PREPROD_LANDING_ADF;
CREATE DATABASE IF NOT EXISTS PREPROD_BRONZE_ADF;
CREATE DATABASE IF NOT EXISTS PREPROD_SILVER;
CREATE DATABASE IF NOT EXISTS PREPROD_GOLD;
CREATE DATABASE IF NOT EXISTS PREPROD_PLATINUM;

-- PROD Environment
CREATE DATABASE IF NOT EXISTS PROD_LANDING_ADF;
CREATE DATABASE IF NOT EXISTS PROD_BRONZE_ADF;
CREATE DATABASE IF NOT EXISTS PROD_SILVER;
CREATE DATABASE IF NOT EXISTS PROD_GOLD;
CREATE DATABASE IF NOT EXISTS PROD_PLATINUM;

-- Central dbt project store
CREATE DATABASE IF NOT EXISTS DBTCENTRAL;
CREATE SCHEMA IF NOT EXISTS DBTCENTRAL.DEV_DBTPROJECTNAME;
CREATE SCHEMA IF NOT EXISTS DBTCENTRAL.TEST_DBTPROJECTNAME;
CREATE SCHEMA IF NOT EXISTS DBTCENTRAL.PREPROD_DBTPROJECTNAME;
CREATE SCHEMA IF NOT EXISTS DBTCENTRAL.PROD_DBTPROJECTNAME;
```

### 2. Landing Schemas and Tables

For each environment, create the necessary landing schemas and source tables.

Example for DEV:
```sql
CREATE SCHEMA IF NOT EXISTS DEV_LANDING_ADF.AIRBNB;
GRANT ALL PRIVILEGES ON SCHEMA DEV_LANDING_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

-- Create landing tables (customize based on your data sources)
-- See snowflake_sql/elt_pipeline/2-landing-gold-tables.sql for examples
```

### 3. Roles and Permissions

Example for DEV environment:
```sql
CREATE WAREHOUSE IF NOT EXISTS DBT_DEV_WH WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 INITIALLY_SUSPENDED=TRUE;
CREATE ROLE IF NOT EXISTS DBT_DEV_ROLE;

GRANT USAGE ON WAREHOUSE DBT_DEV_WH TO ROLE DBT_DEV_ROLE;

-- Grant database permissions
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_LANDING_ADF TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_BRONZE_ADF TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_SILVER TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_GOLD TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_PLATINUM TO ROLE DBT_DEV_ROLE;
GRANT USAGE ON DATABASE DBTCENTRAL TO ROLE DBT_DEV_ROLE;
GRANT ALL PRIVILEGES ON SCHEMA DBTCENTRAL.DEV_DBTPROJECTNAME TO ROLE DBT_DEV_ROLE;

-- Create CI/CD user
CREATE USER IF NOT EXISTS GHA_DBT_DEV
  DEFAULT_ROLE=DBT_DEV_ROLE
  DEFAULT_WAREHOUSE=DBT_DEV_WH
  DEFAULT_NAMESPACE=DBTCENTRAL.DEV_DBTPROJECTNAME
  MUST_CHANGE_PASSWORD=FALSE;

GRANT ROLE DBT_DEV_ROLE TO USER GHA_DBT_DEV;
```

Repeat similar setup for TEST, PREPROD, and PROD environments.

## GitHub Configuration

### 1. GitHub Environments

Create four GitHub Environments with the following configuration:
- **dev** - No approvers required
- **test** - No approvers required
- **preprod** - Require reviewers
- **prod** - Require reviewers

### 2. Environment Secrets

Configure these secrets for **each environment** (dev, test, preprod, prod):

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `SNOWFLAKE_ACCOUNT` | Snowflake account identifier | `abc12345.us-east-1` |
| `SNOWFLAKE_USER` | Service account username | `GHA_DBT_DEV` |
| `SNOWFLAKE_ROLE` | Role for the user | `DBT_DEV_ROLE` |
| `SNOWFLAKE_WAREHOUSE` | Warehouse to use | `DBT_DEV_WH` |
| `SNOWFLAKE_PROJECT_DB` | Always `DBTCENTRAL` | `DBTCENTRAL` |
| `SNOWFLAKE_PROJECT_SCHEMA` | Environment-specific schema | `DEV_DBTPROJECTNAME` |
| `SNOWFLAKE_PRIVATE_KEY_B64` | Base64-encoded RSA private key | `<base64 string>` |

### 3. Generate RSA Key Pair

```bash
# Generate private key
openssl genrsa -out rsa_key.pem 2048

# Generate public key
openssl rsa -in rsa_key.pem -pubout -out rsa_key.pub

# Base64 encode the private key for GitHub secret
cat rsa_key.pem | base64 -w 0 > rsa_key_b64.txt
```

Add the public key to your Snowflake user:
```sql
ALTER USER GHA_DBT_DEV SET RSA_PUBLIC_KEY='<paste public key here without headers>';
```

Store the base64-encoded private key in the `SNOWFLAKE_PRIVATE_KEY_B64` secret.

## dbt Naming Standard

### Database-per-layer Architecture

Each environment follows this pattern:
- `<ENV>_LANDING_ADF` - Raw data ingestion layer
- `<ENV>_BRONZE_ADF` - Initial transformation layer
- `<ENV>_SILVER` - Cleansed and conformed layer
- `<ENV>_GOLD` - Business logic layer
- `<ENV>_PLATINUM` - Aggregated marts layer

### Folder Structure

Models are organized by layer:
```
datahub_refinery/models/
├── bronze_adf/
│   └── airbnb/
│       ├── _airbnb_bronze_sources.yml
│       ├── airbnb_bronze_drivers.sql
│       ├── airbnb_bronze_listings.sql
│       └── airbnb_bronze_reviews.sql
├── gold/
│   └── airbnb/
│       ├── _airbnb_gold_sources.yml
│       ├── airbnb_gold_dim_listing_details.sql
│       └── airbnb_gold_fact_listings.sql
└── ...
```

The custom macro `macros/generate_schema_name.sql` enforces that **schema = 2nd folder name** (e.g., `models/bronze_adf/airbnb/` → schema `AIRBNB`).

## Workflow Details

### Workflow Files

All workflow files are in `.github/workflows/`:
- `dev-deploy.yml` - Triggered on push to `feature/**` branches
- `test-deploy.yml` - Triggered on push to `test` branch
- `preprod-deploy.yml` - Triggered after successful TEST deployment
- `prod-deploy.yml` - Triggered on push to `pre-prod` branch

### Common Workflow Steps

1. **Checkout code** - Clone the repository
2. **Setup Python** - Install Python 3.11
3. **Install dependencies** - Snowflake CLI, dbt Core, dbt-snowflake
4. **Configure Snowflake connection** - Write private key and create config.toml
5. **Install dbt packages** - Run `dbt deps`
6. **Deploy dbt project** - Upload to Snowflake using `snow dbt deploy`
7. **Execute dbt build** - Run models using `snow dbt execute`

## Troubleshooting

### Issue: "No such option: -c"

**Cause**: The `-c` flag is not a valid option for `snow dbt` subcommands.

**Solution**: Remove `-c ci` from commands. The default connection is automatically used when configured in `~/.snowflake/config.toml`.

### Issue: "dbt_project.yml does not exist"

**Cause**: The `--source` path is incorrect.

**Solution**: Ensure workflows use `--source datahub_refinery` to point to the correct dbt project directory.

### Issue: "Schema does not exist or not authorized"

**Cause**: Landing schemas and/or source tables haven't been created in Snowflake.

**Solution**: Create the required schemas and tables in Snowflake before running dbt build. See the Prerequisites section above.

### Issue: "The selection criterion 'path:models+' does not match any enabled nodes"

**Cause**: dbt cannot find any models in the expected location.

**Solution**: Verify that `dbt_project.yml` is in the same directory as the `models/` folder (should be `datahub_refinery/`).
