#!/usr/bin/env python3
"""
dbt_report.py
-------------
Reads dbt's target/run_results.json and target/manifest.json and generates
a self-contained HTML report showing:
  - Model build results  (model / snapshot / seed nodes)
  - Schema test results  (test nodes — populated once tests are defined)

Usage (from repo root):
    python scripts/dbt_report.py

Outputs:
    dbt_test_report.html   (in the current working directory)

Requires no third-party libraries.
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
TARGET_DIR        = Path("datahub_refinery/target")
RUN_RESULTS_PATH  = TARGET_DIR / "run_results.json"
MANIFEST_PATH     = TARGET_DIR / "manifest.json"
OUTPUT_PATH       = Path("dbt_test_report.html")

# ── Load files ─────────────────────────────────────────────────────────────────
def load_json(path: Path) -> dict:
    if not path.exists():
        return None
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)

run_results = load_json(RUN_RESULTS_PATH)
manifest    = load_json(MANIFEST_PATH)

# ── Handle missing run_results ─────────────────────────────────────────────────
if run_results is None:
    error_html = """<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <title>dbt Build Report</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
           background:#f5f7fa; display:flex; align-items:center; justify-content:center;
           min-height:100vh; margin:0; }
    .box { background:#fff; border-radius:12px; padding:48px 56px; text-align:center;
           box-shadow:0 2px 12px rgba(0,0,0,.1); max-width:520px; }
    h1 { color:#dc3545; font-size:24px; margin-bottom:16px; }
    p  { color:#555; line-height:1.6; margin-bottom:10px; }
    code { background:#f0f0f0; padding:2px 6px; border-radius:4px; font-size:13px; }
  </style>
</head>
<body>
  <div class="box">
    <h1>&#10060; Build Failed &mdash; No Results</h1>
    <p>The dbt build step failed before any models were compiled.</p>
    <p><code>datahub_refinery/target/run_results.json</code> was not produced.</p>
    <p>Check the <strong>Build changed dbt models</strong> step for the compilation error.</p>
  </div>
</body>
</html>
"""
    OUTPUT_PATH.write_text(error_html, encoding="utf-8")
    print(f"[WARN] run_results.json not found — build likely failed at compilation.")
    print(f"[OK]  Error report written to: {OUTPUT_PATH.resolve()}")
    sys.exit(0)

# ── Split results by node type ──────────────────────────────────────────────────
all_results     = run_results.get("results", [])
manifest_nodes  = (manifest or {}).get("nodes", {})

MODEL_PREFIXES = ("model.", "snapshot.", "seed.")
TEST_PREFIX    = "test."

model_results = [r for r in all_results if r.get("unique_id", "").startswith(MODEL_PREFIXES)]
test_results  = [r for r in all_results if r.get("unique_id", "").startswith(TEST_PREFIX)]

# ── Helpers ────────────────────────────────────────────────────────────────────
STATUS_ICON  = {"success": "✅", "pass": "✅", "error": "❌", "fail": "❌",
                "skipped": "⏭️", "skip": "⏭️", "warn": "⚠️"}
STATUS_CLASS = {"success": "pass", "pass": "pass", "error": "error", "fail": "fail",
                "skipped": "skip", "skip": "skip", "warn": "warn"}

def icon(s):  return STATUS_ICON.get(s,  "❓")
def cls(s):   return STATUS_CLASS.get(s, "")

def model_label(uid: str) -> str:
    """Return schema.model_name from a unique_id like model.project.schema.name"""
    parts = uid.split(".")
    return ".".join(parts[-2:]) if len(parts) >= 2 else uid

def safe_msg(r: dict) -> str:
    return (r.get("message") or "").replace("<", "&lt;").replace(">", "&gt;")

# ── Model rows ─────────────────────────────────────────────────────────────────
def build_model_rows(results):
    rows = []
    for r in sorted(results, key=lambda x: (x.get("status") != "error", x.get("unique_id",""))):
        uid    = r.get("unique_id", "")
        node   = manifest_nodes.get(uid, {})
        status = r.get("status", "unknown")
        rows.append({
            "label":     model_label(uid),
            "node_type": uid.split(".")[0].capitalize() if "." in uid else "Model",
            "schema":    node.get("schema", "—"),
            "status":    status,
            "exec_time": r.get("execution_time", 0),
            "message":   safe_msg(r),
        })
    return rows

# ── Test rows ──────────────────────────────────────────────────────────────────
def build_test_rows(results):
    rows = []
    for r in sorted(results, key=lambda x: (x.get("status") == "pass", x.get("unique_id",""))):
        uid       = r.get("unique_id", "")
        node      = manifest_nodes.get(uid, {})
        attached  = node.get("attached_node", "") or ""
        status    = r.get("status", "unknown")
        rows.append({
            "test_name":  node.get("name") or uid.split(".")[-1],
            "model":      attached.split(".")[-1] if attached else "—",
            "column":     node.get("column_name") or "—",
            "test_type":  node.get("test_metadata", {}).get("name") or node.get("resource_type", "test"),
            "status":     status,
            "exec_time":  r.get("execution_time", 0),
            "message":    safe_msg(r),
        })
    return rows

model_rows = build_model_rows(model_results)
test_rows  = build_test_rows(test_results)

# ── Model summary ──────────────────────────────────────────────────────────────
m_total   = len(model_rows)
m_pass    = sum(1 for r in model_rows if r["status"] == "success")
m_error   = sum(1 for r in model_rows if r["status"] == "error")
m_skipped = sum(1 for r in model_rows if r["status"] in ("skipped", "skip"))

# ── Test summary ───────────────────────────────────────────────────────────────
t_total   = len(test_rows)
t_pass    = sum(1 for r in test_rows if r["status"] == "pass")
t_fail    = sum(1 for r in test_rows if r["status"] == "fail")
t_error   = sum(1 for r in test_rows if r["status"] == "error")

overall_ok     = m_error == 0 and t_fail == 0 and t_error == 0
overall_status = "PASSED" if overall_ok else "FAILED"
badge_color    = "#28a745" if overall_ok else "#dc3545"

generated_at = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
dbt_version  = run_results.get("metadata", {}).get("dbt_schema_version", "")

# ── Build HTML rows ────────────────────────────────────────────────────────────
def model_table_html(rows):
    if not rows:
        return '<tr><td colspan="6" style="text-align:center;color:#999;padding:24px;">No model results found.</td></tr>'
    html = ""
    for r in rows:
        sc  = cls(r["status"])
        ic  = icon(r["status"])
        msg = f'<span class="msg">{r["message"]}</span>' if r["message"] else ""
        html += f"""
      <tr class="{sc}">
        <td>{ic} <code>{r["label"]}</code></td>
        <td><span class="badge-type">{r["node_type"]}</span></td>
        <td><code>{r["schema"]}</code></td>
        <td class="status-cell {sc}">{r["status"].upper()}</td>
        <td>{r["exec_time"]:.2f}s</td>
        <td>{msg}</td>
      </tr>"""
    return html

def test_table_html(rows):
    if not rows:
        return '<tr><td colspan="7" style="text-align:center;color:#999;padding:24px;">No schema tests defined yet. Add <code>tests:</code> blocks to your model YAML files to populate this section.</td></tr>'
    html = ""
    for r in rows:
        sc  = cls(r["status"])
        ic  = icon(r["status"])
        msg = f'<span class="msg">{r["message"]}</span>' if r["message"] else ""
        html += f"""
      <tr class="{sc}">
        <td>{ic} <code>{r["test_name"]}</code></td>
        <td><code>{r["model"]}</code></td>
        <td>{r["column"]}</td>
        <td>{r["test_type"]}</td>
        <td class="status-cell {sc}">{r["status"].upper()}</td>
        <td>{r["exec_time"]:.2f}s</td>
        <td>{msg}</td>
      </tr>"""
    return html

model_rows_html = model_table_html(model_rows)
test_rows_html  = test_table_html(test_rows)

# ── Full HTML ──────────────────────────────────────────────────────────────────
html = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>dbt Build Report</title>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
      background: #f5f7fa; color: #212529; font-size: 14px;
    }}
    header {{
      background: #1a1f3c; color: #fff; padding: 24px 32px;
      display: flex; align-items: center; justify-content: space-between; flex-wrap: wrap; gap: 12px;
    }}
    header h1 {{ font-size: 22px; font-weight: 700; letter-spacing: .5px; }}
    header .meta {{ font-size: 12px; color: #aab; text-align: right; line-height: 1.7; }}
    .badge {{
      display: inline-block; padding: 6px 18px; border-radius: 20px;
      font-weight: 700; font-size: 15px; background: {badge_color}; color: #fff; letter-spacing: 1px;
    }}
    /* ── Summary strip ── */
    .summary {{
      display: flex; gap: 16px; flex-wrap: wrap;
      padding: 20px 32px; background: #fff; border-bottom: 1px solid #e0e4ed;
    }}
    .summary-group {{ display: flex; gap: 12px; flex-wrap: wrap; align-items: center; }}
    .summary-label {{
      font-size: 11px; text-transform: uppercase; letter-spacing: .8px;
      color: #888; font-weight: 600; padding-right: 8px;
      border-right: 2px solid #e0e4ed; margin-right: 0;
    }}
    .stat-card {{
      min-width: 110px; border-radius: 10px; padding: 14px 18px;
      text-align: center; box-shadow: 0 1px 4px rgba(0,0,0,.08);
    }}
    .stat-card .num {{ font-size: 28px; font-weight: 700; }}
    .stat-card .lbl {{ font-size: 11px; color: #666; margin-top: 4px; text-transform: uppercase; }}
    .card-total   {{ background: #f0f4ff; }} .total-num  {{ color: #1a1f3c; }}
    .card-pass    {{ background: #eafaf1; }} .pass-num   {{ color: #28a745; }}
    .card-error   {{ background: #fdf0f0; }} .error-num  {{ color: #dc3545; }}
    .card-skip    {{ background: #f8f9fa; }} .skip-num   {{ color: #6c757d; }}
    /* ── Tables ── */
    .section {{ padding: 24px 32px; }}
    .section-title {{
      font-size: 15px; font-weight: 700; color: #1a1f3c;
      margin-bottom: 14px; display: flex; align-items: center; gap: 8px;
    }}
    .section-title .count {{
      background: #e8ecf8; color: #1a1f3c; border-radius: 12px;
      padding: 2px 10px; font-size: 12px; font-weight: 600;
    }}
    table {{
      width: 100%; border-collapse: collapse; background: #fff;
      border-radius: 10px; overflow: hidden; box-shadow: 0 1px 6px rgba(0,0,0,.08);
    }}
    thead {{ background: #1a1f3c; color: #fff; }}
    th {{ padding: 12px 14px; text-align: left; font-size: 12px;
          text-transform: uppercase; letter-spacing: .6px; font-weight: 600; }}
    td {{ padding: 10px 14px; border-bottom: 1px solid #eef0f5; vertical-align: top; }}
    tr:last-child td {{ border-bottom: none; }}
    tr.error  {{ background: #fff5f5; }}
    tr.fail   {{ background: #fff5f5; }}
    tr.skip   {{ background: #fafafa; color: #999; }}
    tr:hover  {{ background: #f0f4ff; cursor: default; }}
    code {{ font-size: 12px; background: #eef0f6; padding: 2px 5px;
             border-radius: 4px; font-family: "SFMono-Regular", Consolas, monospace; }}
    .badge-type {{
      font-size: 11px; background: #e8ecf8; color: #1a1f3c;
      border-radius: 4px; padding: 2px 6px; font-weight: 600;
    }}
    .status-cell {{ font-weight: 700; font-size: 12px; }}
    .status-cell.pass  {{ color: #28a745; }}
    .status-cell.error {{ color: #dc3545; }}
    .status-cell.fail  {{ color: #dc3545; }}
    .status-cell.skip  {{ color: #6c757d; }}
    .msg {{ color: #c0392b; font-size: 12px; white-space: pre-wrap;
             font-family: "SFMono-Regular", Consolas, monospace; }}
    .divider {{ border: none; border-top: 1px solid #e0e4ed; margin: 0 32px; }}
    footer {{
      text-align: center; padding: 18px; color: #999; font-size: 12px;
      border-top: 1px solid #e0e4ed;
    }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>🧪 dbt Build Report</h1>
      <div style="margin-top:8px"><span class="badge">{overall_status}</span></div>
    </div>
    <div class="meta">
      Generated: {generated_at}<br>
      dbt schema: {dbt_version}<br>
      Models: {m_total} &nbsp;|&nbsp; Tests: {t_total}
    </div>
  </header>

  <div class="summary">
    <div class="summary-label">Models</div>
    <div class="summary-group">
      <div class="stat-card card-total"><div class="num total-num">{m_total}</div><div class="lbl">Total</div></div>
      <div class="stat-card card-pass"><div class="num pass-num">{m_pass}</div><div class="lbl">Passed</div></div>
      <div class="stat-card card-error"><div class="num error-num">{m_error}</div><div class="lbl">Errors</div></div>
      <div class="stat-card card-skip"><div class="num skip-num">{m_skipped}</div><div class="lbl">Skipped</div></div>
    </div>
    &nbsp;&nbsp;
    <div class="summary-label">Tests</div>
    <div class="summary-group">
      <div class="stat-card card-total"><div class="num total-num">{t_total}</div><div class="lbl">Total</div></div>
      <div class="stat-card card-pass"><div class="num pass-num">{t_pass}</div><div class="lbl">Passed</div></div>
      <div class="stat-card card-error"><div class="num error-num">{t_fail + t_error}</div><div class="lbl">Failed</div></div>
    </div>
  </div>

  <!-- Model Builds -->
  <div class="section">
    <div class="section-title">
      🔧 Model Build Results
      <span class="count">{m_total}</span>
    </div>
    <table>
      <thead>
        <tr>
          <th>Model</th>
          <th>Type</th>
          <th>Schema</th>
          <th>Status</th>
          <th>Time</th>
          <th>Message</th>
        </tr>
      </thead>
      <tbody>
        {model_rows_html}
      </tbody>
    </table>
  </div>

  <hr class="divider"/>

  <!-- Schema Tests -->
  <div class="section">
    <div class="section-title">
      ✅ Schema Test Results
      <span class="count">{t_total}</span>
    </div>
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
        {test_rows_html}
      </tbody>
    </table>
  </div>

  <footer>
    Generated by dbt_report.py &mdash; dbt native build &amp; test results
  </footer>
</body>
</html>
"""

# ── Write output ───────────────────────────────────────────────────────────────
OUTPUT_PATH.write_text(html, encoding="utf-8")
print(f"[OK] Report written to: {OUTPUT_PATH.resolve()}")
print(f"     Models  — Total: {m_total} | Passed: {m_pass} | Errors: {m_error} | Skipped: {m_skipped}")
print(f"     Tests   — Total: {t_total} | Passed: {t_pass} | Failed: {t_fail} | Errors: {t_error}")
