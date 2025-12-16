{{ config(alias = 'AirBnBDrivers') }}

SELECT
    CURRENT_TIMESTAMP AS SYSLOADDATE,
    '{{ invocation_id }}' AS SYSRUNID,
    'DBT' AS SYSPROCESSINGTOOL,
    '{{ project_name }}' AS SYSDATAPROCESSORNAME,
    CAST(PAYLOAD:SOURCESYSTEM AS STRING) AS SOURCESYSTEM,
    CAST(PAYLOAD:code AS STRING) AS "code",
    CAST(PAYLOAD:dob AS DATE) AS "dob",
    CAST(PAYLOAD:driverId AS INT) AS "driverId",
    CAST(PAYLOAD:driverRef AS STRING) AS "driverRef",
    CAST(PAYLOAD:name:forename AS STRING) AS "forename",
    CAST(PAYLOAD:name:surname AS STRING) AS "surname",
    CAST(PAYLOAD:nationality AS STRING) AS "nationality",
    CAST(PAYLOAD:number AS INT) AS "number",
    CAST(PAYLOAD:url AS STRING) AS "url"
FROM
    {{ source('LANDING_AIRBNB', 'AirBnBDrivers') }}