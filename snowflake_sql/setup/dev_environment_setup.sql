-- ============================================================================
-- Snowflake Setup for DEV Environment - dbt Project
-- ============================================================================
-- This script creates all required databases, schemas, and tables for the
-- DEV environment. Run this as ACCOUNTADMIN or a role with sufficient privileges.
--
-- IMPORTANT: This assumes you've already created:
-- - DBT_DEV_ROLE
-- - DBT_DEV_WH
-- - GHA_DBT_DEV user
-- - DBTCENTRAL database and schemas
-- ============================================================================

USE ROLE ACCOUNTADMIN;

-- ============================================================================
-- STEP 1: Create Layer Databases (if not already created)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS DEV_LANDING_ADF;
CREATE DATABASE IF NOT EXISTS DEV_BRONZE_ADF;
CREATE DATABASE IF NOT EXISTS DEV_SILVER;
CREATE DATABASE IF NOT EXISTS DEV_GOLD_ADF;  -- Note: Using _ADF suffix to match source config
CREATE DATABASE IF NOT EXISTS DEV_PLATINUM;

-- ============================================================================
-- STEP 2: Grant Permissions to DBT_DEV_ROLE
-- ============================================================================

GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_LANDING_ADF TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_BRONZE_ADF TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_SILVER TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_GOLD_ADF TO ROLE DBT_DEV_ROLE;
GRANT USAGE, CREATE SCHEMA ON DATABASE DEV_PLATINUM TO ROLE DBT_DEV_ROLE;

-- ============================================================================
-- STEP 3: Create Landing Schemas and Tables
-- ============================================================================

-- Create AIRBNB schema in Landing
CREATE SCHEMA IF NOT EXISTS DEV_LANDING_ADF.AIRBNB;
GRANT ALL PRIVILEGES ON SCHEMA DEV_LANDING_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

USE SCHEMA DEV_LANDING_ADF.AIRBNB;

-- Landing Table: AirBnBListings
CREATE OR REPLACE TABLE "AirBnBListings"(
    SYSLOADDATE TIMESTAMP_LTZ NOT NULL,
    SYSRUNID VARCHAR NOT NULL,
    SYSPROCESSINGTOOL VARCHAR NOT NULL,
    SYSDATAPROCESSORNAME VARCHAR NOT NULL,
    SOURCESYSTEM VARCHAR NOT NULL,
    "id" VARCHAR,
    "name" VARCHAR,
    "host_id" VARCHAR,
    "host_name" VARCHAR,
    "neighbourhood_group" VARCHAR,
    "neighbourhood" VARCHAR,
    "latitude" VARCHAR,
    "longitude" VARCHAR,
    "room_type" VARCHAR,
    "price" VARCHAR,
    "minimum_nights" VARCHAR,
    "number_of_reviews" VARCHAR,
    "last_review" VARCHAR,
    "reviews_per_month" VARCHAR,
    "calculated_host_listings_count" VARCHAR,
    "availability_365" VARCHAR,
    "number_of_reviews_ltm" VARCHAR,
    "license" VARCHAR
);

-- Landing Table: AirBnBReviews
CREATE OR REPLACE TABLE "AirBnBReviews"(
    SYSLOADDATE TIMESTAMP_LTZ NOT NULL,
    SYSRUNID VARCHAR NOT NULL,
    SYSPROCESSINGTOOL VARCHAR NOT NULL,
    SYSDATAPROCESSORNAME VARCHAR NOT NULL,
    SOURCESYSTEM VARCHAR NOT NULL,
    "listing_id" VARCHAR,
    "id" VARCHAR,
    "date" VARCHAR,
    "reviewer_id" VARCHAR,
    "reviewer_name" VARCHAR,
    "comments" VARCHAR
);

-- Landing Table: AirBnBDrivers (VARIANT format)
CREATE OR REPLACE TABLE "AirBnBDrivers"(
    PAYLOAD VARIANT NOT NULL
);

-- Grant read permissions on landing tables
GRANT SELECT ON ALL TABLES IN SCHEMA DEV_LANDING_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;
GRANT SELECT ON FUTURE TABLES IN SCHEMA DEV_LANDING_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

-- ============================================================================
-- STEP 4: Create Gold Dimension Tables (Pre-existing Reference Data)
-- ============================================================================

-- Create AIRBNB schema in Gold
CREATE SCHEMA IF NOT EXISTS DEV_GOLD_ADF.AIRBNB;
GRANT ALL PRIVILEGES ON SCHEMA DEV_GOLD_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

USE SCHEMA DEV_GOLD_ADF.AIRBNB;

-- Gold Table: DIM_GEOGRAPHY
CREATE OR REPLACE TABLE DIM_GEOGRAPHY(
    GEOGRAPHY_ID NUMBER(38,0) AUTOINCREMENT,
    BOROUGH_ID NUMBER(38,0),
    LATITUDE NUMBER(10,8),
    LONGITUDE NUMBER(11,8),
    GEO_POINT GEOGRAPHY,
    NEIGHBOURHOOD VARCHAR(100),
    NEIGHBOURHOOD_GROUP VARCHAR(100),
    CITY VARCHAR(50),
    COUNTRY_CODE CHAR(2),
    ZIPCODE VARCHAR(20),
    PRIMARY KEY(GEOGRAPHY_ID)
);

