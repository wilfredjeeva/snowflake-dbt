from utils import *

def compare_row_counts_activeRows(cursor, source_table, target_table):
    bcount = get_row_count(cursor, source_table)
    scount = get_row_count_activeRows(cursor, target_table)
    diff = abs(bcount - scount)

    assert scount == bcount, (f"❌ Row count difference {diff} : " f"Bronze Count={bcount}, Silver Count={scount}")
    print(f"✅ Success: Row counts match! Bronze table count={bcount}, Silver table count={scount}")

def get_row_count_activeRows(cursor, table_full_name) -> int:
    query = f"SELECT count(*) FROM {table_full_name} where DBT_UPDATE_TM is NULL"
    print(query)
    cursor.execute(query)
    row = cursor.fetchone()
    print(row)

    if row[0] == 0:
        logger.warning("⚠️ Table %s has no records (COUNT(*) = 0).", table_full_name)

    if row is None or len(row) < 1:
        raise ValueError(f"Unexpected COUNT(*). Result for table {table_full_name}: {row}")
    return int(row[0])

