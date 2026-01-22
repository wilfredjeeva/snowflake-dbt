import logging
from Data.variables import *
from bronze_adf.support import *

logger = logging.getLogger(__name__)
if not logger.handlers:
    # Basic configuration only if no handlers are present
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")


def get_row_count(cursor, table_full_name) -> int:
    query = f"SELECT COUNT(*) FROM {table_full_name}"
    cursor.execute(query)
    row = cursor.fetchone()
    print(row)

    if row[0] == 0:
        logger.warning("⚠️ Table %s has no records (COUNT(*) = 0).", table_full_name)

    if row is None or len(row) < 1:
        raise ValueError(f"Unexpected COUNT(*). Result for table {table_full_name}: {row}")
    return int(row[0])


def compare_row_counts(cursor, source_table, target_table):
    lcount = get_row_count(cursor, source_table)
    bcount = get_row_count(cursor, target_table)
    diff = abs(lcount - bcount)

    assert lcount == bcount, (f"❌ Row count difference {diff} : " f"Landing Count={lcount}, Bronze Count={bcount}")
    print(f"✅ Success: Row counts match! landing table count={lcount}, bronze table count={bcount}")


def compare_data(cursor, source_query, landing_table, target_query, bronze_table):
    cursor.execute(source_query, (landing_table,))
    landing_df = cursor.fetch_pandas_all()
    cursor.execute(target_query, (bronze_table,))
    bronze_df = cursor.fetch_pandas_all()
    res = save_positional_row_diffs_to_excel(bronze_df, landing_df, "/tmp/diff_oo_NEW.xlsx")
    print(res)

def check_metadata(cursor,schema_table_name,table_name,expected_column_datatype):
    query = f"SELECT column_name,data_type from {schema_table_name} where table_name='{table_name}' order by ordinal_position;"
    cursor.execute(query)
    actual_schema_df = cursor.fetch_pandas_all()
    actual_dict = dict(zip(actual_schema_df["COLUMN_NAME"], actual_schema_df["DATA_TYPE"]))
    print("Actual Schema:", actual_dict)
    print(expected_column_datatype)
    assert    actual_dict == expected_column_datatype, (f"❌ Metadata is not matching as expected ")
    print(f"✅ Success: MetaData matched!")