-- Insert sample geography data
INSERT INTO DIM_GEOGRAPHY
    (GEOGRAPHY_ID, BOROUGH_ID, LATITUDE, LONGITUDE, GEO_POINT, NEIGHBOURHOOD, NEIGHBOURHOOD_GROUP, CITY, COUNTRY_CODE, ZIPCODE) 
VALUES
    (1, 101, 51.56861000, -0.11270000, NULL, 'NEIGHBOURHOOD A', 'BOROUGH A', 'LONDON', 'GB', 'N/A'),
    (2, 102, 51.47072000, -0.16266000, NULL, 'NEIGHBOURHOOD B', 'BOROUGH B', 'LONDON', 'GB', 'N/A'),
    (3, 103, 51.50701000, -0.23362000, NULL, 'NEIGHBOURHOOD C', 'BOROUGH C', 'LONDON', 'GB', 'N/A'),
    (4, 104, 51.61492000, -0.25632000, NULL, 'NEIGHBOURHOOD D', 'BOROUGH D', 'LONDON', 'GB', 'N/A'),
    (5, 105, 51.52958000, -0.14344000, NULL, 'NEIGHBOURHOOD E', 'BOROUGH E', 'LONDON', 'GB', 'N/A'),
    (6, 106, 51.39648000, -0.21170000, NULL, 'NEIGHBOURHOOD F', 'BOROUGH F', 'LONDON', 'GB', 'N/A');

-- Gold Table: DIM_GEOGRAPHY_GEOSPATIAL
CREATE OR REPLACE TABLE DIM_GEOGRAPHY_GEOSPATIAL(
    GEOSPATIAL_ID NUMBER(38,0) AUTOINCREMENT,
    GEOGRAPHY_ID NUMBER(38,0),
    WARD_ID NUMBER(38,0),
    LOCATION_NAME VARCHAR(100),
    DESCRIPTION VARCHAR(255),
    LATITUDE NUMBER(10,8),
    LONGITUDE NUMBER(11,8),
    GEO_POINT GEOGRAPHY,
    COUNTRY_CODE CHAR(2),
    CITY VARCHAR(50),
    ZIPCODE VARCHAR(20),
    PRIMARY KEY(GEOSPATIAL_ID)
);

-- Insert sample geospatial data
INSERT INTO DIM_GEOGRAPHY_GEOSPATIAL
    (GEOSPATIAL_ID, GEOGRAPHY_ID, WARD_ID, LOCATION_NAME, DESCRIPTION, LATITUDE, LONGITUDE, GEO_POINT, COUNTRY_CODE, CITY, ZIPCODE) 
VALUES
    (1, 1, 2001, 'LOCATION A PARK', 'Area in North London', 51.56861000, -0.11270000, NULL, 'GB', 'LONDON', 'N/A'),
    (2, 2, 2002, 'LOCATION B STREET', 'Residential street', 51.47072000, -0.16266000, NULL, 'GB', 'LONDON', 'N/A'),
    (3, 3, 2003, 'LOCATION C MARKET', 'Local market area', 51.50701000, -0.23362000, NULL, 'GB', 'LONDON', 'N/A'),
    (4, 4, 2004, 'LOCATION D HILL', 'Northern hill region', 51.61492000, -0.25632000, NULL, 'GB', 'LONDON', 'N/A'),
    (5, 5, 2005, 'LOCATION E SQUARE', 'Central square area', 51.52958000, -0.14344000, NULL, 'GB', 'LONDON', 'N/A'),
    (6, 6, 2006, 'LOCATION F PARK', 'South-west open area', 51.39648000, -0.21170000, NULL, 'GB', 'LONDON', 'N/A');

-- Grant permissions on gold tables
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA DEV_GOLD_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;
GRANT SELECT, INSERT, UPDATE, DELETE ON FUTURE TABLES IN SCHEMA DEV_GOLD_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

-- ============================================================================
-- STEP 5: (Optional) Create PII Tags for Data Governance
-- ============================================================================
-- Uncomment these if you want to enable PII tagging

-- CREATE TAG IF NOT EXISTS DEV_LANDING_ADF.AIRBNB.PII_TAG_LISTINGs
--     COMMENT = 'Tag for sensitive PII columns in listings';
-- GRANT APPLY ON TAG DEV_LANDING_ADF.AIRBNB.PII_TAG_LISTINGs TO ROLE DBT_DEV_ROLE;

-- ============================================================================
-- VERIFICATION
-- ============================================================================

-- Verify databases exist
SHOW DATABASES LIKE 'DEV%';

-- Verify schemas exist
SHOW SCHEMAS IN DATABASE DEV_LANDING_ADF;
SHOW SCHEMAS IN DATABASE DEV_GOLD_ADF;

-- Verify tables exist
SHOW TABLES IN SCHEMA DEV_LANDING_ADF.AIRBNB;
SHOW TABLES IN SCHEMA DEV_GOLD_ADF.AIRBNB;

-- Verify role permissions
SHOW GRANTS TO ROLE DBT_DEV_ROLE;

-- ============================================================================
-- NOTES
-- ============================================================================
-- 1. The landing tables (AirBnBListings, AirBnBReviews, AirBnBDrivers) are
--    initially empty. You'll need to load data via ADF or insert test data.
--
-- 2. Bronze, Silver, and Platinum tables will be created automatically by dbt
--    when you run 'dbt build'.
--
-- 3. For TEST, PREPROD, and PROD environments, replace 'DEV' with the
--    appropriate environment prefix and re-run this script.
--
-- 4. Make sure to grant the same permissions for other environments.
-- ============================================================================
