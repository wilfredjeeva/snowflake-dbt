
# ---------------------------
# Fully qualified table names
# ---------------------------
BRONZE_TABLE = "DEV_BRONZE_ADF.AIRBNB.AIRBNBDRIVERS"      # <-- set your real Bronze FQN
SILVER_TABLE = "DEV_SILVER_ADF.AIRBNB.AIRBNBDRIVERS"      # <-- as you created

# ---------------------------
# Hash expression using QUOTED column names (case-sensitive)
# ---------------------------
HASH_SELECT_EXPR_QUOTED = """
MD5(UPPER(CONCAT_WS(
  '|',
  COALESCE(TRIM(CAST("code" AS STRING)), ''),
  COALESCE(TRIM(CAST("dob" AS STRING)), ''),
  COALESCE(TRIM(CAST("driverId" AS STRING)), ''),
  COALESCE(TRIM(CAST("driverRef" AS STRING)), ''),
  COALESCE(TRIM(CAST("forename" AS STRING)), ''),
  COALESCE(TRIM(CAST("surname" AS STRING)), ''),
  COALESCE(TRIM(CAST("nationality" AS STRING)), ''),
  COALESCE(TRIM(CAST("number" AS STRING)), ''),
  COALESCE(TRIM(CAST("url" AS STRING)), '')
)))
"""

BRONZE_HASH_QUERY = f"""
SELECT {HASH_SELECT_EXPR_QUOTED} AS HASH_KEY
FROM IDENTIFIER(%s)
"""

SILVER_HASH_QUERY = BRONZE_HASH_QUERY  # same expression & columns

# Recompute with business key to compare Bronze vs Silver (assumes "driverId" is the join key)
BRONZE_RECOMPUTE_WITH_KEY = f"""
SELECT
  "driverId" AS driverId,
  {HASH_SELECT_EXPR_QUOTED} AS HASH_KEY
FROM IDENTIFIER(%s)
"""

SILVER_RECOMPUTE_WITH_KEY = BRONZE_RECOMPUTE_WITH_KEY

# ---------------------------
# Helpers
# ---------------------------
def fetch_df(cursor, query, table):
    cursor.execute(query, (table,))
    return cursor.fetch_pandas_all()

# ---------------------------
# Test 1: Uniqueness in each layer
# ---------------------------
def test_hash_uniqueness_bronze_silver(sf_conn):
    bronze_df = fetch_df(sf_conn, BRONZE_HASH_QUERY, BRONZE_TABLE)
    silver_df = fetch_df(sf_conn, SILVER_HASH_QUERY, SILVER_TABLE)

    assert "HASH_KEY" in bronze_df.columns, "Bronze query did not return HASH_KEY"
    assert "HASH_KEY" in silver_df.columns, "Silver query did not return HASH_KEY"

    assert bronze_df["HASH_KEY"].duplicated().sum() == 0, \
        "❌ Duplicate HASH_KEY values found in Bronze layer."
    assert silver_df["HASH_KEY"].duplicated().sum() == 0, \
        "❌ Duplicate HASH_KEY values found in Silver layer."

    print("✅ Hash uniqueness verified in both Bronze and Silver layers.")

# ---------------------------
# Test 2: Set integrity Bronze → Silver
# ---------------------------
def test_bronze_silver_hash_integrity(sf_conn):
    bronze_hashes = set(fetch_df(sf_conn, BRONZE_HASH_QUERY, BRONZE_TABLE)["HASH_KEY"])
    silver_hashes = set(fetch_df(sf_conn, SILVER_HASH_QUERY, SILVER_TABLE)["HASH_KEY"])

    extra_in_silver = silver_hashes - bronze_hashes
    missing_in_silver = bronze_hashes - silver_hashes

    assert len(extra_in_silver) == 0, \
        f"❌ Silver has extra hash keys not present in Bronze: {list(extra_in_silver)[:10]}"
    assert len(missing_in_silver) == 0, \
        f"❌ Silver is missing hash keys present in Bronze: {list(missing_in_silver)[:10]}"

    print("✅ Bronze → Silver hash integrity validated.")

# ---------------------------
# Test 3: Recompute across layers and compare by driverId
# (no stored HASH_KEY needed)
# ---------------------------
def test_recomputed_hash_matches_between_layers(sf_conn):
    bronze_df = fetch_df(sf_conn, BRONZE_RECOMPUTE_WITH_KEY, BRONZE_TABLE)
    silver_df = fetch_df(sf_conn, SILVER_RECOMPUTE_WITH_KEY, SILVER_TABLE)

    # Join by driverId and compare hashes
    merged = bronze_df.merge(silver_df, on="driverId", suffixes=("_bronze", "_silver"))

    # If join count mismatches, show helpful diagnostics
    if len(merged) != len(bronze_df) or len(merged) != len(silver_df):
        bronze_keys = set(bronze_df["driverId"])
        silver_keys = set(silver_df["driverId"])
        missing_in_silver = bronze_keys - silver_keys
        extra_in_silver = silver_keys - bronze_keys
        assert False, (
            "❌ Mismatch in driverId coverage between Bronze and Silver.\n"
            f"- Missing in Silver (sample): {list(missing_in_silver)[:10]}\n"
            f"- Extra in Silver (sample): {list(extra_in_silver)[:10]}"
        )

    mismatches = merged[merged["HASH_KEY_bronze"] != merged["HASH_KEY_silver"]]
    assert mismatches.empty, (
        "❌ Recomputed hash differs between Bronze and Silver for some driverId(s).\n"
        f"Sample:\n{mismatches.head(10).to_string(index=False)}"
    )

    print("✅ Recomputed HASH_KEY matches between Bronze and Silver by driverId.")
