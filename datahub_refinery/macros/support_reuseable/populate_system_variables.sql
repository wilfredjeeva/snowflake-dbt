{% macro system_variables() %}
CAST(CURRENT_TIMESTAMP() AS TIMESTAMP_NTZ) as SYSLOADDATE
,'{{ invocation_id }}' as SYSRUNID
,'DBT' as SYSPROCESSINGTOOL
,'{{ project_name }}' as SYSDATAPROCESSORNAME
{% endmacro %}
