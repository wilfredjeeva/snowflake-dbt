-- 1. Create database space for dbt project
CREATE DATABASE IF NOT EXISTS DEV_DBTCENTRAL;

-- 2. Create schema space for dbt project
CREATE SCHEMA IF NOT EXISTS DEV_DBTCENTRAL.DATAHUB_REFINERY;

-- 3. Create object for dbt project
CREATE OR REPLACE DBT PROJECT DEV_DBTCENTRAL.DATAHUB_REFINERY.DATAHUB_DBT_MODELS
  FROM 'snow://workspace/"USER$"."PUBLIC"."snowflake-workspace"/versions/head/datahub_refinery'
  COMMENT = 'Snowflake DBT Project for datahub_refinery'
;

-- 4. Update dbt project
ALTER DBT PROJECT DEV_DBTCENTRAL.DATAHUB_REFINERY.DATAHUB_DBT_MODELS
  ADD VERSION
  FROM 'snow://workspace/"USER$"."PUBLIC"."snowflake-workspace"/versions/head/datahub_refinery'
;
  
-- 5. Check deployed versions
SHOW VERSIONS IN DBT PROJECT DEV_DBTCENTRAL.DATAHUB_REFINERY.DATAHUB_DBT_MODELS;

-- 6. SnowSQL Excution command
EXECUTE DBT PROJECT DEV_DBTCENTRAL.DATAHUB_REFINERY.DATAHUB_DBT_MODELS
ARGS = 'compile --select path:models/bronze_adf/airbnb --target dev'
;