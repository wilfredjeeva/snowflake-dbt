#!/usr/bin/env python3
"""Example team script — copy this folder pattern for your own job."""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # scripts/
from python_jobs.sf_connect import connect


def main() -> int:
    conn = connect()
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT
                'hello_select' AS SCRIPT,
                CURRENT_USER() AS SF_USER,
                CURRENT_ROLE() AS SF_ROLE,
                CURRENT_TIMESTAMP() AS RAN_AT
            """
        )
        cols = [d[0] for d in cur.description]
        row = cur.fetchone()
        print(" | ".join(cols))
        print(" | ".join(str(v) for v in row))
        cur.close()
    finally:
        conn.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
