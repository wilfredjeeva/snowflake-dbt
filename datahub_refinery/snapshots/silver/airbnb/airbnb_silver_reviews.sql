{% snapshot airbnb_silver_reviews %}

{{ config(alias='AirBnBReviews') }}

SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    SOURCESYSTEM,
    "listing_id",
    "id",
    "date",
    "reviewer_id",
    "reviewer_name",
    "comments"
from {{ ref('airbnb_bronze_reviews') }}

{% endsnapshot %}
