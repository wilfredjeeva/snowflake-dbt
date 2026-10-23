#!/usr/bin/env python3
"""
dbt_report.py
-------------
Reads dbt's target/run_results.json and target/manifest.json and generates
a self-contained HTML build report showing both model and test results —
equivalent to the dbt Cloud native report view.

Optional env vars (DEV / CI context for DEs):
    DBT_REPORT_TITLE, DBT_REPORT_ENV, DBT_REPORT_BRANCH, DBT_REPORT_SHA,
    DBT_REPORT_ACTOR, DBT_REPORT_SELECTOR, DBT_REPORT_EXCLUDE, DBT_REPORT_REASON

Usage (from repo root):
    python scripts/dbt_report.py

Outputs:
    dbt_test_report.html   (in the current working directory)

Requires no third-party libraries.
"""

import html
import json
import os
import sys
from datetime import datetime, timezone, timedelta
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
TARGET_DIR       = Path("datahub_refinery/target")
RUN_RESULTS_PATH = TARGET_DIR / "run_results.json"
MANIFEST_PATH    = TARGET_DIR / "manifest.json"
OUTPUT_PATH      = Path("dbt_test_report.html")


def esc(value) -> str:
    return html.escape(str(value if value is not None else ""), quote=True)


def env_meta(key: str, fallback: str = "") -> str:
    return (os.environ.get(key) or fallback).strip()


def infer_layer(path: str, resource_type: str) -> str:
    p = (path or "").replace("\\", "/").lower()
    if resource_type == "snapshot" or "/snapshots/" in p:
        return "snapshot"
    if "/bronze" in p:
        return "bronze"
    if "/silver" in p:
        return "silver"
    if "/gold" in p:
        return "gold"
    if "/platinum" in p:
        return "platinum"
    if resource_type == "seed":
        return "seed"
    if resource_type == "test":
        return "test"
    return resource_type or "—"


