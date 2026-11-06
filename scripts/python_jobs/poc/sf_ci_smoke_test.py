#!/usr/bin/env python3
"""
CI smoke test (POC) — same idea as the team's sf_ci_smoke_test.py, but auth
comes from GitHub Environment secrets (key-pair / JWT), not SNOWFLAKE_PASSWORD.

Test 1: live SELECT on DEV_GOLD.DBO.DimFuelTypes (exclude sys/hash cols)
Test 2: Cortex reachability via SNOWFLAKE.CORTEX.COMPLETE

Writes CSV + HTML under ./output/ for Actions artifact download.
"""

from __future__ import annotations

import html
import sys
from datetime import datetime, timezone
from pathlib import Path

import pandas as pd

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from python_jobs.sf_connect import connect

# --- Test 1: live table SELECT (stakeholder query) ----------------------------
DIM_FUEL_TYPES_SQL = """
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

# --- Test 2: Cortex reachability (from automation team's smoke test) ----------
# Model name can be overridden with env CORTEX_MODEL if the account differs.
CORTEX_MODEL = (
    __import__("os").environ.get("CORTEX_MODEL") or "claude-sonnet-4-5"
).strip()
CORTEX_SQL = (
    f"SELECT SNOWFLAKE.CORTEX.COMPLETE('{CORTEX_MODEL}', "
    f"'Reply only with: Status OK')"
)

OUTPUT_DIR = Path("output")
CSV_PATH = OUTPUT_DIR / "dim_fuel_types_poc.csv"
HTML_PATH = OUTPUT_DIR / "sf_ci_smoke_test.html"


def write_html(df: pd.DataFrame, cortex_result: str, cortex_ok: bool) -> None:
    generated = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    badge = "#28a745" if cortex_ok else "#dc3545"
    cortex_label = "PASS" if cortex_ok else "FAIL"
    table_html = df.to_html(index=False, border=0, classes="data", escape=True)
    doc = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>SF CI Smoke Test POC</title>
  <style>
    body {{ font-family: Segoe UI, Arial, sans-serif; margin: 24px; background: #f5f7fa; }}
    h1, h2 {{ margin: 0 0 8px; }}
    .meta {{ color: #555; margin-bottom: 16px; }}
    .badge {{ display: inline-block; color: #fff; padding: 4px 12px; border-radius: 12px; font-weight: 700; }}
    pre {{ background: #1e1e1e; color: #d4d4d4; padding: 12px; border-radius: 8px; overflow-x: auto; }}
    table.data {{ border-collapse: collapse; background: #fff; width: 100%; box-shadow: 0 1px 4px rgba(0,0,0,.08); }}
    table.data th {{ background: #3D0F6E; color: #fff; text-align: left; padding: 8px 10px; }}
    table.data td {{ padding: 8px 10px; border-bottom: 1px solid #eee; }}
    .card {{ background: #fff; padding: 12px 16px; border-radius: 8px; margin-bottom: 16px;
             box-shadow: 0 1px 4px rgba(0,0,0,.08); }}
  </style>
</head>
<body>
  <h1>SF CI Smoke Test — POC</h1>
  <div class="meta">Generated {html.escape(generated)}</div>

  <div class="card">
    <h2>Test 1 — DimFuelTypes SELECT
      <span class="badge" style="background:#28a745">PASS</span>
    </h2>
    <p>Rows: {len(df)} | Columns: {len(df.columns)}</p>
    <pre>{html.escape(DIM_FUEL_TYPES_SQL.strip())}</pre>
    {table_html}
  </div>

  <div class="card">
    <h2>Test 2 — Cortex reachability
      <span class="badge" style="background:{badge}">{cortex_label}</span>
    </h2>
    <pre>{html.escape(CORTEX_SQL)}</pre>
    <p><strong>Response:</strong> {html.escape(str(cortex_result))}</p>
  </div>
</body>
</html>
"""
    HTML_PATH.write_text(doc, encoding="utf-8")


def main() -> int:
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []

    print("Connecting via GitHub Environment secrets (JWT)…")
    conn = connect()
    try:
        cur = conn.cursor()

        # ----- Test 1 -----
        print("\n=== Test 1: DimFuelTypes SELECT ===")
        print(DIM_FUEL_TYPES_SQL.strip())
        try:
            df = pd.read_sql(DIM_FUEL_TYPES_SQL, conn)
            print(f"Rows: {len(df)}  Columns: {list(df.columns)}")
            df.to_csv(CSV_PATH, index=False)
            print(f"Wrote CSV: {CSV_PATH.resolve()}")
        except Exception as exc:  # noqa: BLE001 — POC: report and continue to Cortex
            failures.append(f"Test 1 failed: {exc}")
            print(f"ERROR Test 1: {exc}")
            df = pd.DataFrame()

        # ----- Test 2 -----
        print("\n=== Test 2: Cortex reachability ===")
        print(CORTEX_SQL)
        cortex_result = ""
        cortex_ok = False
        try:
            cur.execute(CORTEX_SQL)
            cortex_result = cur.fetchone()[0]
            print(f"Cortex response: {cortex_result}")
            cortex_ok = True
        except Exception as exc:  # noqa: BLE001
            failures.append(f"Test 2 failed: {exc}")
            cortex_result = str(exc)
            print(f"ERROR Test 2: {exc}")

        write_html(df, cortex_result, cortex_ok)
        print(f"Wrote HTML: {HTML_PATH.resolve()}")
        cur.close()
    finally:
        conn.close()

    if failures:
        print("\nPOC finished with failures:")
        for msg in failures:
            print(f"  - {msg}")
        return 1

    print("\nPOC succeeded — both tests passed. Download the Actions artifact.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
