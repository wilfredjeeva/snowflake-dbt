#!/usr/bin/env python3
"""
POC proof script: connect to Snowflake and run a sample SELECT.

Shows rows in the Actions log so stakeholders can see a real query result.
Team scripts should live under scripts/python_jobs/<your_name_or_team>/ and
import sf_connect from scripts.python_jobs (see README in that folder).

Usage (local or CI):
  python scripts/poc_snowflake_connect.py
"""

from __future__ import annotations

import sys
from pathlib import Path

# Allow `from python_jobs.sf_connect import connect` when run as a file path.
sys.path.insert(0, str(Path(__file__).resolve().parent))

from python_jobs.sf_connect import connect  # noqa: E402


PROOF_SQL = """
SELECT
    SEQ4()                              AS ROW_ID,
    UNIFORM(1, 100, RANDOM())           AS RANDOM_SCORE,
    'poc-python-snowflake'              AS JOB_NAME,
    CURRENT_USER()                      AS SF_USER,
    CURRENT_ROLE()                      AS SF_ROLE,
    CURRENT_DATABASE()                  AS SF_DATABASE,
    CURRENT_SCHEMA()                    AS SF_SCHEMA,
    CURRENT_WAREHOUSE()                 AS SF_WAREHOUSE,
    CURRENT_TIMESTAMP()                 AS RAN_AT
FROM TABLE(GENERATOR(ROWCOUNT => 5))
ORDER BY ROW_ID
"""


def main() -> int:
    print("Connecting to Snowflake via GitHub Environment secrets…")
    conn = connect()
    try:
        cur = conn.cursor()
        print("Running proof SELECT (5 generated rows)…")
        print("--- SQL ---")
        print(PROOF_SQL.strip())
        print("-----------")
        cur.execute(PROOF_SQL)
        cols = [d[0] for d in cur.description]
        rows = cur.fetchall()
        print(f"Rows returned: {len(rows)}")
        print(" | ".join(cols))
        print("-" * 100)
        for row in rows:
            print(" | ".join(str(v) for v in row))
        cur.close()
    finally:
        conn.close()

    print("POC succeeded — SELECT returned rows above.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
