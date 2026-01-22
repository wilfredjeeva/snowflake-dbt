import pytest
from Data.variables import *
from utils import *
from Data.ExpectedSchema.bronze_adf_schema.data_AirBnBListings import (table_name, expected_column_datatype)

@pytest.mark.smoke
@pytest.mark.regression
def test_landing_bronze_count(sf_conn):
    landing_table = f'{landing_db}.{airBnB_schema}.{airBnB_listing_table}'
    bronze_table = f"{bronze_db}.{airBnB_schema}.{airBnB_listing_table}"
    compare_row_counts(sf_conn, landing_table, bronze_table)

@pytest.mark.smoke
@pytest.mark.regression
def test_landing_bronze_metadataValidation(sf_conn):
    check_metadata(sf_conn,f"{bronze_db}.INFORMATION_SCHEMA.COLUMNS",table_name,expected_column_datatype)

@pytest.mark.smoke
def test_landing_bronze_dataValidation(sf_conn):
    landing_table = f"{landing_db}.{airBnB_schema}.{airBnB_listing_table}"
    sql = f"""
            SELECT cast(ID as INT) ID,NAME,cast(HOST_ID as INT) HOST_ID,HOST_NAME,NEIGHBOURHOOD_GROUP,NEIGHBOURHOOD,cast(LATITUDE as FLOAT) LATITUDE,
                cast(LONGITUDE as FLOAT) LONGITUDE,ROOM_TYPE,cast(PRICE as INT) PRICE,cast(MINIMUM_NIGHTS as INT) MINIMUM_NIGHTS,cast(NUMBER_OF_REVIEWS as INT) NUMBER_OF_REVIEWS,
                cast(LAST_REVIEW as Date) LAST_REVIEW,cast(REVIEWS_PER_MONTH as FLOAT) REVIEWS_PER_MONTH,cast(CALCULATED_HOST_LISTINGS_COUNT as INT) CALCULATED_HOST_LISTINGS_COUNT,
                cast(AVAILABILITY_365 as INT) AVAILABILITY_365,cast(NUMBER_OF_REVIEWS_LTM as INT) NUMBER_OF_REVIEWS_LTM,LICENSE
            FROM IDENTIFIER(%s)
            """

    bronze_table = f"{bronze_db}.{airBnB_schema}.{airBnB_listing_table}"
    bsql = f"""select ID,NAME,HOST_ID,HOST_NAME,NEIGHBOURHOOD_GROUP,NEIGHBOURHOOD,LATITUDE,LONGITUDE,ROOM_TYPE,PRICE,MINIMUM_NIGHTS,NUMBER_OF_REVIEWS,LAST_REVIEW,REVIEWS_PER_MONTH,CALCULATED_HOST_LISTINGS_COUNT,AVAILABILITY_365,NUMBER_OF_REVIEWS_LTM,LICENSE from IDENTIFIER(%s)"""

    compare_data(sf_conn, sql, landing_table, bsql, bronze_table)
