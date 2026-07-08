{{ config(
    materialized = 'table',
    alias = 'monitored_planning_schemes',
    post_hook = [
        "COMMENT ON TABLE {{ this }} IS 'This table contains data on monitored planning schemes, including development progress, housing delivery, scheme status, and key planning-related indicators.'"
    ]
) }}

select
    $SYSSOURCE,
    SYSFILENAME,
    SYSLASTMODIFIEDDATE,
    RFVAL,
    STATUS,
    REVIEWER,
    SUPERSEDINGCASENO,

    TRY_TO_TIMESTAMP_NTZ(STARTDATE, 'DD/MM/YYYY')     AS STARTDATE,
    TRY_TO_TIMESTAMP_NTZ(COMPLETEDDATE, 'DD/MM/YYYY') AS COMPLETEDDATE,

    COMMENTS,
    CHANGETORECORD,

    TRY_TO_TIMESTAMP_NTZ(REVIEWDATE, 'DD/MM/YYYY')    AS REVIEWDATE

From {{ source('landing_planningpolicy', 'monitored_planning_schemes') }}
