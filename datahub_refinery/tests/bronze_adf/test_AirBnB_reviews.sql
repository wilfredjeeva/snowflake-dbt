{{ config(tags=["P1", "recon"]) }}

with landing as (
    SELECT CAST("listing_id" AS INT) AS "listing_id",
    CAST("id" AS INT) AS "id",
    CAST("date" AS DATE) AS "date",
    CAST("reviewer_id" AS INT) AS "reviewer_id",
    "reviewer_name",
    "comments",
    "comments" AS "comments2",
    "comments" AS "comments3",
    "comments" AS "comments4"
    FROM {{ source('LANDING_AIRBNB', 'AirBnBReviews') }}
),
bronze as (
    select "listing_id","id","date","reviewer_id","reviewer_name","comments", "comments2","comments3", "comments4"
    FROM {{ ref('airbnb_bronze_reviews') }}
),
diff as (
    (select * from landing except select * from bronze)
    union all
    (select * from bronze except select * from landing)
)
select * from diff
