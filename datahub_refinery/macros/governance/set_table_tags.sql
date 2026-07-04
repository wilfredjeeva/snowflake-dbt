{% macro set_table_tags () %}

    {% if execute %}

        {# Macro variables #}
        {% set manual_tags            = {} %}
        {% set key_field              = 'table_tags' %}
        {% set supported_layer        = ['GOLD', 'PLATINUM'] %}
        {% set model_database         = (model.database | upper) %}
        {% set model_schema           = (model.schema   | upper) %}
        {% set model_alias            = (model.alias    | upper) %}
        {% set materialization_type   = (model.config.materialized | lower) %}
        {% set restricted_tags        = ['SENSITIVE_TAG', 'SENSITIVEDATASET_TAG'] %}
        {% set this_temp_identifier   = this.identifier ~ '_dbt_tmp_gov_del_tbl__' ~ invocation_id.replace('-', '_') %}
        {% set database_layer         = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) %}
        {% set materialization_rebuild = {'table': true, 'view': true, 'dynamic_table': false, 'incremental': false, 'snapshot': false} %}
        {% set is_rebuild_model       = materialization_rebuild.get(materialization_type) %}

        {# Usage validation #}
        {% if database_layer not in supported_layer %}
            {{ return(null) }}
        {% elif is_rebuild_model is none %}
            {{ return(null) }}
        {% endif %}

        {{ log('/-------------------------------------- start -------------------------------------\', info=True) }}
        {{ log('** Table Tags - Management **', info=True) }}

        {# Config validation #}
        {% if model.config and model.config.meta and key_field in model.config.meta %}

            {% set meta_tags = model.config.meta.get(key_field) %}

            {# Validate `table_tags` value #}
            {% if (meta_tags is not none) and (meta_tags is not mapping) %}
                {{ exceptions.raise_compiler_error('The meta field `' ~ key_field ~ '` value must be of type key-value pair.') }}
            {% endif %}

            {{ log('Meta tags: ' ~ meta_tags, info=False) }}

            {# Validate `table_tags[i]` name and value #}
            {% for tag_name, tag_value in meta_tags.items() %}

                {% set _tag_name  = (tag_name  | trim | upper) %}
                {% set _tag_value = (tag_value | upper) %}

                {% if (tag_name is none) or (tag_name is not string) or (_tag_name == '') %}
                    {{ exceptions.raise_compiler_error('Missing key, set `' ~ key_field ~ '`[' ~ loop.index ~ '] to a non-empty string') }}

                {% elif (tag_value is none) or (tag_value is not string) or (_tag_value == '') %}
                    {{ exceptions.raise_compiler_error('Missing value, set `' ~ key_field ~ '`[' ~ loop.index ~ '] to a non-empty string') }}

                {% elif _tag_name in restricted_tags %}
                    {{ exceptions.raise_compiler_error(
                        'Invalid key, set `' ~ key_field ~ '`[' ~ loop.index ~ '] to an non-restricted value ' ~
                        '| `' ~ _tag_name ~ '` cannot be set via dbt meta config.'
                    ) }}

                {% endif %}

                {% if _tag_name not in manual_tags %}
                    {% do manual_tags.update({ ('GOVERNANCE.TAGS.' ~ _tag_name): _tag_value }) %}
                {% endif %}

            {% endfor %}
        {% endif %}

        {{ log('Manual tags: ' ~ manual_tags, info=False) }}

        {# Main execution #}
        {% if is_rebuild_model is true %}
            {{ log('  --', info=True) }}
            {{ log('  Tag strategy: Direct', info=True) }}

            {% for tag_name, tag_value in manual_tags.items() %}

                {% if tag_name == 'GOVERNANCE.TAGS.DATASET_TAG' %}

                    {% set call_provision_dataset_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.PROVISION_DATASET('{{ tag_value }}');
                    {% endset %}

                    {% do run_query(call_provision_dataset_sql) %}

                {% endif %}

                {% set call_set_table_tag_sql %}
                    CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_TABLE_TAG(
                        '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                        '{{ tag_name.split(".")[2] }}', '{{ tag_value }}'
                    );
                {% endset %}

                {% do run_query(call_set_table_tag_sql) %}
                {{ log('    SET: ' ~ tag_name ~ ' = ' ~ tag_value, info=True) }}

            {% endfor %}

        {% else %}
            {{ log('  --', info=True) }}
            {{ log('  Tag strategy: Check', info=True) }}

            {# Get propagated table tags #}
            {% set get_propagated_table_tags_sql %}
                SELECT
                    OBJECT_AGG(CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME), TAG_VALUE::VARIANT) AS ALL_TABLE_TAGS
                FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this }}', 'TABLE'))
                WHERE LEVEL = 'TABLE' AND APPLY_METHOD IN ('PROPAGATED', 'INHERITED')
                ;
            {% endset %}

            {# Get tag reference from snowflake object #}
            {% set get_propagated_table_tags_result = run_query(get_propagated_table_tags_sql) %}
            {% set propagated_tags = fromjson(get_propagated_table_tags_result.columns[0].values()[0] ) %}

            {{ log('Propagated Tags: ' ~ propagated_tags, info=False) }}

            {# Combine propagated and manual tags #}
            {% set table_tags = propagated_tags.copy() %}
            {% for tag_name, tag_value in manual_tags.copy().items() %}
                {% if tag_name not in table_tags %}
                    {% do table_tags.update({ tag_name: null }) %}
                {% endif %}
                {% do table_tags.update({ tag_name: tag_value }) %}
            {% endfor %}

            {{ log('Table Tags: ' ~ table_tags, info=False) }}

            {% set compare_table_tags_sql %}
                WITH SRC_TAG_REFERENCE AS (
                    {% if (table_tags | length) > 0 %}
                        {% for tag_name, tag_value in table_tags.items() %}
                            SELECT
                                '{{ tag_name }}' AS SRC_TAG_NAME,
                                '{{ tag_value }}' AS SRC_TAG_VALUE
                            {% if not loop.last %} UNION {% endif %}
                        {% endfor %}
                    {% else %}
                        SELECT NULL AS SRC_TAG_NAME, NULL AS SRC_TAG_VALUE
                        LIMIT 0
                    {% endif %}
                ),
                TGT_TAG_REFERENCE AS (
                    SELECT
                        CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TGT_TAG_NAME,
                        TAG_VALUE AS TGT_TAG_VALUE
                    FROM TABLE (
                        {{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this }}', 'TABLE')
                    )
                    WHERE LEVEL = 'TABLE'
                ),
                SRC_TGT_TAG_REFERENCE AS (
                    SELECT
                        SRC_TAG_NAME, SRC_TAG_VALUE,
                        TGT_TAG_NAME, TGT_TAG_VALUE,
                        CASE
                            WHEN TGT_TAG_NAME IS NULL THEN 'SET'
                            WHEN SRC_TAG_NAME IS NULL THEN 'UNSET'
                            WHEN SRC_TAG_NAME = TGT_TAG_NAME AND SRC_TAG_VALUE != TGT_TAG_VALUE THEN 'SET'
                        END AS TAG_ACTION,
                        CASE
                            WHEN TAG_ACTION = 'SET' THEN 1
                            WHEN TAG_ACTION = 'UNSET' THEN 2
                        END AS ORDER_ACTION
                    FROM SRC_TAG_REFERENCE
                    FULL JOIN TGT_TAG_REFERENCE
                        ON SRC_TAG_NAME = TGT_TAG_NAME
                ),
                FINAL_REFERENCE AS (
                    SELECT
                        ORDER_ACTION, TAG_ACTION,
                        IFF(TAG_ACTION = 'SET', SRC_TAG_NAME, TGT_TAG_NAME) AS TAG_NAME,
                        IFF(TAG_ACTION = 'SET', SRC_TAG_VALUE, TGT_TAG_VALUE) AS TAG_VALUE
                    FROM SRC_TGT_TAG_REFERENCE
                    WHERE TAG_ACTION IS NOT NULL
                )
                SELECT
                    ORDER_ACTION, TAG_ACTION, TAG_NAME, TAG_VALUE
                FROM FINAL_REFERENCE
                ORDER BY ORDER_ACTION
                ;
            {% endset %}

            {% set compare_table_tags_results = run_query(compare_table_tags_sql) %}

            {% for (order_action, tag_action, tag_name, tag_value) in compare_table_tags_results.rows %}

                {% if tag_action == 'SET' %}

                    {% if tag_name == 'GOVERNANCE.TAGS.DATASET_TAG' %}

                        {% set call_provision_dataset_sql %}
                            CALL GOVERNANCE.GLOBAL_PROCEDURES.PROVISION_DATASET('{{ tag_value }}');
                        {% endset %}

                        {% do run_query(call_provision_dataset_sql) %}

                    {% endif %}

                    {% set call_set_table_tag_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_TABLE_TAG(
                            '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                            '{{ tag_name.split(".")[2] }}', '{{ tag_value }}'
                        );
                    {% endset %}

                    {% do run_query(call_set_table_tag_sql) %}
                    {{ log('    SET: ' ~ tag_name ~ ' = ' ~ tag_value, info=True) }}

                {% elif tag_action == 'UNSET' and tag_name not in ['GOVERNANCE.TAGS.SENSITIVE_TAG', 'GOVERNANCE.TAGS.SENSITIVEDATASET_TAG'] %}

                    {% set call_unset_table_tag_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
                            '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                            '{{ tag_name.split(".")[2] }}'
                        );
                    {% endset %}

                    {% do run_query(call_unset_table_tag_sql) %}
                    {{ log('    UNSET: ' ~ tag_name, info=True) }}

                {% endif %}
            {% endfor %}

            {# Force tag propagation #}
            {% set create_temp_table_sql %}
                CREATE OR REPLACE TEMPORARY TABLE {{ this.database }}.{{ this.schema }}.{{ this_temp_identifier }} AS (
                    SELECT * FROM ({{ model['compiled_sql'] }})
                    WHERE FALSE
                );
            {% endset %}

            {% do run_query(create_temp_table_sql) %}
            {{ log('  Temporary table `' ~ this.database ~ '.' ~ this.schema ~ '.' ~ this_temp_identifier ~ '` successfully created.', info=False) }}

            {% set get_columns_information_sql %}
                WITH TGT_COLUMNS AS (
                    SELECT
                        COL.ORDINAL_POSITION AS TGT_COLUMN_POSITION,
                        COL.COLUMN_NAME AS TGT_COLUMN
                    FROM {{ this.database }}.INFORMATION_SCHEMA.TABLES AS TBL
                    INNER JOIN {{ this.database }}.INFORMATION_SCHEMA.COLUMNS AS COL
                        ON TBL.TABLE_CATALOG = COL.TABLE_CATALOG
                        AND TBL.TABLE_SCHEMA = COL.TABLE_SCHEMA
                        AND TBL.TABLE_NAME = COL.TABLE_NAME
                    WHERE UPPER(TBL.TABLE_CATALOG) = UPPER('{{ this.database }}')
                    AND UPPER(TBL.TABLE_SCHEMA) = UPPER('{{ this.schema }}')
                    AND UPPER(TBL.TABLE_NAME) = UPPER('{{ this.identifier }}')
                    AND TBL.IS_TEMPORARY = 'NO'
                ),
                TEMP_COLUMNS AS (
                    SELECT COL.COLUMN_NAME AS TEMP_COLUMN
                    FROM {{ this.database }}.INFORMATION_SCHEMA.TABLES AS TBL
                    INNER JOIN {{ this.database }}.INFORMATION_SCHEMA.COLUMNS AS COL
                        ON TBL.TABLE_CATALOG = COL.TABLE_CATALOG
                        AND TBL.TABLE_SCHEMA = COL.TABLE_SCHEMA
                        AND TBL.TABLE_NAME = COL.TABLE_NAME
                    WHERE UPPER(TBL.TABLE_CATALOG) = UPPER('{{ this.database }}')
                    AND UPPER(TBL.TABLE_SCHEMA) = UPPER('{{ this.schema }}')
                    AND UPPER(TBL.TABLE_NAME) = UPPER('{{ this_temp_identifier }}')
                    AND TBL.IS_TEMPORARY = 'YES'
                )
                SELECT
                    ARRAY_AGG(TGT_COLUMN) WITHIN GROUP (ORDER BY TGT_COLUMN_POSITION) AS ALL_COLUMNS,
                    ARRAY_AGG(IFF(TEMP_COLUMN IS NULL, TGT_COLUMN, NULL)) WITHIN GROUP (ORDER BY TGT_COLUMN_POSITION) AS MISSING_COLUMNS
                FROM TGT_COLUMNS
                LEFT JOIN TEMP_COLUMNS
                    ON TGT_COLUMN = TEMP_COLUMN
                ;
            {% endset %}

            {% set get_columns_information_result = run_query(get_columns_information_sql) %}
            {% set target_columns  = fromjson(get_columns_information_result.columns[0].values()[0]) %}
            {% set missing_columns = fromjson(get_columns_information_result.columns[1].values()[0]) %}

            {% set force_tag_propagation_sql %}
                INSERT INTO {{ this }} ({{ target_columns | join(', ') }})
                SELECT {{ target_columns | join(', ') }} FROM (
                    SELECT
                        src.*
                        {% for missing_column in missing_columns %}
                        , NULL AS {{ missing_column }}
                        {% endfor %}
                    FROM ( {{ model['compiled_sql'] }} ) AS src
                    WHERE FALSE
                )
            {% endset %}

            {% do run_query(force_tag_propagation_sql) %}

            {% if database_layer in ['GOLD', 'PLATINUM'] %}
                {% set call_unset_table_tag_sql %}
                    CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
                        '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}', 'SENSITIVE_TAG'
                    );
                {% endset %}

                {% do run_query(call_unset_table_tag_sql) %}
            {% endif %}

            {{ log('  --', info=True) }}
            {{ log('  Table refreshed!', info=True) }}

        {% endif %}

        {{ log('/-------------------------------------- end --------------------------------------\', info=True) }}

    {% endif %}
{% endmacro %}
