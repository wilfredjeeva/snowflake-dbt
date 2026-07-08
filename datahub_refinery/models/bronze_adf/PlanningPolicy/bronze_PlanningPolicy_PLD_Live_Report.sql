{{ config(
    materialized = 'table',
    alias = 'pld_live_report',
    post_hook = [
        "COMMENT ON TABLE {{ this }} IS 'This Bronze table contains planning live report data sourced from UK Open Data, including planning application details, housing gain and loss metrics, development status, and location information.'"
    ]
) }}

select
    $SYSSOURCE,
    SYSFILENAME,
    SYSLASTMODIFIEDDATE,
    CAST(COUNTOFID AS NUMBER(38,0))         AS COUNTOFID,
    ID,
    STATUS,
    CAST(TOTALGAINS AS NUMBER(38,0))        AS TOTALGAINS,
    CAST(TOTALLOSSES AS NUMBER(38,0))       AS TOTALLOSSES,
    CAST(GAINSCOMPLETED AS NUMBER(38,0))    AS GAINSCOMPLETED,
    CAST(LOSSESCOMPLETED AS NUMBER(38,0))   AS LOSSESCOMPLETED,
    CAST(REMAININGGAINS AS NUMBER(38,0))    AS REMAININGGAINS,
    CAST(REMAININGLOST AS NUMBER(38,0))     AS REMAININGLOST,
    CAST(LIVENET AS NUMBER(38,0))           AS LIVENET,
    DESCRIPTION,
    CAST(VALIDATE AS DATE)                  AS VALIDATE,
    CAST(DECISIONDATE AS DATE)              AS DECISIONDATE,
    DECISION,
    APPEALDECISION,
    CAST(APPEALDECISIONDATE AS DATE)        AS APPEALDECISIONDATE,
    SITENAME,
    SITENUMBER,
    STREETNAME,
    LOCALITY,
    FULLPOSTCODE,
    WARD,
    APPLICATIONTYPEFULL,
    POLYGON

from {{ source('landing_planningpolicy', 'pld_live_report') }}
where ID is not Null
