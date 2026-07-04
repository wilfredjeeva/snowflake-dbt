{% macro rebuild_current_scd_table(snapshot_relation) %}

    {# Where to write the current table #}
    {% set target_db         = env_var('SILVER_DB', (target.name ~ '_SILVER') | upper) %}
    {% set target_schema     = snapshot_relation.schema %}
    {% set target_identifier = snapshot_relation.identifier ~ '_CURRENT' %}

    {# Build a physical table from the snapshot, with SYS columns #}
    create or replace table {{ target_db }}.{{ target_schema }}.{{ target_identifier }} as
    select
        s.*,

        -- Your SYS columns
        s.dbt_valid_from::timestamp_ntz as SYSDATEFROM,
        coalesce(s.dbt_valid_to::timestamp_ntz, to_timestamp_ntz('9999-12-31')) as SYSDATETO,
        iff(s.dbt_valid_to is null, true, false) as SYSCURRENTFLAG

    from {{ snapshot_relation }} s

    qualify row_number() over (
        partition by s.hash_sk
        order by s.dbt_valid_from desc
    ) = 1
    ;

{% endmacro %}
