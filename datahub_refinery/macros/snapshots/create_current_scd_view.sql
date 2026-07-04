{% macro create_current_scd_view(snapshot_relation) %}

    {# choose where the current-view should live #}
    {% set view_db     = env_var('SILVER_DB', (target.name ~ '_SILVER') | upper) %}
    {% set view_schema = snapshot_relation.schema %}
    {% set view_name   = snapshot_relation.identifier ~ '_CURRENT' %}

    create or replace view {{ view_db }}.{{ view_schema }}.{{ view_name }} as
    select
        s.*,
        s.dbt_valid_from as SYSDATEFROM,
        coalesce(s.dbt_valid_to, to_timestamp_ntz('9999-12-31')) as SYSDATETO,
        iff(s.dbt_valid_to is null, true, false) as SYSCURRENTFLAG
    from {{ snapshot_relation }} s;

{% endmacro %}
