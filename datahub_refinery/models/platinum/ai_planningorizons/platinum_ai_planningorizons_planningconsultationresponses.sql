{{ config(
    materialized = 'table',
    alias = 'planningconsultationresponses',
    meta = {
        'table_tags': {'DATASET_TAG': 'UNIFORM', 'DATAOWNER_TAG': 'RCP'},
        'column_tags': {'CURRENT': {'SENSITIVE_FREETEXT_TAG': 'FREE TEXT'}}
    }
) }}

select * EXCLUDE (SYSGUIDGUID, SYSMODIFIEDTOOL, SYSDATAPROCESSNAME)
from {{ source('landing_ai_uniform_planning_poc', 'planningconsultationresponses') }}
