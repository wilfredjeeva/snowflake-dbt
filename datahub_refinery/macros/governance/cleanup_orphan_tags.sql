{% macro cleanup_orphan_tags() %}

    {% if execute %}

        {# Macro variables #}
        {% set supported_layer         = ['GOLD', 'PLATINUM'] %}
        {% set model_database          = (model.database | upper) %}
        {% set model_schema            = (model.schema   | upper) %}
        {% set model_alias             = (model.alias    | upper) %}
        {% set materialization_type    = (model.config.materialized | lower) %}
        {% set materialization_cleanup = {'incremental': true, 'snapshot': true} %}
        {% set is_cleanup_required     = materialization_cleanup.get(materialization_type) %}
        {% set this_temp               = this ~ '__dbt_tmp_gov_prop__' ~ invocation_id.replace('-', '_') %}
        {% set database_layer          = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) %}

        {# Usage validation #}
        {% if database_layer not in supported_layer %}
            {{ return(null) }}
        {% elif is_cleanup_required is none %}
            {{ return(null) }}
        {% endif %}

        {# Main execution #}
        {{ log('/-------------------------------------- start -------------------------------------\', info=True) }}
        {{ log('** Orphan Tags - Cleanup **', info=True) }}

        {% set create_temp_table_sql %}
            CREATE OR REPLACE TEMPORARY TABLE {{ this_temp }} AS (
                SELECT * FROM ({{ model['compiled_sql'] }})
                WHERE FALSE
            );
        {% endset %}

        {% do run_query(create_temp_table_sql) %}
        {{ log('  Temporary table `' ~ this_temp ~ '` successfully created.', info=False) }}

        {{ log('  --', info=True) }}
        {{ log('  Table Tags', info=True) }}

        {% set compare_table_tags_sql %}
            WITH
            TAG_REFERENCES AS (
                SELECT
                    CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TGT_TAG_NAME,
                    APPLY_METHOD AS TGT_APPLY_METHOD
                FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this }}', 'TABLE'))
                WHERE LEVEL = 'TABLE' AND APPLY_METHOD = 'PROPAGATED'
            ),
            SRC_REFERENCES AS (
                SELECT
                    CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS SRC_TAG_NAME,
                    APPLY_METHOD AS SRC_APPLY_METHOD
                FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this_temp }}', 'TABLE'))
                WHERE LEVEL = 'TABLE' AND APPLY_METHOD IN ('PROPAGATED', 'MANUAL')
            )
            SELECT
                TGT_TAG_NAME AS TAG_NAME,
                TGT_APPLY_METHOD AS APPLY_METHOD
            FROM TAG_REFERENCES
            LEFT JOIN SRC_REFERENCES
                ON TGT_TAG_NAME = SRC_TAG_NAME
            WHERE SRC_TAG_NAME IS NULL
            ;
        {% endset %}

        {% set compare_table_tags_results = run_query(compare_table_tags_sql) %}

        {% for (tag_name, apply_method) in compare_table_tags_results.rows %}

            {% set call_unset_table_tag_sql %}
                CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
                    '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}', '{{ tag_name.split(".")[2] }}'
                );
            {% endset %}

            {% do run_query(call_unset_table_tag_sql) %}
            {{ log('  UNSET[' ~ apply_method[0] ~ ']: ' ~ tag_name, info=True) }}

        {% endfor %}

        {{ log('  --', info=True) }}
        {{ log('  Column Tags', info=True) }}

        {% set compare_column_tags_sql %}
            WITH
            TAG_REFERENCES AS (
                SELECT
                    COLUMN_NAME AS TGT_COLUMN_NAME,
                    CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TGT_TAG_NAME,
                    APPLY_METHOD AS TGT_APPLY_METHOD
                FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('{{ this }}', 'TABLE'))
                WHERE LEVEL = 'COLUMN' AND APPLY_METHOD = 'PROPAGATED'
            ),
            SRC_REFERENCES AS (
                SELECT
                    COLUMN_NAME AS SRC_COLUMN_NAME,
                    CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS SRC_TAG_NAME,
                    APPLY_METHOD AS SRC_APPLY_METHOD
                FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('{{ this_temp }}', 'TABLE'))
                WHERE LEVEL = 'COLUMN' AND APPLY_METHOD IN ('PROPAGATED', 'MANUAL')
            )
            SELECT
                TGT_COLUMN_NAME AS COLUMN_NAME,
                TGT_TAG_NAME AS TAG_NAME,
                TGT_APPLY_METHOD AS APPLY_METHOD
            FROM TAG_REFERENCES
            LEFT JOIN SRC_REFERENCES
                ON TGT_COLUMN_NAME = SRC_COLUMN_NAME
                AND TGT_TAG_NAME = SRC_TAG_NAME
            WHERE SRC_TAG_NAME IS NULL
            ;
        {% endset %}

        {% set compare_column_tags_results = run_query(compare_column_tags_sql) %}

        {% for (column_name, tag_name, apply_method) in compare_column_tags_results.rows %}

            {% set call_unset_column_tag_sql %}
                CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_COLUMN_TAG(
                    '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}', '{{ column_name }}', '{{ tag_name.split(".")[2] }}'
                );
            {% endset %}

            {% do run_query(call_unset_column_tag_sql) %}
            {{ log('  UNSET[' ~ apply_method[0] ~ ']: ' ~ column_name ~ ' → ' ~ tag_name, info=True) }}

        {% endfor %}

        {{ log('/-------------------------------------- end --------------------------------------\', info=True) }}

    {% endif %}
{% endmacro %}
