from Data.variables import *
from utils import *
from Data.ExpectedSchema.bronze_adf_schema.data_AirBnBDrivers import (table_name, expected_column_datatype)

def test_landing_bronze_count(sf_conn):
    # Use quoted identifier for case-sensitive landing table
    landing_table = f'{landing_db}.{airBnB_schema}.{airBnB_drivers_table}'
    bronze_table = f"{bronze_db}.{airBnB_schema}.{airBnB_drivers_table}"
    compare_row_counts(sf_conn, landing_table, bronze_table)


def test_landing_bronze_metadataValidation(sf_conn):
    check_metadata(sf_conn,f"{bronze_db}.INFORMATION_SCHEMA.COLUMNS",table_name,expected_column_datatype)

def test_landing_bronze_dataValidation(sf_conn):
    # Use quoted identifier for case-sensitive landing table
    landing_table = f'{landing_db}.{airBnB_schema}.{airBnB_drivers_table}'
    sql = f"""
            SELECT
                PAYLOAD:SOURCESYSTEM::STRING AS SOURCESYSTEM,
                PAYLOAD:code::STRING AS "code",
                PAYLOAD:dob::DATE AS "dob",
                PAYLOAD:driverId::INT AS "driverId",
                PAYLOAD:driverRef::STRING AS "driverRef",
                PAYLOAD:name:forename::STRING AS "forename",
                PAYLOAD:name:surname::STRING AS "surname",
                PAYLOAD:nationality::STRING AS "nationality",
                PAYLOAD:number::INT AS "number",
                PAYLOAD:url::STRING AS "url"
            FROM IDENTIFIER(%s)
            """

    bronze_table = f"{bronze_db}.{airBnB_schema}.{airBnB_drivers_table}"
    bsql = f"""select SOURCESYSTEM,"code","dob","driverId","driverRef","forename","surname","nationality","number","url" from IDENTIFIER(%s)"""

    compare_data(sf_conn, sql, landing_table, bsql, bronze_table)
