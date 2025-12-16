{{
    config(
        alias = 'DIM_AIRBNBLISTING_DETAILS',
        incremental_strategy = 'merge',
        unique_key = 'ID'
    )
}}

SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    SOURCESYSTEM,
    SHA1(CONCAT_WS('||',
        COALESCE(CAST("id" AS VARCHAR), '')
    )) AS SK,
    "id" AS ID,
    "name" AS NAME,
    "host_id" AS HOST_ID,
    "host_name" AS HOST_NAME,
    "room_type" AS ROOM_TYPE,
    DBT_UPDATED_AT AS LAST_MODIFIED_AT
FROM {{ ref('airbnb_silver_listings') }}
WHERE DBT_VALID_TO IS NULL

{% if is_incremental() %}
    AND DBT_UPDATED_AT > (
        SELECT COALESCE(MAX(LAST_MODIFIED_AT), '0000-01-01'::TIMESTAMP_NTZ) FROM {{ this }}
    )
{% endif %}