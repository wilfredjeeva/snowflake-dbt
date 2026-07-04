{% macro set_sensitive_tag() %}

    {% if execute %}

        {# Macro variables #}
        {% set supported_layer  = ['GOLD', 'PLATINUM'] %}
        {% set model_database   = (model.database | upper) %}
        {% set model_schema     = (model.schema   | upper) %}
        {% set model_alias      = (model.alias    | upper) %}
        {% set database_layer   = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) %}

        {# Usage validation #}
        {% if database_layer not in supported_layer %}
            {{ return(null) }}
        {% endif %}

        {# Main execution #}
        {{ log('/-------------------------------------- start -------------------------------------\', info=True) }}
        {{ log('** Sensitive Tags - Replacement **', info=True) }}

        {% set get_sensitive_tag_value_sql %}
            SELECT SYSTEM$GET_TAG('GOVERNANCE.TAGS.SENSITIVE_TAG', '{{ this }}', 'TABLE');
        {% endset %}

        {% set sensitive_tag_value_result = run_query(get_sensitive_tag_value_sql) %}
        {% set sensitive_tag_value = sensitive_tag_value_result.columns[0].values()[0] %}
        {{ log('  --', info=False) }}
        {{ log('  SENSITIVE_TAG = ' ~ sensitive_tag_value, info=False) }}

        {% set get_sensitive_dataset_tag_value_sql %}
            SELECT SYSTEM$GET_TAG('GOVERNANCE.TAGS.SENSITIVEDATASET_TAG', '{{ this }}', 'TABLE');
        {% endset %}

        {% set get_sensitive_dataset_tag_value_result = run_query(get_sensitive_dataset_tag_value_sql) %}
        {% set sensitive_dataset_tag_value = get_sensitive_dataset_tag_value_result.columns[0].values()[0] %}
        {{ log('  SENSITIVEDATASET_TAG = ' ~ sensitive_dataset_tag_value, info=False) }}

        {# Key decision #}
        {% if (sensitive_tag_value is none) and (sensitive_dataset_tag_value is none) %}
            {% set tag_value = 'SENSITIVE' %}
        {% elif sensitive_tag_value is not none %}
            {% set tag_value = sensitive_tag_value %}
        {% else %}
            {{ log('  --', info=True) }}
            {{ log('  No action required', info=True) }}
            {{ return(null) }}
        {% endif %}

        {{ log('  Selected tag value: ' ~ tag_value, info=False) }}

        {% set call_set_table_tag_sql %}
            CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_TABLE_TAG(
                '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                'SENSITIVEDATASET_TAG', '{{ tag_value }}'
            );
        {% endset %}

        {% do run_query(call_set_table_tag_sql) %}
        {{ log('  --', info=True) }}
        {{ log('  SET[M]: SENSITIVEDATASET_TAG = ' ~ tag_value, info=True) }}

        {% set call_unset_table_tag_sql %}
            CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
                '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}', 'SENSITIVE_TAG'
            );
        {% endset %}

        {% do run_query(call_unset_table_tag_sql) %}
        {{ log('  UNSET[M]: SENSITIVE_TAG' ~ tag_value, info=True) }}

        {{ log('/-------------------------------------- end --------------------------------------\', info=True) }}

    {% endif %}
{% endmacro %}
