-- =====================================================
-- QUICK FIX: Update Reviews to Use Numeric IDs
-- =====================================================
-- Run this if you already ran the setup script and got the error
-- This will replace the string review IDs with numeric IDs

USE ROLE DBT_DEV_ROLE;
USE WAREHOUSE DBT_DEV_WH;

-- Drop and recreate the reviews table with corrected data
TRUNCATE TABLE DEV_LANDING_ADF.AIRBNB."AirBnBReviews";

-- Insert corrected reviews with numeric IDs (1001-1010 instead of R001-R010)
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

-- Verify the fix
SELECT 'Reviews Fixed' AS STATUS, COUNT(*) AS ROW_COUNT FROM DEV_LANDING_ADF.AIRBNB."AirBnBReviews";

-- Now your dbt pipeline should run successfully!
