
# src/sf_client.py
import snowflake.connector

class SnowflakeClient:
    def __init__(self, account, user, password, role=None, warehouse=None, database=None, schema=None,
                 host=None, disable_ocsp_checks=False):
        self._conn = None
        self.config = {
            "account": account,
            "user": user,
            "password": password,
            "role": role,
            "warehouse": warehouse,
            "database": database,
            "schema": schema,
        }
        # host usually derived from account; only set if you truly need it
        self.host = host
        self.disable_ocsp_checks = disable_ocsp_checks

    def connect(self):
        # Optionally manage OCSP/insecure mode via connector parameters if needed
        self._conn = snowflake.connector.connect(**{k:v for k,v in self.config.items() if v})

    def close(self):
        if self._conn:
            self._conn.close()
            self._conn = None

    def cursor(self):
        if not self._conn:
            raise RuntimeError("Not connected")
        return self._conn.cursor()

    def query(self, sql, params=None):
        """Return list of rows (tuples). Adjust if you prefer returning a cursor."""
        cur = self.cursor()
        cur.execute(sql, params=params or {})
        rows = cur.fetchall()
        cur.close()
        return rows

    def get_count(self, fully_qualified_table_name):
        rows = self.query(f"SELECT COUNT(*) AS C FROM {fully_qualified_table_name}")
        return rows[0][0]