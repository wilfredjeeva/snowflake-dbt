{{ config(alias='AirBnBReviews') }}

SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    SOURCESYSTEM,
    CAST("listing_id" AS INT) AS "listing_id",
    CAST("id" AS INT) AS "id",
    CAST("date" AS DATE) AS "date",
    CAST("reviewer_id" AS INT) AS "reviewer_id",
    "reviewer_name",
    "comments",
    "comments" AS "comments2"
FROM
    {{ source('LANDING_AIRBNB', 'AirBnBReviews') }}