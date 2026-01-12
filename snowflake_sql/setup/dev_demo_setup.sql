-- =====================================================
-- DEV Environment Setup for CI/CD Demo
-- =====================================================
-- Run this script as DBT_DEV_ROLE to prepare your DEV environment
-- This creates landing tables with sample data for the demo

USE ROLE DBT_DEV_ROLE;
USE WAREHOUSE DBT_DEV_WH;

-- =====================================================
-- 1. CREATE LANDING SCHEMA
-- =====================================================
CREATE SCHEMA IF NOT EXISTS DEV_LANDING_ADF.AIRBNB;
GRANT ALL PRIVILEGES ON SCHEMA DEV_LANDING_ADF.AIRBNB TO ROLE DBT_DEV_ROLE;

-- =====================================================
-- 2. CREATE LANDING TABLES (case-sensitive names)
-- =====================================================

-- AirBnB Listings Landing Table
CREATE OR REPLACE TABLE DEV_LANDING_ADF.AIRBNB."AirBnBListings"(
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

-- AirBnB Reviews Landing Table
CREATE OR REPLACE TABLE DEV_LANDING_ADF.AIRBNB."AirBnBReviews"(
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

-- AirBnB Drivers Landing Table (for variant data)
CREATE OR REPLACE TABLE DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"(
    PAYLOAD VARIANT NOT NULL
);

-- =====================================================
-- 3. INSERT SAMPLE DATA
-- =====================================================

-- Sample Listings Data (London properties)
INSERT INTO DEV_LANDING_ADF.AIRBNB."AirBnBListings" VALUES
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1001', 'Cozy Studio in Central London', '5001', 'John Smith', 'Westminster', 'Covent Garden', '51.51279', '-0.12647', 'Entire home/apt', '250', '2', '45', '2024-12-15', '3.2', '1', '300', '12', 'ABC123'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1002', 'Modern Flat Near Tower Bridge', '5002', 'Emma Wilson', 'Tower Hamlets', 'Wapping', '51.50701', '-0.06355', 'Entire home/apt', '180', '1', '78', '2025-01-02', '4.5', '2', '365', '25', 'DEF456'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1003', 'Private Room in Camden', '5003', 'Sarah Johnson', 'Camden', 'Camden Town', '51.53959', '-0.14267', 'Private room', '85', '1', '120', '2024-11-20', '2.8', '1', '200', '38', 'GHI789'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1004', 'Luxury Penthouse Kensington', '5004', 'David Brown', 'Kensington and Chelsea', 'South Kensington', '51.49450', '-0.17420', 'Entire home/apt', '450', '3', '92', '2024-12-28', '5.1', '3', '330', '55', 'JKL012'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1005', 'Budget Room in Shoreditch', '5005', 'Lisa Anderson', 'Hackney', 'Shoreditch', '51.52554', '-0.07818', 'Private room', '65', '1', '156', '2025-01-01', '3.9', '1', '250', '42', 'MNO345'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1006', 'Spacious Apartment Greenwich', '5006', 'Michael Davis', 'Greenwich', 'Greenwich', '51.48270', '-0.00750', 'Entire home/apt', '195', '2', '63', '2024-10-18', '4.2', '1', '280', '18', 'PQR678'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1007', 'Shared Room in Brixton', '5007', 'Rachel Green', 'Lambeth', 'Brixton', '51.46138', '-0.11471', 'Shared room', '45', '1', '89', '2024-09-22', '2.1', '4', '150', '28', 'STU901'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1008', 'Victorian House in Notting Hill', '5008', 'Thomas White', 'Kensington and Chelsea', 'Notting Hill', '51.51540', '-0.20560', 'Entire home/apt', '320', '2', '104', '2024-12-05', '6.3', '2', '340', '67', 'VWX234'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1009', 'Studio in Canary Wharf', '5009', 'Jennifer Taylor', 'Tower Hamlets', 'Canary Wharf', '51.50466', '-0.01949', 'Entire home/apt', '220', '1', '47', '2024-11-12', '3.8', '1', '365', '15', 'YZA567'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1010', 'Family Home in Richmond', '5010', 'Robert Miller', 'Richmond upon Thames', 'Richmond', '51.46141', '-0.30340', 'Entire home/apt', '280', '4', '71', '2024-08-30', '4.7', '1', '300', '22', 'BCD890');

-- Sample Reviews Data (using numeric IDs to match bronze model casting)
INSERT INTO DEV_LANDING_ADF.AIRBNB."AirBnBReviews" VALUES
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1001', '1001', '2024-12-16', '9001', 'Alice Cooper', 'Amazing location! Very clean and comfortable.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1001', '1002', '2024-11-20', '9002', 'Bob Martin', 'Great host, would definitely recommend.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1002', '1003', '2025-01-03', '9003', 'Carol Lee', 'Perfect for a weekend getaway!'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1003', '1004', '2024-11-21', '9004', 'Dan Roberts', 'Good value for money, friendly host.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1004', '1005', '2024-12-29', '9005', 'Eve Thompson', 'Absolutely stunning property! Worth every penny.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1005', '1006', '2025-01-02', '9006', 'Frank Harris', 'Basic but clean. Good location for exploring.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1006', '1007', '2024-10-19', '9007', 'Grace Wilson', 'Lovely apartment with great amenities.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1008', '1008', '2024-12-06', '9008', 'Henry Clark', 'Beautiful Victorian house, highly recommended!'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1009', '1009', '2024-11-13', '9009', 'Iris Lewis', 'Modern and convenient for business travelers.'),
    (CURRENT_TIMESTAMP(), 'DEMO_RUN_001', 'ADF', 'AIRBNB_PIPELINE', 'AIRBNB_API', '1010', '1010', '2024-09-01', '9010', 'Jack Robinson', 'Spacious and perfect for families.');

