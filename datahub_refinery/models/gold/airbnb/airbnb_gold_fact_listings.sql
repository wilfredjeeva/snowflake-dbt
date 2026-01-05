{{
    config(
        alias = 'FACT_AIRBNBLISTINGS',
        incremental_strategy = 'merge',
        unique_key = 'LISTING_ID'
    )
}}

WITH LATEST_AIRBNB_LISTINGS AS (
    SELECT
        SOURCESYSTEM,
        "id" AS ID,
        "name" AS NAME,
        "host_id" AS HOST_ID,
        "host_name" AS HOST_NAME,
        "neighbourhood_group" AS NEIGHBOURHOOD,
        "neighbourhood" AS NEIGHBOURHOOD_GROUP,
        "latitude" AS LATITUDE,
        "longitude" AS LONGITUDE,
        "room_type" AS ROOM_TYPE,
        "price" AS PRICE,
        "minimum_nights" AS MINIMUM_NIGHTS ,
        "number_of_reviews" AS NUMBER_OF_REVIEWS,
        "last_review" AS LAST_REVIEW,
        "reviews_per_month" AS REVIEWS_PER_MONTH,
        "calculated_host_listings_count" AS CALCULATED_HOST_LISTINGS_COUNT,
        "availability_365" AS AVAILABILITY_365,
        "number_of_reviews_ltm" AS NUMBER_OF_REVIEWS_LTM,
        "license" AS LICENSE,
        DBT_UPDATED_AT AS LAST_MODIFIED_AT
    FROM
        {{ ref('airbnb_silver_listings') }}
    WHERE DBT_VALID_TO IS NULL

    {% if is_incremental() %}
        AND DBT_UPDATED_AT > (
            SELECT COALESCE(MAX(LAST_MODIFIED_AT), '0000-01-01'::TIMESTAMP_NTZ) FROM {{ this }}
        )
    {% endif %}

)
SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    CASE 
        WHEN ABNB.PRICE > 200 THEN 'High Value'
        WHEN ABNB.PRICE > 100 THEN 'Medium Value'
        ELSE 'Standard'
    END AS VALUE_CATEGORY,
    ABNB.SOURCESYSTEM,
    DD.SK AS LISTING_SK,
    ABNB.ID as LISTING_ID,
    DD.NAME as LISTINGS,
    DD.HOST_ID,
    DD.HOST_NAME,
    G.GEOGRAPHY_ID,
    G.BOROUGH_ID,
    GS.WARD_ID,
    ABNB.PRICE,
    ABNB.MINIMUM_NIGHTS,
    ABNB.NUMBER_OF_REVIEWS,
    ABNB.CALCULATED_HOST_LISTINGS_COUNT as HOST_LISTING_COUNT,
    ABNB.AVAILABILITY_365 as AVAILABILITY,
    TO_VARCHAR(ABNB.LAST_REVIEW, 'YYYYMMDD') AS LAST_REVIEW_DATE_KEY,
    ABNB.REVIEWS_PER_MONTH,
    ABNB.LAST_MODIFIED_AT
FROM
    LATEST_AIRBNB_LISTINGS AS ABNB
LEFT JOIN {{ ref('airbnb_gold_dim_listing_details') }} AS DD
    ON ABNB.ID = DD.ID AND ABNB.HOST_ID = DD.HOST_ID
LEFT JOIN {{ source('GOLD_AIRBNB', 'DIM_GEOGRAPHY') }} AS G
    ON ABNB.LATITUDE = G.LATITUDE AND ABNB.LONGITUDE = G.LONGITUDE
LEFT JOIN {{ source('GOLD_AIRBNB', 'DIM_GEOGRAPHY_GEOSPATIAL') }} AS GS
    ON ABNB.LATITUDE = GS.LATITUDE AND ABNB.LONGITUDE = GS.LONGITUDE