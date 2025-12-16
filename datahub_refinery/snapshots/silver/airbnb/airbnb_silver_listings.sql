{% snapshot airbnb_silver_listings %}

{{ config(alias='AirBnBListings') }}

SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    SOURCESYSTEM,
    "id",
    "name",
    "host_id",
    "host_name",
    "neighbourhood_group",
    "neighbourhood",
    "latitude",
    "longitude",
    "room_type",
    "price",
    "minimum_nights",
    "number_of_reviews",
    "last_review",
    "reviews_per_month",
    "calculated_host_listings_count",
    "availability_365",
    "number_of_reviews_ltm",
    "license"
from {{ ref('airbnb_bronze_listings') }}

{% endsnapshot %}
