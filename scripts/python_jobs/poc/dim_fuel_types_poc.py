#!/usr/bin/env python3
"""
Manager POC: run a real SELECT against Snowflake DEV and write CSV + HTML.

Query (from stakeholder): DimFuelTypes in DEV_GOLD.DBO, excluding sys/hash cols.

Outputs (written under ./output/ relative to repo root):
  - dim_fuel_types_poc.csv
  - dim_fuel_types_poc.html

CI uploads those as workflow artifacts for download / screenshot.
"""

from __future__ import annotations

import html
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

# scripts/ on PYTHONPATH (set by workflow) or when run locally from repo root
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from python_jobs.sf_connect import connect

PROOF_SQL = """
SELECT * EXCLUDE (
    ATTRIBUTE_HASH,
    HASH_BK,
    SYSCURRENTFLAG,
    SYSDATAPROCESSORNAME,
    SYSDATEFROM,
    SYSDATETO,
    SYSDELETEDFLAG,
    SYSLOADDATE,
    SYSPROCESSINGTOOL,
    SYSRUNID,
    SYSSOURCE
)
FROM DEV_GOLD.DBO.DimFuelTypes
"""

OUTPUT_DIR = Path("output")
CSV_PATH = OUTPUT_DIR / "dim_fuel_types_poc.csv"
HTML_PATH = OUTPUT_DIR / "dim_fuel_types_poc.html"


def write_html(df: pd.DataFrame, path: Path, sql: str) -> None:
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    table_html = df.to_html(index=False, border=0, classes="data", escape=True)
    doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>POC — DimFuelTypes</title>
  <style>
    body {{ font-family: Segoe UI, Arial, sans-serif; margin: 24px; background: #f5f7fa; color: #212529; }}
    h1 {{ margin: 0 0 8px; }}
    .meta {{ color: #555; margin-bottom: 16px; }}
    .badge {{ display: inline-block; background: #28a745; color: #fff; padding: 4px 12px; border-radius: 12px; font-weight: 700; }}
    pre {{ background: #1e1e1e; color: #d4d4d4; padding: 12px; border-radius: 8px; overflow-x: auto; }}
    table.data {{ border-collapse: collapse; background: #fff; width: 100%; box-shadow: 0 1px 4px rgba(0,0,0,.08); }}
    table.data th {{ background: #3D0F6E; color: #fff; text-align: left; padding: 8px 10px; }}
    table.data td {{ padding: 8px 10px; border-bottom: 1px solid #eee; }}
    table.data tr:nth-child(even) {{ background: #fafbff; }}
  </style>
</head>
<body>
  <h1>POC — DimFuelTypes SELECT</h1>
  <div class="meta">
    <span class="badge">SUCCESS</span>
    &nbsp; Generated {html.escape(generated)}
    &nbsp;|&nbsp; Rows: {len(df)}
    &nbsp;|&nbsp; Columns: {len(df.columns)}
  </div>
  <h2>SQL</h2>
  <pre>{html.escape(sql.strip())}</pre>
  <h2>Result</h2>
  {table_html}
</body>
</html>
"""
    path.write_text(doc, encoding="utf-8")


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

    print("Connecting to Snowflake…")
    conn = connect()
    try:
        print("Running proof SELECT…")
        print(PROOF_SQL.strip())
        # pandas warning about DBAPI2 is fine for POC; results still load
        df = pd.read_sql(PROOF_SQL, conn)
    finally:
        conn.close()

    # Snowflake/pandas may uppercase column names — fine for proof
    print(f"Rows: {len(df)}  Columns: {list(df.columns)}")
    if df.empty:
        print("WARNING: query returned 0 rows (table empty or no access) — files still written.")

    df.to_csv(CSV_PATH, index=False)
    write_html(df, HTML_PATH, PROOF_SQL)

    print(f"Wrote CSV : {CSV_PATH.resolve()}")
    print(f"Wrote HTML: {HTML_PATH.resolve()}")
    print("POC succeeded — download artifacts from the Actions run.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
