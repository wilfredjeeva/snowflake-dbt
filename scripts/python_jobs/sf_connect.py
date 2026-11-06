"""Shared Snowflake key-pair connector for CI Python jobs.

Env vars (set by GitHub Actions from Environment secrets):
  SNOWFLAKE_ACCOUNT, SNOWFLAKE_USER, SNOWFLAKE_ROLE,
  SNOWFLAKE_WAREHOUSE, SNOWFLAKE_DB, SNOWFLAKE_SCHEMA,
  SNOWFLAKE_PRIVATE_KEY_PATH, SNOWFLAKE_KEY_PASSPHRASE (optional)
"""

from __future__ import annotations

import os
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


def connect():
    """Return an open snowflake.connector connection using CI secrets."""
    passphrase = (os.environ.get("SNOWFLAKE_KEY_PASSPHRASE") or "").strip() or None
    return snowflake.connector.connect(
        account=_require("SNOWFLAKE_ACCOUNT"),
        user=_require("SNOWFLAKE_USER"),
        role=_require("SNOWFLAKE_ROLE"),
        warehouse=_require("SNOWFLAKE_WAREHOUSE"),
        database=_require("SNOWFLAKE_DB"),
        schema=_require("SNOWFLAKE_SCHEMA"),
        private_key=load_private_key(_require("SNOWFLAKE_PRIVATE_KEY_PATH"), passphrase),
        authenticator="SNOWFLAKE_JWT",
    )