-- Sample Drivers Data (JSON metadata)
INSERT INTO DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"
SELECT PARSE_JSON($$
{
  "driver_id": "D001",
  "driver_name": "Premium Transport Co",
  "contact_email": "contact@premiumtransport.com",
  "rating": 4.8,
  "vehicles": [
    {"type": "Sedan", "capacity": 4, "available": true},
    {"type": "SUV", "capacity": 6, "available": true}
  ]
}
$$)
UNION ALL
SELECT PARSE_JSON($$
{
  "driver_id": "D002",
  "driver_name": "London Ride Services",
  "contact_email": "info@londonride.co.uk",
  "rating": 4.5,
  "vehicles": [
    {"type": "Minivan", "capacity": 8, "available": false}
  ]
}
$$);

-- =====================================================
-- 4. CREATE GOLD DIMENSION TABLES
-- =====================================================

-- Note: These are referenced in gold models as sources
CREATE SCHEMA IF NOT EXISTS DEV_GOLD.AIRBNB;

CREATE OR REPLACE TABLE DEV_GOLD.AIRBNB.DIM_GEOGRAPHY(
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

INSERT INTO DEV_GOLD.AIRBNB.DIM_GEOGRAPHY
    (GEOGRAPHY_ID, BOROUGH_ID, LATITUDE, LONGITUDE, GEO_POINT, NEIGHBOURHOOD, NEIGHBOURHOOD_GROUP, CITY, COUNTRY_CODE, ZIPCODE) VALUES
    (1, 101, 51.51279000, -0.12647000, NULL, 'Covent Garden', 'Westminster', 'LONDON', 'GB', 'WC2'),
    (2, 102, 51.50701000, -0.06355000, NULL, 'Wapping', 'Tower Hamlets', 'LONDON', 'GB', 'E1W'),
    (3, 103, 51.53959000, -0.14267000, NULL, 'Camden Town', 'Camden', 'LONDON', 'GB', 'NW1'),
    (4, 104, 51.49450000, -0.17420000, NULL, 'South Kensington', 'Kensington and Chelsea', 'LONDON', 'GB', 'SW7'),
    (5, 105, 51.52554000, -0.07818000, NULL, 'Shoreditch', 'Hackney', 'LONDON', 'GB', 'E1'),
    (6, 106, 51.48270000, -0.00750000, NULL, 'Greenwich', 'Greenwich', 'LONDON', 'GB', 'SE10');

CREATE OR REPLACE TABLE DEV_GOLD.AIRBNB.DIM_GEOGRAPHY_GEOSPATIAL(
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

INSERT INTO DEV_GOLD.AIRBNB.DIM_GEOGRAPHY_GEOSPATIAL
    (GEOSPATIAL_ID, GEOGRAPHY_ID, WARD_ID, LOCATION_NAME, DESCRIPTION, LATITUDE, LONGITUDE, GEO_POINT, COUNTRY_CODE, CITY, ZIPCODE) VALUES
    (1, 1, 2001, 'Covent Garden Market', 'Historic market area in Central London', 51.51279000, -0.12647000, NULL, 'GB', 'LONDON', 'WC2'),
    (2, 2, 2002, 'Tower Bridge Area', 'Iconic landmark vicinity', 51.50701000, -0.06355000, NULL, 'GB', 'LONDON', 'E1W'),
    (3, 3, 2003, 'Camden Market', 'Alternative culture market', 51.53959000, -0.14267000, NULL, 'GB', 'LONDON', 'NW1'),
    (4, 4, 2004, 'Museums District', 'Cultural heritage area', 51.49450000, -0.17420000, NULL, 'GB', 'LONDON', 'SW7'),
    (5, 5, 2005, 'Tech City', 'Innovation and tech hub', 51.52554000, -0.07818000, NULL, 'GB', 'LONDON', 'E1'),
    (6, 6, 2006, 'Maritime Greenwich', 'UNESCO World Heritage Site', 51.48270000, -0.00750000, NULL, 'GB', 'LONDON', 'SE10');

-- =====================================================
-- 5. VERIFY SETUP
-- =====================================================

SELECT 'Landing Tables Created' AS STATUS, COUNT(*) AS LISTING_COUNT FROM DEV_LANDING_ADF.AIRBNB."AirBnBListings"
UNION ALL
SELECT 'Reviews Created', COUNT(*) FROM DEV_LANDING_ADF.AIRBNB."AirBnBReviews"
UNION ALL
SELECT 'Drivers Created', COUNT(*) FROM DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"
UNION ALL
SELECT 'Geography Dim Created', COUNT(*) FROM DEV_GOLD.AIRBNB.DIM_GEOGRAPHY
UNION ALL
SELECT 'Geospatial Dim Created', COUNT(*) FROM DEV_GOLD.AIRBNB.DIM_GEOGRAPHY_GEOSPATIAL;

-- =====================================================
-- SETUP COMPLETE!
-- =====================================================
-- You can now run your dbt pipeline:
-- dbt build --target dev
-- 
-- Or trigger the CI/CD pipeline by pushing to a feature branch
-- =====================================================
