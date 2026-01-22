import pandas as pd
import numpy as np
from pathlib import Path

def save_positional_row_diffs_to_excel(
    bronze_df: pd.DataFrame,
    landing_df: pd.DataFrame,
    out_path: str,
    *,
    summary_sheet: str = "summary",
    details_sheet: str = "details",
    bronze_sheet: str | None = "bronze_details",
    landing_sheet: str | None = "landing_details",
):
    # -----------------------------
    # 0) Resolve output path
    # -----------------------------
    out_path = Path(out_path)

    # If caller passes only a filename or relative path, write into ./output/
    if not out_path.is_absolute():
        output_dir = Path.cwd() / "output"
        output_dir.mkdir(parents=True, exist_ok=True)
        out_path = output_dir / out_path
    else:
        # If absolute path was provided, ensure its parent exists
        out_path.parent.mkdir(parents=True, exist_ok=True)

    # -----------------------------
    # 1) Normalize columns & length
    # -----------------------------
    common_cols = sorted(set(bronze_df.columns).union(set(landing_df.columns)))

    b = bronze_df.reindex(columns=common_cols).reset_index(drop=True)
    l = landing_df.reindex(columns=common_cols).reset_index(drop=True)

    bronze_count = len(b)
    landing_count = len(l)

    max_len = max(bronze_count, landing_count)
    b = b.reindex(range(max_len))
    l = l.reindex(range(max_len))

    # -----------------------------
    # 2) Compare positionally
    # -----------------------------
    neq = b.ne(l) & ~(b.isna() & l.isna())
    diff_rows_mask = neq.any(axis=1)
    diff_positions = np.flatnonzero(diff_rows_mask)

    # -----------------------------
    # 3) Extract diff rows
    # -----------------------------
    bronze_diff_rows = b.loc[diff_positions].copy()
    landing_diff_rows = l.loc[diff_positions].copy()

    bronze_diff_rows.insert(0, "_row_pos", diff_positions)
    landing_diff_rows.insert(0, "_row_pos", diff_positions)

    # -----------------------------
    # 4) Row-level summary
    # -----------------------------
    diff_columns = (
        neq.loc[diff_positions]
        .apply(lambda r: ", ".join(r.index[r.values]), axis=1)
    )

    diff_count = neq.loc[diff_positions].sum(axis=1).astype(int)

    row_summary = pd.DataFrame({
        "_row_pos": diff_positions,
        "diff_count": diff_count.values,
        "diff_columns": diff_columns.values
    })

    # -----------------------------
    # 5) Dataset-level metrics
    # -----------------------------
    metrics = pd.DataFrame({
        "metric": [
            "Bronze record count",
            "Landing record count",
            "Row count difference (Bronze - Landing)",
            "Total mismatched rows",
            "Difference description"
        ],
        "value": [
            bronze_count,
            landing_count,
            bronze_count - landing_count,
            len(diff_positions),
            (
                "Row count differs and/or column values differ at same row positions"
                if bronze_count != landing_count
                else "Row counts match; differences are due to column value mismatches"
            )
        ]
    })

    # -----------------------------
    # 6) Details sheet (side-by-side)
    # -----------------------------
    details = pd.concat(
        [
            bronze_diff_rows.add_prefix("bronze_"),
            landing_diff_rows.add_prefix("landing_")
        ],
        axis=1
    )

    # -----------------------------
    # 7) Write to Excel
    # -----------------------------
    with pd.ExcelWriter(str(out_path), engine="openpyxl") as writer:
        metrics.to_excel(writer, sheet_name=summary_sheet, index=False, startrow=0)

        row_summary.to_excel(
            writer,
            sheet_name=summary_sheet,
            index=False,
            startrow=len(metrics) + 2
        )

        details.to_excel(writer, sheet_name=details_sheet, index=False)

        if bronze_sheet:
            bronze_diff_rows.to_excel(writer, sheet_name=bronze_sheet, index=False)

        if landing_sheet:
            landing_diff_rows.to_excel(writer, sheet_name=landing_sheet, index=False)

    return {
        "bronze_count": bronze_count,
        "landing_count": landing_count,
        "diff_row_count": int(len(diff_positions)),
        "diff_positions": diff_positions.tolist(),
        "excel_path": str(out_path)
    }
