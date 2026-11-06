#!/usr/bin/env python3
"""
POC: connect to Snowflake with the same env secrets used by dbt CI.

Required env vars (from GitHub Environment secrets):
  SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_ROLE,
  SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DB, SNOWFLAKE_SCHEMA,
  SNOWFLAKE_PRIVATE_KEY_PATH  (path to PEM file written by the workflow)
  SNOWFLAKE_KEY_PASSPHRASE    (optional if the key is unencrypted)

Usage:
  python scripts/poc_snowflake_connect.py
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

import snowflake.connector
from cryptography.hazmat.backends import default_backend
from cryptography.hazmat.primitives import serialization


def _require(name: str) -> str:
    value = (os.environ.get(name) or "").strip()
    if not value:
        raise SystemExit(f"Missing required env var: {name}")
    return value


def load_private_key(path: str, passphrase: str | None):
    key_bytes = Path(path).read_bytes()
    password = passphrase.encode() if passphrase else None
    p_key = serialization.load_pem_private_key(
        key_bytes,
        password=password,
        backend=default_backend(),
    )
    return p_key.private_bytes(
        encoding=serialization.Encoding.DER,
        format=serialization.PrivateFormat.PKCS8,
        encryption_algorithm=serialization.NoEncryption(),
    )


def main() -> int:
    account = _require("SNOWFLAKE_ACCOUNT")
    user = _require("SNOWFLAKE_USER")
    role = _require("SNOWFLAKE_ROLE")
    warehouse = _require("SNOWFLAKE_WAREHOUSE")
    database = _require("SNOWFLAKE_DB")
    schema = _require("SNOWFLAKE_SCHEMA")
    key_path = _require("SNOWFLAKE_PRIVATE_KEY_PATH")
    passphrase = (os.environ.get("SNOWFLAKE_KEY_PASSPHRASE") or "").strip() or None

    print("Connecting to Snowflake…")
    print(f"  account   = {account}")
    print(f"  user      = {user}")
    print(f"  role      = {role}")
    print(f"  warehouse = {warehouse}")
    print(f"  database  = {database}")
    print(f"  schema    = {schema}")

    conn = snowflake.connector.connect(
        account=account,
        user=user,
        role=role,
        warehouse=warehouse,
        database=database,
        schema=schema,
        private_key=load_private_key(key_path, passphrase),
        authenticator="SNOWFLAKE_JWT",
    )

    try:
        cur = conn.cursor()
        cur.execute(
            "SELECT CURRENT_ACCOUNT(), CURRENT_USER(), CURRENT_ROLE(), "
            "CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA(), CURRENT_TIMESTAMP()"
        )
        row = cur.fetchone()
        labels = (
            "CURRENT_ACCOUNT",
            "CURRENT_USER",
            "CURRENT_ROLE",
            "CURRENT_WAREHOUSE",
            "CURRENT_DATABASE",
            "CURRENT_SCHEMA",
            "CURRENT_TIMESTAMP",
        )
        print("Connection OK:")
        for label, value in zip(labels, row):
            print(f"  {label} = {value}")
        cur.close()
    finally:
        conn.close()

    print("POC succeeded.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
