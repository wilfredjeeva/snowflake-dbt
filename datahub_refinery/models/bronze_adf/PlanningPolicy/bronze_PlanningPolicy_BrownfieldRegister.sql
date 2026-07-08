{{ config(
    materialized = 'table',
    alias = 'brownfieldregister',
    post_hook = [
        "COMMENT ON TABLE {{ this }} IS 'This table contains Brownfield Land Register data, including site details, planning status, and development indicators for local areas.'"
    ]
) }}

with source_data as (

    select
        $SYSSOURCE,
        SYSFILENAME,
        SYSLASTMODIFIEDDATE,
        ORGANISATIONURI,
        ORGANISATIONLABEL,
        SITEREFERENCE,
        PREVIOUSLYPARTOF,
        SITENAMEADDRESS,
        SITEPLANURL,
        COORDINATEREFERENCESYSTEM,
        TRY_TO_NUMBER(GEOX, 38, 8)          as GEOX,
        TRY_TO_NUMBER(GEOY, 38, 8)          as GEOY,
        TRY_TO_NUMBER(HECTARES, 5, 2)       as HECTARES,
        OWNERSHIPSTATUS,
        DELIVERABLE,
        PLANNINGSTATUS,
        PERMISSIONTYPE,
        TRY_TO_TIMESTAMP_NTZ(PERMISSIONDATE, 'DD/MM/YYYY')  as PERMISSIONDATE,
        PLANNINGHISTORY,
        TRY_TO_NUMBER(PROPOSEDFORPIP)       as PROPOSEDFORPIP,
        TRY_TO_NUMBER(MINNETDWELLINGS)      as MINNETDWELLINGS,
        DEVELOPMENTDESCRIPTION,
        NONHOUSINGDEVELOPMENT,
        PART2,
        TRY_TO_NUMBER(NETWELLINGSRANGEFROM) as NETWELLINGSRANGEFROM,
        TRY_TO_NUMBER(NETWELLINGSRANGETO)   as NETWELLINGSRANGETO,
        HAZARDOUSSUBSTANCES,
        SITEINFORMATION,
        NOTES,
        TRY_TO_TIMESTAMP_NTZ(FIRSTADDEDDATE, 'DD/MM/YYYY')  as FIRSTADDEDDATE,
        TRY_TO_TIMESTAMP_NTZ(LASTUPDATEDDATE, 'DD/MM/YYYY') as LASTUPDATEDDATE
    from {{ source('landing_planningpolicy', 'brownfieldregister') }}

),

deduplicated as (

    select *
    from (
        select
            *,
            row_number() over (
                partition by SITEREFERENCE
                order by SYSLASTMODIFIEDDATE desc
            ) as rn
        from source_data
    )
    where rn = 1

)

select
    SYSSOURCE,
    SYSFILENAME,
    SYSLASTMODIFIEDDATE,
    ORGANISATIONURI,
    ORGANISATIONLABEL,
    SITEREFERENCE,
    PREVIOUSLYPARTOF,
    SITENAMEADDRESS,
    SITEPLANURL,
    COORDINATEREFERENCESYSTEM,
    GEOX,
    GEOY,
    HECTARES,
    OWNERSHIPSTATUS,
    DELIVERABLE,
    PLANNINGSTATUS,
    PERMISSIONTYPE,
    PERMISSIONDATE,
    PLANNINGHISTORY,
    PROPOSEDFORPIP,
    MINNETDWELLINGS,
    DEVELOPMENTDESCRIPTION,
    NONHOUSINGDEVELOPMENT,
    PART2,
    NETWELLINGSRANGEFROM,
    NETWELLINGSRANGETO,
    HAZARDOUSSUBSTANCES,
    SITEINFORMATION,
    NOTES,
    FIRSTADDEDDATE,
    LASTUPDATEDDATE
from deduplicated