def fmt_seconds(seconds) -> str:
    try:
        seconds = float(seconds or 0)
    except (TypeError, ValueError):
        return "—"
    if seconds >= 3600:
        h = int(seconds // 3600)
        m = int((seconds % 3600) // 60)
        s = int(seconds % 60)
        return f"{h}h {m}m {s}s"
    if seconds >= 60:
        m = int(seconds // 60)
        s = seconds % 60
        return f"{m}m {s:.1f}s"
    return f"{seconds:.2f}s"


def load_json(path: Path) -> dict:
    if not path.exists():
        print(f"[ERROR] File not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


# YAML-only / "nothing to build" runs never create run_results.json.
# Exit 0 so CI can still finish snow dbt deploy.
if not RUN_RESULTS_PATH.exists():
    print(f"[WARN] {RUN_RESULTS_PATH} not found — no dbt build ran; skipping HTML report.")
    sys.exit(0)

run_results = load_json(RUN_RESULTS_PATH)
manifest    = load_json(MANIFEST_PATH) if MANIFEST_PATH.exists() else {"nodes": {}}

# ── Parse results ──────────────────────────────────────────────────────────────
results        = run_results.get("results", [])
manifest_nodes = manifest.get("nodes", {})
elapsed_time   = run_results.get("elapsed_time")

# Snapshots/seeds fail independently of models; they must appear in the report
# or a green "PASSED" HTML artefact hides a red dbt build (DHE-3437 DATEKEY).
BUILD_PREFIXES = ("model.", "snapshot.", "seed.")
model_results = [
    r for r in results
    if any(r.get("unique_id", "").startswith(p) for p in BUILD_PREFIXES)
]
test_results  = [r for r in results if r.get("unique_id", "").startswith("test.")]

# ── Model / snapshot / seed rows ───────────────────────────────────────────────
model_rows = []
for r in model_results:
    uid       = r["unique_id"]
    node      = manifest_nodes.get(uid, {})
    name      = node.get("name") or uid.split(".")[-1]
    schema    = node.get("schema", "—")
    database  = node.get("database") or ""
    alias     = node.get("alias") or name
    node_type = node.get("resource_type", "model").capitalize()
    status    = r.get("status", "unknown")
    exec_time = r.get("execution_time", 0)
    message   = r.get("message") or ""
    adapter   = r.get("adapter_response") or {}
    rows_aff  = adapter.get("rows_affected")
    path      = node.get("original_file_path") or node.get("path") or ""
    materialized = (node.get("config") or {}).get("materialized") or "—"
    relation  = ".".join(p for p in (database, schema, alias) if p) or "—"
    model_rows.append({
        "model": name, "type": node_type, "schema": schema,
        "status": status, "exec_time": exec_time, "message": message,
        "relation": relation, "materialized": materialized,
        "layer": infer_layer(path, node.get("resource_type", "")),
        "path": path, "rows": rows_aff, "uid": uid,
    })

# Errors first, then alphabetically
model_rows.sort(key=lambda x: (x["status"] != "error", x["model"]))

# Model summary counts
m_total   = len(model_rows)
m_passed  = sum(1 for r in model_rows if r["status"] == "success")
m_errors  = sum(1 for r in model_rows if r["status"] == "error")
m_skipped = sum(1 for r in model_rows if r["status"] == "skipped")

# ── Test rows ──────────────────────────────────────────────────────────────────
test_rows = []
for r in test_results:
    uid       = r["unique_id"]
    node      = manifest_nodes.get(uid, {})
    test_name = node.get("name") or uid.split(".")[-1]
    attached  = node.get("attached_node", "") or ""
    model     = attached.split(".")[-1] if attached else "—"
    column    = node.get("column_name") or "—"
    test_type = node.get("test_metadata", {}).get("name") or node.get("resource_type", "test")
    status    = r.get("status", "unknown")
    exec_time = r.get("execution_time", 0)
    message   = r.get("message") or ""
    failures  = r.get("failures")
    path      = node.get("original_file_path") or node.get("path") or ""
    test_rows.append({
        "test_name": test_name, "model": model, "column": column,
        "test_type": test_type, "status": status,
        "exec_time": exec_time, "message": message,
        "failures": failures, "path": path, "uid": uid,
    })

# Failures first, then by model
test_rows.sort(key=lambda x: (x["status"] == "pass", x["model"], x["test_name"]))

# Test summary counts
t_total   = len(test_rows)
t_passed  = sum(1 for r in test_rows if r["status"] == "pass")
t_failed  = sum(1 for r in test_rows if r["status"] == "fail")
t_errored = sum(1 for r in test_rows if r["status"] == "error")
t_skipped = t_total - t_passed - t_failed - t_errored

# ── Overall status ─────────────────────────────────────────────────────────────
overall_failed = m_errors > 0 or t_failed > 0 or t_errored > 0
overall_status = "PASSED" if not overall_failed else "FAILED"
badge_color    = "#28a745" if overall_status == "PASSED" else "#dc3545"

_now_utc = datetime.now(timezone.utc)
_now_ist = _now_utc + timedelta(hours=5, minutes=30)
generated_at = f"{_now_ist.strftime('%Y-%m-%d %H:%M:%S IST')} / {_now_utc.strftime('%H:%M:%S GMT')}"
dbt_version  = run_results.get("metadata", {}).get("dbt_schema_version", "")

report_title    = env_meta("DBT_REPORT_TITLE")
report_env      = env_meta("DBT_REPORT_ENV")
report_branch   = env_meta("DBT_REPORT_BRANCH")
report_sha      = env_meta("DBT_REPORT_SHA")
report_actor    = env_meta("DBT_REPORT_ACTOR")
report_selector = env_meta("DBT_REPORT_SELECTOR") or "(entire project)"
report_exclude  = env_meta("DBT_REPORT_EXCLUDE") or "—"
report_reason   = env_meta("DBT_REPORT_REASON") or "—"
short_sha       = report_sha[:12] if report_sha else "—"

# ── Status icons (inline SVG — uniform 16 px, no emoji OS-rendering variance) ──
_S = 'width="16" height="16" viewBox="0 0 16 16" style="vertical-align:-3px;margin-right:4px;flex-shrink:0;"'
_SVG_OK   = (f'<svg {_S}><circle cx="8" cy="8" r="7.5" fill="#28a745"/>'
             f'<path d="M4.5 8.4 L6.8 10.8 L11.5 5.2" stroke="white" stroke-width="1.7"'
             f' stroke-linecap="round" stroke-linejoin="round" fill="none"/></svg>')
_SVG_FAIL = (f'<svg {_S}><circle cx="8" cy="8" r="7.5" fill="#dc3545"/>'
             f'<path d="M5.5 5.5 L10.5 10.5 M10.5 5.5 L5.5 10.5" stroke="white"'
             f' stroke-width="1.7" stroke-linecap="round" fill="none"/></svg>')
_SVG_SKIP = (f'<svg {_S}><circle cx="8" cy="8" r="7.5" fill="#6c757d"/>'
             f'<rect x="4.5" y="7.2" width="7" height="1.6" rx="0.8" fill="white"/></svg>')
_SVG_WARN = (f'<svg {_S}><circle cx="8" cy="8" r="7.5" fill="#e67e22"/>'
             f'<rect x="7.2" y="3.8" width="1.6" height="5.2" rx="0.8" fill="white"/>'
             f'<circle cx="8" cy="11.6" r="0.95" fill="white"/></svg>')
_SVG_UNKN = (f'<svg {_S}><circle cx="8" cy="8" r="7.5" fill="#adb5bd"/>'
             f'<path d="M6 6.5 Q6 4.5 8 4.5 Q10 4.5 10 6.5 Q10 8 8 8.5" stroke="white"'
             f' stroke-width="1.6" stroke-linecap="round" fill="none"/>'
             f'<circle cx="8" cy="11.2" r="0.9" fill="white"/></svg>')

MODEL_ICON = {"success": _SVG_OK, "error": _SVG_FAIL, "skipped": _SVG_SKIP}
TEST_ICON  = {"pass": _SVG_OK, "fail": _SVG_FAIL, "error": _SVG_WARN, "warn": _SVG_WARN, "skipped": _SVG_SKIP}
MODEL_CLS  = {"success": "pass", "error": "fail", "skipped": "skipped"}
TEST_CLS   = {"pass": "pass", "fail": "fail", "error": "error", "warn": "warn", "skipped": "skipped"}


def m_icon(s): return MODEL_ICON.get(s, _SVG_UNKN)
def t_icon(s): return TEST_ICON.get(s, _SVG_UNKN)
def m_cls(s):  return MODEL_CLS.get(s, "")
def t_cls(s):  return TEST_CLS.get(s, "")


def attention_hint(status: str, message: str) -> str:
    msg = (message or "").lower()
    if status == "error" and ("does not exist" in msg or "not authorized" in msg):
        return "Likely missing upstream table (not a selector typo if this node itself built)."
    if status == "error" and "number out of representative range" in msg:
        return "Column type too narrow for the value (snapshot table may need recreate/widen)."
    if status == "fail":
        return "Assertion failed (row count / accepted values / uniqueness). Check the message, not an exclude."
    if status == "error":
        return "Compile / database error — read the SQL message below."
    return ""


# ── Attention panel ────────────────────────────────────────────────────────────
attention_items = []
for row in model_rows:
    if row["status"] in ("error",):
        attention_items.append(("build", row["status"], row["model"], row["relation"], row["message"], row["uid"]))
for row in test_rows:
    if row["status"] in ("fail", "error"):
        attention_items.append(("test", row["status"], row["test_name"], row["model"], row["message"], row["uid"]))

attention_html = ""
if attention_items:
    cards = []
    for kind, status, name, extra, message, uid in attention_items:
        hint = attention_hint(status, message)
        cards.append(f"""
        <div class="attn-card {esc(status)}">
          <div class="attn-head">
            <span class="attn-kind">{esc(kind)} · {esc(status).upper()}</span>
            <code>{esc(name)}</code>
            <span class="attn-extra">{esc(extra)}</span>
          </div>
          {f'<div class="attn-hint">{esc(hint)}</div>' if hint else ''}
          <pre class="attn-msg">{esc(message) or '(no message)'}</pre>
        </div>""")
    attention_html = f"""
  <div class="attention">
    <div class="summary-label">Needs attention ({len(attention_items)})</div>
    <p class="attn-note">
      <strong>ERROR</strong> = compile / missing object / warehouse issue.
      <strong>FAIL</strong> = the test ran and the data did not meet the assertion.
      Do not <code>--exclude</code> a FAIL unless a DE has confirmed it is expected.
    </p>
    {''.join(cards)}
  </div>"""

# ── Meta bar ───────────────────────────────────────────────────────────────────
meta_cells = []
if report_title:
    meta_cells.append(("Run title", report_title))
if report_env:
    meta_cells.append(("Environment", report_env))
if report_branch:
    meta_cells.append(("Branch", report_branch))
meta_cells.append(("Commit", short_sha))
if report_actor:
    meta_cells.append(("Triggered by", report_actor))
meta_cells.append(("Elapsed", fmt_seconds(elapsed_time) if elapsed_time is not None else "—"))
meta_cells.append(("Selector", report_selector))
meta_cells.append(("Exclude", report_exclude))
if report_reason and report_reason != "—":
    meta_cells.append(("Reason", report_reason))

meta_html = "".join(
    f'<div class="meta-cell"><div class="meta-k">{esc(k)}</div><div class="meta-v">{esc(v)}</div></div>'
    for k, v in meta_cells
)

# ── Model table rows ───────────────────────────────────────────────────────────
model_table_html = ""
for row in model_rows:
    sc  = m_cls(row["status"])
    msg = f'<span class="msg">{esc(row["message"])}</span>' if row["message"] else ""
    rows_txt = "—" if row["rows"] is None else esc(row["rows"])
    model_table_html += f"""
      <tr class="{sc}" data-status="{esc(row["status"])}" data-search="{esc((row['model']+' '+row['relation']+' '+row['path']+' '+(row['message'] or '')).lower())}">
        <td>{m_icon(row["status"])} <code>{esc(row["model"])}</code></td>
        <td>{esc(row["type"])}</td>
        <td>{esc(row["layer"])}</td>
        <td>{esc(row["materialized"])}</td>
        <td><code>{esc(row["relation"])}</code></td>
        <td class="status-cell {sc}">{esc(row["status"].upper())}</td>
        <td>{rows_txt}</td>
        <td>{row["exec_time"]:.2f}s</td>
        <td>{msg}</td>
      </tr>"""

# ── Test table rows ────────────────────────────────────────────────────────────
test_table_html = ""
for row in test_rows:
    sc  = t_cls(row["status"])
    msg = f'<span class="msg">{esc(row["message"])}</span>' if row["message"] else ""
    fail_txt = "—" if row["failures"] is None else esc(row["failures"])
    test_table_html += f"""
      <tr class="{sc}" data-status="{esc(row["status"])}" data-search="{esc((row['test_name']+' '+row['model']+' '+row['column']+' '+(row['message'] or '')).lower())}">
        <td>{t_icon(row["status"])} <code>{esc(row["test_name"])}</code></td>
        <td><code>{esc(row["model"])}</code></td>
        <td>{esc(row["column"])}</td>
        <td>{esc(row["test_type"])}</td>
        <td class="status-cell {sc}">{esc(row["status"].upper())}</td>
        <td>{fail_txt}</td>
        <td>{row["exec_time"]:.2f}s</td>
        <td>{msg}</td>
      </tr>"""

header_sub = esc(report_title) if report_title else "dbt Build Report"

# ── Full HTML ──────────────────────────────────────────────────────────────────
html_out = f"""<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>{header_sub}</title>
  <link rel="preconnect" href="https://fonts.googleapis.com"/>
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin/>
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet"/>
  <style>
    *, *::before, *::after {{ box-sizing: border-box; margin: 0; padding: 0; }}
    body {{
      font-family: 'Inter', -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      background: #f5f7fa; color: #212529; font-size: 14px;
    }}
    header {{
      background: linear-gradient(90deg, #3D0F6E 0%, #8B2FC9 35%, #D44000 70%, #FF6200 100%);
      color: #fff; padding: 24px 32px;
      display: flex; align-items: center; justify-content: space-between;
    }}
    header h1 {{
      font-size: 24px; font-weight: 800; letter-spacing: -.3px;
      display: flex; align-items: center; gap: 12px;
    }}
    header .meta {{ font-size: 13px; color: #fff; text-align: right; line-height: 1.9; font-weight: 500; }}
    .badge {{
      display: inline-block; padding: 6px 18px; border-radius: 20px;
      font-weight: 700; font-size: 15px; background: {badge_color}; color: #fff;
      letter-spacing: 1px;
    }}
    .run-title {{ margin-top: 8px; font-size: 15px; font-weight: 600; opacity: .95; }}
    .meta-bar {{
      display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
      gap: 10px; padding: 16px 32px; background: #fff; border-bottom: 1px solid #e0e4ed;
    }}
    .meta-cell {{ background: #f7f8fc; border-radius: 8px; padding: 10px 12px; }}
    .meta-k {{ font-size: 10px; font-weight: 700; letter-spacing: .8px; text-transform: uppercase; color: #6b7280; }}
    .meta-v {{ margin-top: 4px; font-size: 13px; font-weight: 600; word-break: break-word; }}
    .attention {{ padding: 18px 32px 8px; background: #fff8f4; border-bottom: 1px solid #f0d9cc; }}
    .attn-note {{ font-size: 13px; color: #5c3d2e; margin-bottom: 12px; }}
    .attn-card {{
      background: #fff; border-radius: 10px; padding: 12px 14px; margin-bottom: 10px;
      border-left: 4px solid #dc3545; box-shadow: 0 1px 4px rgba(0,0,0,.06);
    }}
    .attn-card.error {{ border-left-color: #e67e22; }}
    .attn-head {{ display: flex; flex-wrap: wrap; gap: 8px; align-items: baseline; }}
    .attn-kind {{ font-size: 11px; font-weight: 800; letter-spacing: .6px; color: #9b1c1c; }}
    .attn-extra {{ color: #6b7280; font-size: 12px; }}
    .attn-hint {{ margin-top: 6px; font-size: 12px; color: #7c2d12; font-weight: 600; }}
    .attn-msg {{
      margin-top: 8px; white-space: pre-wrap; font-size: 12px;
      font-family: "SFMono-Regular", Consolas, monospace; color: #7f1d1d;
      background: #fff5f5; padding: 8px; border-radius: 6px; overflow-x: auto;
    }}
    .toolbar {{
      display: flex; gap: 10px; flex-wrap: wrap; align-items: center;
      padding: 14px 32px 0;
    }}
    .toolbar input {{
      flex: 1; min-width: 220px; padding: 8px 12px; border: 1px solid #d5d9e3;
      border-radius: 8px; font-size: 13px;
    }}
    .chip {{
      border: 1px solid #d5d9e3; background: #fff; border-radius: 999px;
      padding: 6px 12px; font-size: 12px; font-weight: 600; cursor: pointer;
    }}
    .chip.active {{ background: #3D0F6E; color: #fff; border-color: #3D0F6E; }}
    .summary-section {{
      background: linear-gradient(135deg, #fafbff 0%, #f4f6fb 100%);
      padding: 22px 32px;
      border-bottom: 1px solid #e0e4ed;
    }}
    .summary-section + .summary-section {{ border-top: none; }}
    .summary-label {{
      font-size: 12px; font-weight: 800; text-transform: uppercase;
      letter-spacing: 1.8px; color: #1a1f3c; margin-bottom: 14px;
      display: flex; align-items: center; gap: 10px;
    }}
    .summary-label::before {{
      content: '';
      display: inline-block;
      width: 4px; height: 16px;
      background: linear-gradient(180deg, #8B2FC9, #FF6200);
      border-radius: 2px;
      flex-shrink: 0;
    }}
    .summary {{
      display: flex; gap: 14px; flex-wrap: wrap;
    }}
    .stat-card {{
      flex: 1; min-width: 110px; border-radius: 12px; padding: 16px 20px;
      text-align: center;
      box-shadow: 0 2px 10px rgba(0,0,0,.10);
      border-top: 3px solid transparent;
      transition: transform .15s ease, box-shadow .15s ease;
    }}
    .stat-card:hover {{
      transform: translateY(-2px);
      box-shadow: 0 6px 18px rgba(0,0,0,.13);
    }}
    .stat-card .num {{ font-size: 30px; font-weight: 800; }}
    .stat-card .lbl {{ font-size: 11px; color: #555; margin-top: 5px; text-transform: uppercase; letter-spacing: .8px; font-weight: 600; }}
    .card-total   {{ background: #f0f4ff; border-top-color: #3D0F6E; }}
    .card-passed  {{ background: #eafaf1; border-top-color: #28a745; }}
    .card-failed  {{ background: #fdf0f0; border-top-color: #dc3545; }}
    .card-error   {{ background: #fff8e1; border-top-color: #e67e22; }}
    .card-skipped {{ background: #f2f3f4; border-top-color: #6c757d; }}
    .total-num  {{ color: #1a1f3c; }}
    .pass-num   {{ color: #28a745; }}
    .fail-num   {{ color: #dc3545; }}
    .error-num  {{ color: #e67e22; }}
    .skip-num   {{ color: #6c757d; }}
    .table-wrap {{ padding: 24px 32px; }}
    h2 {{ font-size: 16px; font-weight: 600; margin-bottom: 14px; color: #1a1f3c; }}
    h2 .count {{ font-weight: 400; color: #888; }}
    table {{
      width: 100%; border-collapse: collapse; background: #fff;
      border-radius: 10px; overflow: hidden;
      box-shadow: 0 1px 6px rgba(0,0,0,.08);
    }}
    thead {{ background: linear-gradient(90deg, #3D0F6E 0%, #8B2FC9 35%, #D44000 70%, #FF6200 100%); color: #fff; }}
    th {{
      padding: 12px 14px; text-align: left; font-size: 12px;
      text-transform: uppercase; letter-spacing: .6px; font-weight: 600;
    }}
    td {{ padding: 10px 14px; border-bottom: 1px solid #eef0f5; vertical-align: top; }}
    tr:last-child td {{ border-bottom: none; }}
    tr.fail    {{ background: #fff5f5; }}
    tr.error   {{ background: #fffbf0; }}
    tr.skipped {{ background: #f8f9fa; }}
    tr:hover   {{ background: #f0f4ff; cursor: default; }}
    tr.hidden  {{ display: none; }}
    code {{
      font-size: 12px; background: #eef0f6; padding: 2px 5px;
      border-radius: 4px; font-family: "SFMono-Regular", Consolas, monospace;
    }}
    .status-cell {{ font-weight: 700; font-size: 12px; }}
    .status-cell.pass    {{ color: #28a745; }}
    .status-cell.fail    {{ color: #dc3545; }}
    .status-cell.error   {{ color: #e67e22; }}
    .status-cell.skipped {{ color: #6c757d; }}
    .msg {{
      color: #c0392b; font-size: 12px; white-space: pre-wrap;
      font-family: "SFMono-Regular", Consolas, monospace;
    }}
    footer {{
      text-align: center; padding: 18px; color: #999; font-size: 12px;
      border-top: 1px solid #e0e4ed;
    }}
  </style>
</head>
<body>
  <header>
    <div>
      <h1>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="40" height="40" style="flex-shrink:0;">
          <path d="M17.4,9.594A7.473,7.473,0,0,0,14.61,6.732l1.624.769a9.434,9.434,0,0,1,3.43,2.752L22.63,4.815A2.618,2.618,0,0,0,22.574,2.1a2.5,2.5,0,0,0-3.271-.8L13.915,4.244a4,4,0,0,1-3.83,0L4.814,1.369A2.618,2.618,0,0,0,2.1,1.427a2.5,2.5,0,0,0-.8,3.27l2.939,5.387a4,4,0,0,1,0,3.831L1.371,19.182a2.623,2.623,0,0,0,.078,2.749A2.5,2.5,0,0,0,4.7,22.7l5.556-3.031A9.434,9.434,0,0,1,7.5,16.234L6.732,14.61A7.473,7.473,0,0,0,9.594,17.4L19.3,22.7a2.5,2.5,0,0,0,3.249-.767,2.632,2.632,0,0,0,.073-2.753ZM20.5,2.5a1,1,0,1,1-1,1A1,1,0,0,1,20.5,2.5Zm-17,2a1,1,0,1,1,1-1A1,1,0,0,1,3.5,4.5Zm0,17a1,1,0,1,1,1-1A1,1,0,0,1,3.5,21.5ZM13,11a1.994,1.994,0,0,0-1.353,3.464,2.494,2.494,0,1,1,2.817-2.817A1.983,1.983,0,0,0,13,11Zm7.5,10.5a1,1,0,1,1,1-1A1,1,0,0,1,20.5,21.5Z" fill="#fff"/>
        </svg>
        dbt Build Report
      </h1>
      {f'<div class="run-title">{esc(report_title)}</div>' if report_title else ''}
      <div style="margin-top:8px"><span class="badge">{overall_status}</span></div>
    </div>
    <div class="meta">
      Generated: {esc(generated_at)}<br>
      dbt schema: {esc(dbt_version)}<br>
      Built: {m_total} | Tests: {t_total}
    </div>
  </header>

  <div class="meta-bar">
    {meta_html}
  </div>

  {attention_html}

  <div class="summary-section">
    <div class="summary-label">Models / snapshots / seeds</div>
    <div class="summary">
      <div class="stat-card card-total">
        <div class="num total-num">{m_total}</div>
        <div class="lbl">Total</div>
      </div>
      <div class="stat-card card-passed">
        <div class="num pass-num">{m_passed}</div>
        <div class="lbl">Passed</div>
      </div>
      <div class="stat-card card-failed">
        <div class="num fail-num">{m_errors}</div>
        <div class="lbl">Errors</div>
      </div>
      <div class="stat-card card-skipped">
        <div class="num skip-num">{m_skipped}</div>
        <div class="lbl">Skipped</div>
      </div>
    </div>
  </div>

  <div class="summary-section">
    <div class="summary-label">Tests</div>
    <div class="summary">
      <div class="stat-card card-total">
        <div class="num total-num">{t_total}</div>
        <div class="lbl">Total</div>
      </div>
      <div class="stat-card card-passed">
        <div class="num pass-num">{t_passed}</div>
        <div class="lbl">Passed</div>
      </div>
      <div class="stat-card card-failed">
        <div class="num fail-num">{t_failed}</div>
        <div class="lbl">Failed</div>
      </div>
      <div class="stat-card card-error">
        <div class="num error-num">{t_errored}</div>
        <div class="lbl">Errors</div>
      </div>
      <div class="stat-card card-skipped">
        <div class="num skip-num">{t_skipped}</div>
        <div class="lbl">Skipped</div>
      </div>
    </div>
  </div>

  <div class="toolbar">
    <input id="q" type="search" placeholder="Search models, tests, relations, messages…"/>
    <button class="chip active" data-filter="all" type="button">All</button>
    <button class="chip" data-filter="problems" type="button">Problems only</button>
    <button class="chip" data-filter="fail" type="button">FAIL</button>
    <button class="chip" data-filter="error" type="button">ERROR</button>
  </div>

  <div class="table-wrap">
    <h2>Build Results <span class="count">{m_total}</span></h2>
    <table>
      <thead>
        <tr>
          <th>Name</th>
          <th>Type</th>
          <th>Layer</th>
          <th>Materialized</th>
          <th>Relation</th>
          <th>Status</th>
          <th>Rows</th>
          <th>Time</th>
          <th>Message</th>
        </tr>
      </thead>
      <tbody>
        {model_table_html}
      </tbody>
    </table>
  </div>

  <div class="table-wrap">
    <h2>Schema Test Results <span class="count">{t_total}</span></h2>
    <table>
      <thead>
        <tr>
          <th>Test Name</th>
          <th>Model</th>
          <th>Column</th>
          <th>Test Type</th>
          <th>Status</th>
          <th>Failing rows</th>
          <th>Time</th>
          <th>Message</th>
        </tr>
      </thead>
      <tbody>
        {test_table_html}
      </tbody>
    </table>
  </div>

  <footer>
    Generated by dbt_report.py &mdash; dbt native build results
  </footer>
  <script>
    (function () {{
      const q = document.getElementById('q');
      const chips = document.querySelectorAll('.chip');
      let filter = 'all';
      function apply() {{
        const term = (q.value || '').trim().toLowerCase();
        document.querySelectorAll('tbody tr').forEach(function (tr) {{
          const status = tr.getAttribute('data-status') || '';
          const search = tr.getAttribute('data-search') || '';
          let ok = true;
          if (filter === 'problems') ok = (status === 'fail' || status === 'error');
          else if (filter === 'fail') ok = status === 'fail';
          else if (filter === 'error') ok = status === 'error';
          if (term && search.indexOf(term) === -1) ok = false;
          tr.classList.toggle('hidden', !ok);
        }});
      }}
      q.addEventListener('input', apply);
      chips.forEach(function (chip) {{
        chip.addEventListener('click', function () {{
          chips.forEach(function (c) {{ c.classList.remove('active'); }});
          chip.classList.add('active');
          filter = chip.getAttribute('data-filter');
          apply();
        }});
      }});
    }})();
  </script>
</body>
</html>
"""

# ── Write output ───────────────────────────────────────────────────────────────
OUTPUT_PATH.write_text(html_out, encoding="utf-8")
print(f"[OK] Report written to: {OUTPUT_PATH.resolve()}")
print(f"     Built  - Total: {m_total} | Passed: {m_passed} | Errors: {m_errors} | Skipped: {m_skipped}")
print(f"     Tests  - Total: {t_total} | Passed: {t_passed} | Failed: {t_failed} | Errors: {t_errored} | Skipped: {t_skipped}")
