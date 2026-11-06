# Python jobs on Snowflake (via GitHub Actions)

Use the **`poc-python-snowflake`** workflow to run any committed Python script against a Snowflake Environment (`DEV`, `test`, `preprod`, `prod`).

Cron/schedules come later. For now everything is **Run workflow** (manual).

## How a team member runs their script

1. Add your script under this folder, e.g.  
   `scripts/python_jobs/my_team/my_job.py`
2. Open a PR / merge it to the branch you will dispatch from (usually `test`).
3. GitHub → **Actions** → **poc-python-snowflake** → **Run workflow**
4. Fill in:
   - **run_title** — e.g. `Nilesh OpenData cleanup`
   - **target_env** — `DEV` (or test / preprod / prod)
   - **script_path** — `scripts/python_jobs/my_team/my_job.py`
5. Open the run log → **Run Python script** to see stdout (query results, prints).

You do **not** put Snowflake passwords in the script. CI injects the Environment secrets.

## Minimal script template

```python
#!/usr/bin/env python3
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))  # scripts/
from python_jobs.sf_connect import connect

def main() -> int:
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute("SELECT CURRENT_TIMESTAMP()")
        print(cur.fetchone())
        cur.close()
    finally:
        conn.close()
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
```

## Proof script

`scripts/poc_snowflake_connect.py` runs a generator `SELECT` and prints 5 rows. Use that path first to prove connectivity.
