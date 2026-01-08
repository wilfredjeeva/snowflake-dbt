# CI/CD Pipeline Demo Guide

## 🎯 Demo Objective
Demonstrate the automated CI/CD pipeline for dbt on Snowflake, showing how code changes flow from development through testing to production with automated deployment and validation.

## 📋 Pre-Demo Checklist

### **CRITICAL: Run Setup Script First!**

**Before the demo, you MUST run the setup SQL to create landing tables with sample data:**

1. Open Snowflake UI
2. Run the setup script: [`snowflake_sql/setup/dev_demo_setup.sql`](file:///c:/Users/pasivalingam/repos/snowflake-dbt/snowflake_sql/setup/dev_demo_setup.sql)
3. Verify the output shows all tables created successfully

This script creates:
- ✅ Landing tables with 10 sample AirBnB listings
- ✅ Sample reviews data
- ✅ Sample drivers data (JSON)
- ✅ Gold dimension tables for geography

**Quick verification:**
```sql
USE ROLE DBT_DEV_ROLE;
USE WAREHOUSE DBT_DEV_WH;

-- Should return 10, 10, 2, 6, 6
SELECT 'Listings' AS TABLE_NAME, COUNT(*) FROM DEV_LANDING_ADF.AIRBNB."AirBnBListings"
UNION ALL SELECT 'Reviews', COUNT(*) FROM DEV_LANDING_ADF.AIRBNB."AirBnBReviews"
UNION ALL SELECT 'Drivers', COUNT(*) FROM DEV_LANDING_ADF.AIRBNB."AirBnBDrivers"
UNION ALL SELECT 'Geography', COUNT(*) FROM DEV_GOLD.AIRBNB.DIM_GEOGRAPHY
UNION ALL SELECT 'Geospatial', COUNT(*) FROM DEV_GOLD.AIRBNB.DIM_GEOGRAPHY_GEOSPATIAL;
```

### Before the Presentation
- [ ] **Run the dev_demo_setup.sql script** ⚠️ MUST DO
- [ ] Verify all 5 tables have data (see query above)
- [ ] Have Snowflake UI open in a browser tab
- [ ] Have GitHub Actions page open in another tab
- [ ] Have your code editor open with the project
- [ ] Clone this repo on a clean feature branch

---

## 🎬 Demo Scenario: Adding a New Business Metric

### Story
*"Our business stakeholders want to track 'high-value listings' - properties with price > $200. We'll add this metric to our fact table and demonstrate how the CI/CD pipeline automatically deploys and validates this change."*

---

## 📝 Step-by-Step Demo Script

### **Step 1: Create Feature Branch** (2 minutes)

**What to say:**
> "We follow GitFlow branching strategy. All development work starts in a feature branch, which automatically deploys to our DEV environment."

**Actions:**
```bash
# In your terminal
cd c:\Users\pasivalingam\repos\snowflake-dbt
git checkout -b feature/high-value-listings
```

**Show on screen:**
- Terminal output showing new branch creation
- Current branch indicator in VS Code

---

### **Step 2: Make Code Changes** (3 minutes)

**What to say:**
> "Let's add a calculated field to identify high-value listings. I'm modifying our gold fact table to include this business logic."

**Actions:**
Open `datahub_refinery\models\gold\airbnb\airbnb_gold_fact_listings.sql` and add the following:

**After line 46 (after `SYSDATAPROCESSORNAME`), add:**
```sql
    CASE 
        WHEN ABNB.PRICE > 200 THEN 'High Value'
        WHEN ABNB.PRICE > 100 THEN 'Medium Value'
        ELSE 'Standard'
    END AS VALUE_CATEGORY,
```

**What to show:**
- Split screen: code before and after
- Explain the business logic briefly
- Save the file

---

### **Step 3: Commit and Push** (2 minutes)

**What to say:**
> "Now I commit the changes and push to GitHub. This single action will trigger our automated CI/CD pipeline."

**Actions:**
```bash
git add datahub_refinery/models/gold/airbnb/airbnb_gold_fact_listings.sql
git commit -m "feat: Add value category classification to listings"
git push origin feature/high-value-listings
```

**Show on screen:**
- Git commit message
- Push in progress

---

### **Step 4: Show GitHub Actions Trigger** (1 minute)

**What to say:**
> "The push automatically triggers our DEV deployment workflow. Let's watch it in action."

**Actions:**
1. Switch to GitHub Actions tab in browser
2. Navigate to: `https://github.com/YOUR_ORG/snowflake-dbt/actions`
3. Show the running "Deploy DEV (feature/*)" workflow

**Point out:**
- Workflow name: "Deploy DEV (feature/*)"
- Trigger: push to `feature/high-value-listings`
- Status: Running (yellow icon)
- Started timestamp

---

### **Step 5: Explain Pipeline Steps** (3 minutes)

**What to say:**
> "Our pipeline follows these automated steps. Let's walk through what's happening behind the scenes."

**Show the workflow run and explain each step:**

```
✓ Checkout code                     - Clones our repository
✓ Setup Python 3.11                 - Prepares runtime environment
✓ Install Snowflake CLI + dbt       - Installs deployment tools
✓ Write Snowflake private key       - Configures authentication
✓ Configure Snowflake CLI           - Sets up connection to DEV
✓ Install dbt dependencies          - Downloads dbt packages
✓ Deploy dbt project                - Uploads project to Snowflake
⏳ Execute dbt build                 - Running models, tests, snapshots
```

**Key points to emphasize:**
- **No manual steps** - completely automated
- **Key-pair authentication** - secure, no passwords stored
- **dbt on Snowflake** - leverages Snowflake's compute power
- **Includes testing** - data quality checks run automatically

---

### **Step 6: Watch the Build Execute** (2 minutes)

**What to say:**
> "The build step runs all our dbt models in dependency order. Watch how it processes bronze, then silver, then gold layers."

**Actions:**
1. Click on "Execute dbt build in Snowflake (DEV)" step
2. Show the expanding log output

**Point out the execution order:**
```
1 of 8 START sql table model AIRBNB.AirBnBDrivers ........... [RUN]
1 of 8 OK created sql table model AIRBNB.AirBnBDrivers ...... [SUCCESS 1 in 1.04s]

2 of 8 START sql table model AIRBNB.AirBnBListings .......... [RUN]
2 of 8 OK created sql table model AIRBNB.AirBnBListings ..... [SUCCESS 1 in 0.79s]

...

8 of 8 START sql table model DEV_GOLD.AIRBNB.FACT_AIRBNBLISTINGS ... [RUN]
8 of 8 OK created sql table model DEV_GOLD.AIRBNB.FACT_AIRBNBLISTINGS [SUCCESS 1 in 1.14s]

Completed successfully
Done. PASS=8 WARN=0 ERROR=0 SKIP=0 TOTAL=8
```

**Highlight:**
- ✅ Green checkmarks = success
- ⏱️ Execution times (fast!)
- 📊 Summary: PASS=8, ERROR=0

---

### **Step 7: Verify in Snowflake** (3 minutes)

**What to say:**
> "Let's verify the changes are live in Snowflake. Our new column should be in the DEV_GOLD fact table."

**Actions:**
Switch to Snowflake UI and run:

```sql
USE ROLE DBT_DEV_ROLE;
USE WAREHOUSE DBT_DEV_WH;
USE DATABASE DEV_GOLD;
USE SCHEMA AIRBNB;

-- Show the new column exists
DESCRIBE TABLE FACT_AIRBNBLISTINGS;

-- Query the new value category
SELECT 
    VALUE_CATEGORY,
    COUNT(*) AS LISTING_COUNT,
    AVG(PRICE) AS AVG_PRICE,
    MIN(PRICE) AS MIN_PRICE,
    MAX(PRICE) AS MAX_PRICE
FROM FACT_AIRBNBLISTINGS
GROUP BY VALUE_CATEGORY
ORDER BY VALUE_CATEGORY;
```

**Expected results:**
```
VALUE_CATEGORY  | LISTING_COUNT | AVG_PRICE | MIN_PRICE | MAX_PRICE
----------------|---------------|-----------|-----------|----------
High Value      |           XXX |       XXX |       201 |       XXX
Medium Value    |           XXX |       XXX |       101 |       200
Standard        |           XXX |       XXX |         0 |       100
```

**What to emphasize:**
- ✅ Column created automatically
- ✅ Data populated correctly
- ✅ Business logic working as expected
- ⚡ All done in ~15 seconds from code push!

---

### **Step 8: Show Version Control** (2 minutes)

**What to say:**
> "All changes are tracked and auditable. Let's see the lineage and metadata."

**Show in Snowflake:**
```sql
-- Show dbt project metadata
USE DATABASE DBTCENTRAL;
USE SCHEMA DEV_DBTPROJECTNAME;

-- See the deployed dbt project object
SHOW DBT PROJECTS;

-- Show when it was last deployed
SELECT 
    NAME,
    CREATED_ON,
    LAST_ALTERED,
    COMMENT
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

**In GitHub:**
- Show the commit history
- Highlight the workflow success badge
- Show the dbt artifacts uploaded (manifest.json)

---

## 🚀 Advanced Demo Options

### Option A: Show Testing Failures

**Scenario:** Demonstrate what happens when tests fail

**Actions:**
1. Add a test that will fail:
   ```sql
   -- In datahub_refinery/models/gold/airbnb/schema.yml
   - name: value_category
     tests:
       - accepted_values:
           values: ['High Value', 'Medium Value']  # Intentionally exclude 'Standard'
   ```

2. Commit and push
3. Show the pipeline fail with clear error messages
4. Revert the change

**What to say:**
> "Our pipeline includes automated testing. If a test fails, the deployment stops, preventing bad data from reaching production."

---

### Option B: Show Promotion to TEST

**Scenario:** Merge to test branch to deploy to TEST environment

**Actions:**
```bash
# Create Pull Request
git checkout test
git merge feature/high-value-listings
git push origin test
```

**What to show:**
- New workflow triggers: "Deploy TEST"
- Same process, different environment
- TEST_GOLD database gets updated
- No manual intervention required

**What to say:**
> "Once DEV testing is complete, we merge to the test branch. This automatically deploys to our TEST environment for QA validation."

---

### Option C: Show Full Promotion Flow

**Visual diagram to show:**

```
feature/* branch  →  DEV (automated)
       ↓
   test branch    →  TEST (automated)
       ↓
                  →  PREPROD (requires approval)
       ↓
  pre-prod branch →  PROD deploy (requires approval)
       ↓
                  →  PROD execute (via ADF)
```

**What to say:**
> "Our pipeline supports multiple environments with approval gates. DEV and TEST are fully automated for fast iteration. PREPROD and PROD require manual approval for compliance and safety."

---

## 🎤 Key Talking Points

### Benefits to Emphasize

1. **Speed & Efficiency**
   - "From code commit to deployed in ~15 seconds"
   - "No manual deployment steps - developers stay in flow"

2. **Quality & Reliability**
   - "Automated testing catches errors before production"
   - "Consistent deployment process - no human error"

3. **Auditability & Compliance**
   - "Every change tracked in Git"
   - "Approval gates for production"
   - "Full lineage in Snowflake metadata"

4. **Developer Experience**
   - "Push code, everything else is automated"
   - "Instant feedback on failures"
   - "Self-service for developers"

5. **Cost Optimization**
   - "dbt runs in Snowflake - no external compute costs"
   - "Warehouses auto-suspend - pay only for what you use"

---

## 📊 Metrics to Share

Prepare slides with these metrics:

- **Deployment frequency:** X times per day
- **Lead time:** < 30 seconds from commit to DEV
- **Failure rate:** Y% (show trend over time)
- **MTTR (Mean Time to Recover):** Z minutes
- **Test coverage:** N data quality tests

---

## ❓ Anticipated Questions & Answers

**Q: What if the deployment fails?**
> **A:** The pipeline stops immediately, sends a notification, and the developer can see detailed logs in GitHub Actions. The previous version stays running - no downtime.

**Q: How do we handle rollbacks?**
> **A:** We can revert the Git commit and push, which triggers an automatic redeployment of the previous version.

**Q: Who can deploy to production?**
> **A:** Only approved users can merge to pre-prod branch. PREPROD and PROD environments require approval gates configured in GitHub.

**Q: What about data quality?**
> **A:** dbt tests run automatically on every build. We have schema tests, null checks, referential integrity tests, and custom business logic tests.

**Q: How much does this cost?**
> **A:** Minimal - we use Snowflake's compute (warehouse spins down after use). GitHub Actions is free for private repos with included minutes.

**Q: Can we add more tests?**
> **A:** Absolutely! Just add YAML configuration or custom test files. The pipeline automatically picks them up.

---

## 🔧 Troubleshooting During Demo

### If pipeline fails:
1. Stay calm - this demonstrates error handling!
2. Show the error logs in GitHub Actions
3. Explain how developers would debug
4. Show how to revert if needed

### If Snowflake query is slow:
- Explain that DEV warehouse might be suspended
- Show auto-resume in action
- Mention this is why we use larger warehouses in PROD

### If version mismatch:
- Show the manifest.json artifact
- Explain how dbt tracks dependencies
- Run `dbt deps` to sync

---

## 📁 Files to Have Ready

Keep these open in tabs:
- GitHub Actions: https://github.com/YOUR_ORG/snowflake-dbt/actions
- GitHub Repo: https://github.com/YOUR_ORG/snowflake-dbt
- Snowflake UI (logged in as DBT_DEV_ROLE)
- VS Code with project open
- This demo guide

---

## ⏱️ Timing Guide

- **Quick Demo (5 min):** Steps 1-4 + 7
- **Standard Demo (15 min):** Steps 1-8
- **Deep Dive (30 min):** All steps + Option A or B + Q&A

---

## 🎯 Success Criteria

At the end of the demo, your audience should understand:

✅ How code changes flow from dev to production  
✅ The role of automated testing in data quality  
✅ How the pipeline saves time and reduces errors  
✅ The approval process for production changes  
✅ How to troubleshoot when things go wrong  

---

## 📝 Post-Demo Actions

1. Share this guide with the team
2. Offer hands-on workshop for developers
3. Collect feedback on the pipeline
4. Document any new questions that came up

---

## 🚦 Quick Start Commands

```bash
# Start the demo
git checkout -b feature/demo-YOURNAME
# Make your change
git add .
git commit -m "feat: your change description"
git push origin feature/demo-YOURNAME

# Check status
gh workflow list
gh run list --workflow "Deploy DEV"

# Clean up after demo
git checkout main
git branch -D feature/demo-YOURNAME
git push origin --delete feature/demo-YOURNAME
```

---

**Good luck with your demo! 🎉**
