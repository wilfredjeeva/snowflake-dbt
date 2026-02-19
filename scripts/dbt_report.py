#!/usr/bin/env python3
"""
dbt_report.py
-------------
Reads dbt's target/run_results.json and target/manifest.json and generates
a self-contained HTML test report — equivalent to pytest's --self-contained-html.

Usage (from repo root):
    python scripts/dbt_report.py

Outputs:
    dbt_test_report.html   (in the current working directory)

Requires no third-party libraries.
"""

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
TARGET_DIR = Path("datahub_refinery/target")
RUN_RESULTS_PATH = TARGET_DIR / "run_results.json"
MANIFEST_PATH    = TARGET_DIR / "manifest.json"
OUTPUT_PATH      = Path("dbt_test_report.html")

# ── Load files ─────────────────────────────────────────────────────────────────
def load_json(path: Path) -> dict:
    if not path.exists():
        print(f"[ERROR] File not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)

run_results = load_json(RUN_RESULTS_PATH)
manifest    = load_json(MANIFEST_PATH)

# ── Parse results ──────────────────────────────────────────────────────────────
results = run_results.get("results", [])

# Only include test node types
test_results = [r for r in results if r.get("unique_id", "").startswith("test.")]

# Enrich each result with manifest metadata
manifest_nodes = manifest.get("nodes", {})

rows = []
for r in test_results:
    uid        = r["unique_id"]
    node       = manifest_nodes.get(uid, {})
    test_name  = node.get("name") or uid.split(".")[-1]
    attached   = node.get("attached_node", "") or ""
    model_name = attached.split(".")[-1] if attached else "—"
    column     = node.get("column_name") or "—"
    test_type  = node.get("test_metadata", {}).get("name") or node.get("resource_type", "test")
    status     = r.get("status", "unknown")
    exec_time  = r.get("execution_time", 0)
    message    = (r.get("message") or "").replace("<", "&lt;").replace(">", "&gt;")
    rows.append({
        "test_name":  test_name,
        "model":      model_name,
        "column":     column,
        "test_type":  test_type,
        "status":     status,
        "exec_time":  exec_time,
        "message":    message,
    })

# Sort: failures first, then by model
rows.sort(key=lambda x: (x["status"] == "pass", x["model"], x["test_name"]))

# ── Summary counts ─────────────────────────────────────────────────────────────
total   = len(rows)
passed  = sum(1 for r in rows if r["status"] == "pass")
failed  = sum(1 for r in rows if r["status"] == "fail")
errored = sum(1 for r in rows if r["status"] == "error")
skipped = total - passed - failed - errored

overall_status = "PASSED" if failed == 0 and errored == 0 else "FAILED"
badge_color    = "#28a745" if overall_status == "PASSED" else "#dc3545"

generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
dbt_version  = run_results.get("metadata", {}).get("dbt_schema_version", "")

# ── Status helpers ─────────────────────────────────────────────────────────────
STATUS_ICON  = {"pass": "✅", "fail": "❌", "error": "⚠️", "warn": "⚠️"}
STATUS_CLASS = {"pass": "pass", "fail": "fail",  "error": "error", "warn": "warn"}

def status_icon(s):  return STATUS_ICON.get(s, "❓")
def status_cls(s):   return STATUS_CLASS.get(s, "")

# ── Build table rows ───────────────────────────────────────────────────────────
table_rows_html = ""
for row in rows:
    sc   = status_cls(row["status"])
    icon = status_icon(row["status"])
    msg  = f'<span class="msg">{row["message"]}</span>' if row["message"] else ""
    table_rows_html += f"""
      <tr class="{sc}">
        <td>{icon} <code>{row["test_name"]}</code></td>
        <td><code>{row["model"]}</code></td>
        <td>{row["column"]}</td>
        <td>{row["test_type"]}</td>
        <td class="status-cell {sc}">{row["status"].upper()}</td>
        <td>{row["exec_time"]:.2f}s</td>
        <td>{msg}</td>
      </tr>"""

# ── Full HTML ──────────────────────────────────────────────────────────────────
html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>dbt Test Report</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f5f7fa; color: #212529; font-size: 14px;
    }}
    header {{
      background: #1a1f3c; color: #fff; padding: 24px 32px;
      display: flex; align-items: center; justify-content: space-between;
    }}
    header h1 {{ font-size: 22px; font-weight: 700; letter-spacing: .5px; }}
    header .meta {{ font-size: 12px; color: #aab; text-align: right; line-height: 1.7; }}
    .badge {{
      display: inline-block; padding: 6px 18px; border-radius: 20px;
      font-weight: 700; font-size: 15px; background: {badge_color}; color: #fff;
      letter-spacing: 1px;
    }}
    .summary {{
      display: flex; gap: 16px; flex-wrap: wrap;
      padding: 24px 32px; background: #fff;
      border-bottom: 1px solid #e0e4ed;
    }}
    .stat-card {{
      flex: 1; min-width: 130px; border-radius: 10px; padding: 16px 20px;
      text-align: center; box-shadow: 0 1px 4px rgba(0,0,0,.08);
    }}
    .stat-card .num  {{ font-size: 32px; font-weight: 700; }}
    .stat-card .lbl  {{ font-size: 12px; color: #666; margin-top: 4px; text-transform: uppercase; }}
    .card-total   {{ background: #f0f4ff; }}
    .card-passed  {{ background: #eafaf1; }}
    .card-failed  {{ background: #fdf0f0; }}
    .card-error   {{ background: #fff8e1; }}
    .total-num  {{ color: #1a1f3c; }}
    .pass-num   {{ color: #28a745; }}
    .fail-num   {{ color: #dc3545; }}
    .error-num  {{ color: #e67e22; }}
    .table-wrap {{
      padding: 24px 32px;
    }}
    h2 {{ font-size: 16px; font-weight: 600; margin-bottom: 14px; color: #1a1f3c; }}
    table {{
      width: 100%; border-collapse: collapse; background: #fff;
      border-radius: 10px; overflow: hidden;
      box-shadow: 0 1px 6px rgba(0,0,0,.08);
    }}
    thead {{ background: #1a1f3c; color: #fff; }}
    th {{ padding: 12px 14px; text-align: left; font-size: 12px;
          text-transform: uppercase; letter-spacing: .6px; font-weight: 600; }}
    td {{ padding: 10px 14px; border-bottom: 1px solid #eef0f5; vertical-align: top; }}
    tr:last-child td {{ border-bottom: none; }}
    tr.fail   {{ background: #fff5f5; }}
    tr.error  {{ background: #fffbf0; }}
    tr:hover  {{ background: #f0f4ff; cursor: default; }}
    code {{ font-size: 12px; background: #eef0f6; padding: 2px 5px;
             border-radius: 4px; font-family: "SFMono-Regular", Consolas, monospace; }}
    .status-cell {{ font-weight: 700; font-size: 12px; }}
    .status-cell.pass  {{ color: #28a745; }}
    .status-cell.fail  {{ color: #dc3545; }}
    .status-cell.error {{ color: #e67e22; }}
    .msg {{ color: #c0392b; font-size: 12px; white-space: pre-wrap;
             font-family: "SFMono-Regular", Consolas, monospace; }}
    footer {{
      text-align: center; padding: 18px; color: #999; font-size: 12px;
      border-top: 1px solid #e0e4ed;
    }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>🧪 dbt Test Report</h1>
      <div style="margin-top:8px"><span class="badge">{overall_status}</span></div>
    </div>
    <div class="meta">
      Generated: {generated_at}<br>
      dbt schema: {dbt_version}<br>
      Total tests: {total}
    </div>
  </header>

  <div class="summary">
    <div class="stat-card card-total">
      <div class="num total-num">{total}</div>
      <div class="lbl">Total</div>
    </div>
    <div class="stat-card card-passed">
      <div class="num pass-num">{passed}</div>
      <div class="lbl">Passed</div>
    </div>
    <div class="stat-card card-failed">
      <div class="num fail-num">{failed}</div>
      <div class="lbl">Failed</div>
    </div>
    <div class="stat-card card-error">
      <div class="num error-num">{errored}</div>
      <div class="lbl">Errors</div>
    </div>
  </div>

  <div class="table-wrap">
    <h2>Test Results</h2>
    <table>
      <thead>
        <tr>
          <th>Test Name</th>
          <th>Model</th>
          <th>Column</th>
          <th>Test Type</th>
          <th>Status</th>
          <th>Time</th>
          <th>Message</th>
        </tr>
      </thead>
      <tbody>
        {table_rows_html}
      </tbody>
    </table>
  </div>

  <footer>
    Generated by dbt_report.py &mdash; dbt native test results
  </footer>
</body>
</html>
"""

# ── Write output ──────────────────────────────────────────────────────────────
OUTPUT_PATH.write_text(html, encoding="utf-8")
print(f"[OK] Report written to: {OUTPUT_PATH.resolve()}")
print(f"     Total: {total} | Passed: {passed} | Failed: {failed} | Errors: {errored}")
