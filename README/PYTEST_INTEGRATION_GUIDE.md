# Step-by-Step Guide: Integrating Pytest Tests into CI/CD Pipeline

## Overview

This guide will walk you through integrating your QA team's pytest tests into the GitHub Actions CI/CD pipeline so they run automatically after each dbt build.

![Test Structure](file:///C:/Users/pasivalingam/.gemini/antigravity/brain/a03bf190-d280-4673-861a-55931456a8ed/uploaded_image_1767855556950.png)

---

## 🎯 What We'll Accomplish

✅ Fix test configuration to work with CI/CD authentication (JWT)  
✅ Add pytest execution to DEV workflow  
✅ Test the integration locally  
✅ Deploy and verify in GitHub Actions  
✅ Extend to TEST, PREPROD, PROD workflows  

---

## Step 1: Fix Test Configuration Files

### 1.1 Update `conftest.py` to Support JWT Authentication

**Issue:** Current `conftest.py` has incorrect path references and doesn't fully support JWT auth.

**Action:** Update the file with these changes:

```python
# conftest.py
import snowflake.connector
import os, sys, logging, pytest, traceback
from dotenv import load_dotenv

# Fix path - point to current tests directory
PROJECT_ROOT = os.path.abspath(os.path.dirname(__file__))
print("PROJECT_ROOT:", PROJECT_ROOT)

if PROJECT_ROOT not in sys.path:
    sys.path.insert(0, PROJECT_ROOT)

from sf_client import SnowflakeClient

load_dotenv()

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
log = logging.getLogger(__name__)

def pytest_addoption(parser):
    parser.addoption('--sf-account', action='store', default=os.getenv('SNOWFLAKE_ACCOUNT'))
    parser.addoption('--sf-user', action='store', default=os.getenv('SNOWFLAKE_USER'))
    parser.addoption('--sf-role', action='store', default=os.getenv('SNOWFLAKE_ROLE'))
    parser.addoption('--sf-warehouse', action='store', default=os.getenv('SNOWFLAKE_WAREHOUSE'))
    parser.addoption('--sf-database', action='store', default=os.getenv('SNOWFLAKE_DATABASE'))
    parser.addoption('--sf-schema', action='store', default=os.getenv('SNOWFLAKE_SCHEMA'))
    parser.addoption('--disable-ocsp', action='store_true', default=False)
    # JWT authentication
    parser.addoption('--sf-authenticator', action='store',
                     default=os.getenv('SNOWFLAKE_AUTHENTICATOR', 'SNOWFLAKE_JWT'))
    parser.addoption('--sf-private-key-path', action='store',
                     default=os.getenv('SNOWFLAKE_PRIVATE_KEY_PATH'))

@pytest.fixture(scope="session")
def sf_conn(pytestconfig):
    """Snowflake connection with JWT support"""
    auth = pytestconfig.getoption('--sf-authenticator')
    
    conn_params = {
        'account': pytestconfig.getoption('--sf-account'),
        'user': pytestconfig.getoption('--sf-user'),
        'role': pytestconfig.getoption('--sf-role'),
        'warehouse': pytestconfig.getoption('--sf-warehouse'),
        'database': pytestconfig.getoption('--sf-database'),
        'schema': pytestconfig.getoption('--sf-schema')
    }
    
    # Use JWT if authenticator is SNOWFLAKE_JWT
    if auth == 'SNOWFLAKE_JWT':
        private_key_path = pytestconfig.getoption('--sf-private-key-path')
        if private_key_path:
            with open(private_key_path, 'rb') as key_file:
                private_key = key_file.read()
            
            from cryptography.hazmat.backends import default_backend
            from cryptography.hazmat.primitives import serialization
            
            p_key = serialization.load_pem_private_key(
                private_key,
                password=None,
                backend=default_backend()
            )
            
            pkb = p_key.private_bytes(
                encoding=serialization.Encoding.DER,
                format=serialization.PrivateFormat.PKCS8,
                encryption_algorithm=serialization.NoEncryption()
            )
            
            conn_params['private_key'] = pkb
            conn_params['authenticator'] = 'SNOWFLAKE_JWT'
    
    conn = snowflake.connector.connect(**conn_params)
    cur = conn.cursor()
    log.info('✅ Snowflake connection opened (JWT auth)')
    yield cur
    log.info('Closing Snowflake connection.')
    cur.close()
    conn.close()

@pytest.fixture(scope='session')
def sf(pytestconfig):
    """SnowflakeClient fixture with JWT support"""
    client = SnowflakeClient(
        account=pytestconfig.getoption('--sf-account'),
        user=pytestconfig.getoption('--sf-user'),
        role=pytestconfig.getoption('--sf-role'),
        warehouse=pytestconfig.getoption('--sf-warehouse'),
        database=pytestconfig.getoption('--sf-database'),
        schema=pytestconfig.getoption('--sf-schema'),
        disable_ocsp_checks=pytestconfig.getoption('--disable-ocsp'),
        authenticator=pytestconfig.getoption('--sf-authenticator'),
        private_key_path=pytestconfig.getoption('--sf-private-key-path')
    )
    log.info('Opening Snowflake connection...')
    client.connect()
    yield client
    log.info('Closing Snowflake connection.')
    client.close()
```

**File:** `datahub_refinery/tests/conftest.py`

---

### 1.2 Update `requirement.txt` to Include Cryptography

**Action:** Add `cryptography` for JWT key parsing:

```txt
pytest
snowflake-connector-python
pytest-html
python-dotenv
pandas
snowflake-connector-python[pandas]
cryptography
```

**File:** `datahub_refinery/tests/requirement.txt`

---

### 1.3 Make Test Variables Environment-Aware

**Current Issue:** `Data/variables.py` is hardcoded to DEV environment.

**Action:** Update to be dynamic based on environment:

```python
# Environment Variable - dynamically set based on SNOWFLAKE_DATABASE
import os

# Get environment from SNOWFLAKE_DATABASE (e.g., "DEV_BRONZE_ADF" -> "DEV")
database = os.getenv('SNOWFLAKE_DATABASE', 'DEV_BRONZE_ADF')
env_prefix = database.split('_')[0]  # Extract "DEV", "TEST", "PREPROD", or "PROD"

# Dynamic database names
landing_db = f"{env_prefix}_LANDING_ADF"
bronze_db = f"{env_prefix}_BRONZE_ADF"

# Schema and Table names (same across all environments)
airBnB_schema = "AIRBNB"
airBnB_table = "AIRBNBDRIVERS"
```

**File:** `datahub_refinery/tests/Data/variables.py`

---

### 1.4 Update `.env` File for JWT Auth

**Action:** Configure for JWT authentication (for local testing):

```env
SNOWFLAKE_ACCOUNT=your_account_here
SNOWFLAKE_USER=GHA_DBT_DEV
SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT
SNOWFLAKE_PRIVATE_KEY_PATH=~/.snowflake/sf_key.p8
SNOWFLAKE_ROLE=DBT_DEV_ROLE
SNOWFLAKE_WAREHOUSE=DBT_DEV_WH
SNOWFLAKE_DATABASE=DEV_BRONZE_ADF
SNOWFLAKE_SCHEMA=AIRBNB
```

**File:** `datahub_refinery/tests/.env`

⚠️ **Note:** Don't commit actual credentials! This file should be in `.gitignore`.

---

## Step 2: Add Pytest to DEV Workflow

### 2.1 Update `dev-deploy.yml`

**Action:** Add pytest step after the dbt build step:

```yaml
      - name: Run pytest tests
        working-directory: datahub_refinery/tests
        env:
          SNOWFLAKE_ACCOUNT: ${{ secrets.SNOWFLAKE_ACCOUNT }}
          SNOWFLAKE_USER: ${{ secrets.SNOWFLAKE_USER }}
          SNOWFLAKE_AUTHENTICATOR: SNOWFLAKE_JWT
          SNOWFLAKE_PRIVATE_KEY_PATH: /home/runner/sf_key.p8
          SNOWFLAKE_ROLE: ${{ secrets.SNOWFLAKE_ROLE }}
          SNOWFLAKE_WAREHOUSE: ${{ secrets.SNOWFLAKE_WAREHOUSE }}
          SNOWFLAKE_DATABASE: DEV_BRONZE_ADF
          SNOWFLAKE_SCHEMA: AIRBNB
        run: |
          pip install -r requirement.txt
          pytest -v --html=report.html --self-contained-html

      - name: Upload pytest report
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: pytest_report_dev
          path: datahub_refinery/tests/report.html
          if-no-files-found: warn
```

**Insert this AFTER:** The "Execute dbt build in Snowflake (DEV)" step (around line 67)

**File:** `.github/workflows/dev-deploy.yml`

---

## Step 3: Test Locally (Before Pushing)

### 3.1 Install Test Dependencies

```bash
cd c:\Users\pasivalingam\repos\snowflake-dbt\datahub_refinery\tests
pip install -r requirement.txt
```

### 3.2 Set Environment Variables

**PowerShell:**
```powershell
$env:SNOWFLAKE_ACCOUNT = "your_account_here"
$env:SNOWFLAKE_USER = "GHA_DBT_DEV"
$env:SNOWFLAKE_AUTHENTICATOR = "SNOWFLAKE_JWT"
$env:SNOWFLAKE_PRIVATE_KEY_PATH = "$HOME/.snowflake/sf_key.p8"
$env:SNOWFLAKE_ROLE = "DBT_DEV_ROLE"
$env:SNOWFLAKE_WAREHOUSE = "DBT_DEV_WH"
$env:SNOWFLAKE_DATABASE = "DEV_BRONZE_ADF"
$env:SNOWFLAKE_SCHEMA = "AIRBNB"
```

### 3.3 Run Tests

```bash
pytest -v --html=report.html --self-contained-html
```

**Expected Output:**
```
======================== test session starts ========================
collected 2 items

bronze_adf/test_AirBnBDrivers.py::test_landing_bronze_count PASSED [ 50%]
bronze_adf/test_AirBnBDrivers.py::test_landing_bronze_dataValidation PASSED [100%]

======================== 2 passed in 5.23s =========================
```

**If tests pass:** You're ready to commit! ✅  
**If tests fail:** Check Snowflake credentials and table existence.

---

## Step 4: Commit and Push Changes

### 4.1 Stage Modified Files

```bash
cd c:\Users\pasivalingam\repos\snowflake-dbt

git add datahub_refinery/tests/conftest.py
git add datahub_refinery/tests/requirement.txt
git add datahub_refinery/tests/Data/variables.py
git add .github/workflows/dev-deploy.yml
```

### 4.2 Commit

```bash
git commit -m "feat: integrate pytest tests into CI/CD pipeline

- Add JWT authentication support to conftest.py
- Make test variables environment-aware
- Add pytest step to dev-deploy workflow
- Update requirements to include cryptography"
```

### 4.3 Push to Feature Branch

```bash
git push origin feature/dbtcicd21
```

---

## Step 5: Verify in GitHub Actions

### 5.1 Watch Workflow Run

1. Go to: `https://github.com/YOUR_ORG/snowflake-dbt/actions`
2. Find your workflow run (triggered by the push)
3. Click on the running workflow

### 5.2 Check Pytest Step

Look for the "Run pytest tests" step:

```
Run pytest tests
  Installing dependencies...
  ✓ pytest installed
  ✓ snowflake-connector-python installed
  
  Running tests...
  ======================== test session starts ========================
  bronze_adf/test_AirBnBDrivers.py::test_landing_bronze_count PASSED
  bronze_adf/test_AirBnBDrivers.py::test_landing_bronze_dataValidation PASSED
  ======================== 2 passed in 6.45s =========================
```

### 5.3 Download Test Report

1. Scroll to bottom of workflow run page
2. Find "Artifacts" section
3. Click **pytest_report_dev** to download
4. Extract and open `report.html` in browser

**Report shows:**
- ✅ Pass/fail status for each test
- ⏱️ Execution time
- 📊 Summary statistics
- 🔍 Detailed logs for failures

---

## Step 6: Extend to Other Environments

### 6.1 Add to TEST Workflow

**File:** `.github/workflows/test-deploy.yml`

Add same pytest step, but change:
```yaml
SNOWFLAKE_DATABASE: TEST_BRONZE_ADF
```

And upload artifact as:
```yaml
name: pytest_report_test
```

### 6.2 Add to PREPROD Workflow

**File:** `.github/workflows/preprod-deploy.yml`

Change:
```yaml
SNOWFLAKE_DATABASE: PREPROD_BRONZE_ADF
name: pytest_report_preprod
```

### 6.3 Add to PROD Workflow (Optional)

**File:** `.github/workflows/prod-deploy.yml`

⚠️ **Consider:** Do you want tests in PROD, or is validation in PREPROD sufficient?

If yes:
```yaml
SNOWFLAKE_DATABASE: PROD_BRONZE_ADF
name: pytest_report_prod
```

---

## Step 7: Add More Tests

### 7.1 Create Test for Listings

**File:** `datahub_refinery/tests/bronze_adf/test_AirBnBListings.py`

```python
from Data.variables import *
from utils import *

def test_listings_row_count(sf_conn):
    """Compare row counts between landing and bronze listings"""
    landing_table = f"{landing_db}.AIRBNB.\"AirBnBListings\""
    bronze_table = f"{bronze_db}.AIRBNB.AIRBNBLISTINGS"
    compare_row_counts(sf_conn, landing_table, bronze_table)

def test_listings_no_nulls_in_id(sf_conn):
    """Ensure no NULL values in listing ID"""
    bronze_table = f"{bronze_db}.AIRBNB.AIRBNBLISTINGS"
    sf_conn.execute(f"SELECT COUNT(*) FROM {bronze_table} WHERE \"id\" IS NULL")
    null_count = sf_conn.fetchone()[0]
    assert null_count == 0, f"Found {null_count} NULL values in listing ID"
    print(f"✅ No NULL values in listing ID")

def test_listings_price_positive(sf_conn):
    """Ensure all prices are positive"""
    bronze_table = f"{bronze_db}.AIRBNB.AIRBNBLISTINGS"
    sf_conn.execute(f"SELECT COUNT(*) FROM {bronze_table} WHERE \"price\" < 0")
    negative_count = sf_conn.fetchone()[0]
    assert negative_count == 0, f"Found {negative_count} listings with negative price"
    print(f"✅ All prices are positive")
```

### 7.2 Create Test for Reviews

**File:** `datahub_refinery/tests/bronze_adf/test_AirBnBReviews.py`

```python
from Data.variables import *
from utils import *

def test_reviews_row_count(sf_conn):
    """Compare row counts between landing and bronze reviews"""
    landing_table = f"{landing_db}.AIRBNB.\"AirBnBReviews\""
    bronze_table = f"{bronze_db}.AIRBNB.AIRBNBREVIEWS"
    compare_row_counts(sf_conn, landing_table, bronze_table)

def test_reviews_valid_dates(sf_conn):
    """Ensure all review dates are valid"""
    bronze_table = f"{bronze_db}.AIRBNB.AIRBNBREVIEWS"
    sf_conn.execute(f"""
        SELECT COUNT(*) FROM {bronze_table} 
        WHERE \"date\" IS NULL OR \"date\" > CURRENT_DATE()
    """)
    invalid_count = sf_conn.fetchone()[0]
    assert invalid_count == 0, f"Found {invalid_count} reviews with invalid dates"
    print(f"✅ All review dates are valid")
```

These tests will automatically run in the next CI/CD execution!

---

## Troubleshooting

### Issue: "ModuleNotFoundError: No module named 'sf_client'"

**Solution:** Ensure `conftest.py` has `PROJECT_ROOT` pointing to the tests directory.

---

### Issue: "Authentication failed"

**Solution:** 
1. Check `SNOWFLAKE_PRIVATE_KEY_PATH` is correct
2. Verify key file has no password
3. Ensure user has RSA public key configured in Snowflake

---

### Issue: "Table does not exist"

**Solution:**
1. Run the dbt build first to create bronze tables
2. Check `SNOWFLAKE_DATABASE` environment variable
3. Verify schema name matches (`AIRBNB`)

---

### Issue: Tests skip or no tests collected

**Solution:**
1. Ensure test files start with `test_`
2. Ensure test functions start with `test_`
3. Check `working-directory` in workflow is correct

---

## Summary Checklist

- [ ] Fix `conftest.py` to support JWT and correct paths
- [ ] Update `requirement.txt` to include cryptography
- [ ] Make `Data/variables.py` environment-aware
- [ ] Update `.env` for JWT authentication
- [ ] Add pytest step to `dev-deploy.yml`
- [ ] Test locally with pytest
- [ ] Commit and push changes
- [ ] Verify in GitHub Actions
- [ ] Download and check HTML report
- [ ] Extend to TEST, PREPROD workflows
- [ ] (Optional) Add more test files

---

## Next Steps

1. **Start with Step 1** - Fix configuration files
2. **Test locally (Step 3)** - Ensure tests pass before pushing
3. **Deploy (Step 4-5)** - Commit and verify in GitHub Actions
4. **Expand (Step 6-7)** - Add to other environments and write more tests

**Good luck! 🚀**
