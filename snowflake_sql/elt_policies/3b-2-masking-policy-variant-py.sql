-- 1. Set current role
USE ROLE ACCOUNTADMIN;
USE SECONDARY ROLES NONE;

-- 2. Remove masking policy if tagged
ALTER TABLE DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"
MODIFY COLUMN PAYLOAD UNSET MASKING POLICY
;

-- 3. Create masking logic
DROP FUNCTION IF EXISTS DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_LOGIC(VARCHAR, VARIANT);
CREATE OR REPLACE FUNCTION DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_LOGIC(ROLE VARCHAR, PAYLOAD VARIANT)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = 3.10
HANDLER = 'mask_handler'
AS
$$
def mask_handler(role: str, payload: dict) -> dict:
    # payload arrives as a Python dict if variant is JSON-like

    if role in ("ACCOUNTADMIN", "SYSADMIN"):
        return payload
        
    elif role in ("BI_READONLY"):
        if payload["nationality"].lower() == "british":
            payload["name"]["forename"] = "** MASKED **"
        else:
            payload["name"]["surname"]  = "** MASKED **"
            
    else:
        payload["name"]["forename"] = "** MASKED **"
        payload["name"]["surname"]  = "** MASKED **"

    return payload
$$;

-- 4. Create new masking policy
-- DROP MASKING POLICY DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_POLICY;
CREATE OR REPLACE MASKING POLICY DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_POLICY AS (PAYLOAD VARIANT)
RETURNS VARIANT ->
    DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_LOGIC(CURRENT_ROLE(), PAYLOAD)
;

-- 5. Validate masking policy creation
SELECT GET_DDL('POLICY', 'DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_POLICY');

-- 6. Tag masking policy
ALTER TABLE DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"
MODIFY COLUMN PAYLOAD
SET MASKING POLICY DEV_LANDING_ADF.AIRBNB.PII_DRIVERS_MASKING_POLICY
;

-- 7. Full access
USE ROLE SYSADMIN;
SELECT PAYLOAD:nationality, PAYLOAD:name:forename, PAYLOAD:name:surname FROM DEV_LANDING_ADF.AIRBNB."AirBnBDrivers" LIMIT 5;

-- 8. Partial access (conditional basis)
USE ROLE BI_READONLY;
SELECT PAYLOAD:nationality, PAYLOAD:name:forename, PAYLOAD:name:surname FROM DEV_LANDING_ADF.AIRBNB."AirBnBDrivers" LIMIT 5;

-- 9. No access
USE ROLE QA_READONLY;
SELECT PAYLOAD:nationality, PAYLOAD:name:forename, PAYLOAD:name:surname FROM DEV_LANDING_ADF.AIRBNB."AirBnBDrivers" LIMIT 5;
