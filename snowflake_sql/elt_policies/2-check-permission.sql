-- 1. Check sesssion's secondary roles
SELECT CURRENT_SECONDARY_ROLES();

-- 2. Clear session's secondary roles (if exists)
USE SECONDARY ROLES NONE;

-- 3. Use custom roles
USE ROLE QA_READONLY;

-- 4. Try accessing database that you don't have access to
USE DATABASE DEV_SILVER_ADF;

-- 5. Try accessing database that you have access to
USE DATABASE DEV_BRONZE_ADF;