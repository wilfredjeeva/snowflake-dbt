{% macro clean_table_tags () %}

    {% if execute %}

        {% set database_supported   = ['GOLD', 'PLATINUM'] %}
        {% set model_database       = (model.database | upper) %}
        {% set model_schema         = (model.schema   | upper) %}
        {% set model_alias          = (model.alias    | upper) %}
        {% set model_prefix         = (model.config.materialized | lower) %}
        {% set table_prefix         = 'VIEW' if model_prefix == 'view' else 'TABLE' %}
        {% set database_suffix      = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) %}
        {% set cleanup_model_config = {'incremental': true, 'snapshot': true} %}
        {% set is_cleanup_model     = cleanup_model_config.get(model_prefix) %}

        {# Macro usage validation #}
        {% if database_suffix not in database_supported %}
            {{ return(null) }}
        {% elif is_cleanup_model is none %}
            {{ exceptions.warn('clean_table_tags() macro skipped for model `' ~ model.name ~ '` because materialization `' ~ tojson(model_prefix) ~ '` is not supported.') }}
            {{ return(null) }}
        {% elif not adapter.get_relation(model.database, model.schema, model.alias) %}
            {{ return(null) }}
        {% endif %}

        {# Tag Assignment #}
        {{ log('/-------------------------------------- start -------------------------------------\', info=True) }}
        {{ log('** Table Tags - Cleanup **', info=True) }}

        {# Get relation tag manual column reference #}
        {% set get_table_tag_reference_sql %}
            SELECT
                CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TAG_NAME
            FROM TABLE(
                {{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this }}', 'TABLE')
            )
            WHERE LEVEL = 'TABLE'
            AND APPLY_METHOD = 'PROPAGATED'
            AND TAG_NAME NOT IN ('SENSITIVE_TAG', 'SOURCESYSTEM_TAG', 'DATASET_TAG')
            ;
        {% endset %}

        {# Get column tag reference from snowflake object #}
        {% set get_table_tag_reference_results = run_query(get_table_tag_reference_sql) %}
        {% for (tag_name, ) in get_table_tag_reference_results.rows %}

            {% set call_unset_table_tag_sql %}
                CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
                    '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}', '{{ tag_name.split(".")[2] }}'
                );
            {% endset %}

            {% do run_query(call_unset_table_tag_sql) %}
            {{ log('  UNSET[P]: ' ~ tag_name, info=True) }}

        {% endfor %}

        {{ log('/-------------------------------------- end --------------------------------------\', info=True) }}

    {% endif %}
{% endmacro %}
