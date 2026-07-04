{% macro set_column_tags() %}

    {% if execute %}

        {# Macro variables #}
        {% set manual_tags            = {} %}
        {% set key_field              = 'column_tags' %}
        {% set supported_layer        = ['GOLD', 'PLATINUM'] %}
        {% set model_database         = (model.database | upper) %}
        {% set model_schema           = (model.schema   | upper) %}
        {% set model_alias            = (model.alias    | upper) %}
        {% set materialization_type   = (model.config.materialized | lower) %}
        {% set database_layer         = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) %}
        {% set this_temp_identifier   = this.identifier ~ '_dbt_tmp_gov_dnl_col_' ~ invocation_id.replace('-', '_') %}
        {% set materialization_rebuild = {'table': true, 'view': true, 'dynamic_table': false, 'incremental': false, 'snapshot': false} %}
        {% set is_rebuild_model       = materialization_rebuild.get(materialization_type) %}

        {# Usage validation #}
        {% if database_layer not in supported_layer %}
            {{ return(null) }}
        {% elif is_rebuild_model is none %}
            {{ return(null) }}
        {% endif %}

        {{ log('/-------------------------------------- start -------------------------------------\', info=True) }}
        {{ log('** Column Tags - Management **', info=True) }}

        {# Config validation #}
        {% if model.config and model.config.meta and key_field in model.config.meta %}

            {% set meta_tags = model.config.meta[key_field] %}

            {# Validate `column_tags` value #}
            {% if (meta_tags is not none) and (meta_tags is not mapping) %}
                {{ exceptions.raise_compiler_error('The meta field `' ~ key_field ~ '` value must be of type key-value pair.') }}
            {% endif %}

            {{ log('Meta tags: ' ~ meta_tags, info=False) }}

            {# Validate `column_tags[i]` column name, tag name and value #}
            {% for column_name, tags in meta_tags.items() %}

                {% set _column_name = (column_name | trim) %}

                {% if (column_name is none) or (column_name is not string) or (_column_name == '') %}
                    {{ exceptions.raise_compiler_error('Missing key, set `' ~ key_field ~ '`[' ~ loop.index ~ '] key to a non-empty string for column → ' ~ _column_name) }}

                {% elif (tags is none) or (tags is not mapping) %}
                    {{ exceptions.raise_compiler_error(
                        'Missing value, set `' ~ key_field ~ '`[' ~ loop.index ~ '] value to a non-empty key value pair for column → ' ~ _column_name) }}

                {% endif %}

                {% for tag_name, tag_value in tags.items() %}

                    {% set _tag_name  = (tag_name | trim) %}
                    {% set _tag_value = tag_value %}

                    {% if (tag_name is none) or (tag_name is not string) or (_tag_name == '') %}
                        {{ exceptions.raise_compiler_error(
                            'Missing key, set `' ~ key_field ~ '`[' ~ loop.index ~ '] key to a non-empty string for column → ' ~ _column_name) }}

                    {% elif (tag_value is none) or (tag_value is not string) or (_tag_value == '') %}
                        {{ exceptions.raise_compiler_error(
                            'Missing value, set `' ~ key_field ~ '`[' ~ loop.index ~ '] value to a non-empty string for column → ' ~ _column_name) }}
                    {% endif %}

                    {% if _column_name not in manual_tags %}
                        {% do manual_tags.update({ _column_name: {} }) %}
                    {% endif %}

                    {% do manual_tags[_column_name].update({ ('GOVERNANCE.TAGS.' ~ _tag_name): _tag_value }) %}

                {% endfor %}
            {% endfor %}
        {% endif %}

        {{ log('Manual tags: ' ~ manual_tags, info=False) }}

        {# Main execution #}
        {% if is_rebuild_model is true %}
            {{ log('  --', info=True) }}
            {{ log('  Tag strategy: Direct', info=True) }}

            {% for column_name, tags in manual_tags.items() %}
                {% for tag_name, tag_value in tags.items() %}

                    {% set call_set_column_tag_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_COLUMN_TAG(
                            '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                            '{{ column_name }}', '{{ tag_name.split(".")[2] }}', '{{ tag_value }}'
                        );
                    {% endset %}

                    {% do run_query(call_set_column_tag_sql) %}
                    {{ log('    SET: ' ~ column_name ~ ' → ' ~ tag_name ~ ' = ' ~ tag_value, info=True) }}

                {% endfor %}
            {% endfor %}

        {% else %}
            {{ log('  --', info=True) }}
            {{ log('  Tag strategy: Check', info=True) }}

            {# Get propagated column tags #}
            {% set get_propagated_column_tags_sql %}
                SELECT OBJECT_AGG(COLUMN_NAME, COLUMN_TAGS) AS ALL_COLUMN_TAGS
                FROM (
                    SELECT COLUMN_NAME, OBJECT_AGG(TAG_NAME, TAG_VALUE) AS COLUMN_TAGS
                    FROM (
                        SELECT
                            COLUMN_NAME,
                            CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TAG_NAME,
                            TAG_VALUE::VARIANT AS TAG_VALUE
                        FROM TABLE(
                            {{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('{{ this }}', 'TABLE')
                        )
                        WHERE LEVEL = 'COLUMN' AND APPLY_METHOD = 'PROPAGATED'
                    )
                    GROUP BY COLUMN_NAME
                )
                ;
            {% endset %}

            {% set get_propagated_column_tags_result = run_query(get_propagated_column_tags_sql) %}
            {% set propagated_tags = fromjson( get_propagated_column_tags_result.columns[0].values()[0] ) %}

            {{ log('Propagated tags: ' ~ propagated_tags, info=False) }}

            {# Combine propagated and manual tags #}
            {% set column_tags = propagated_tags.copy() %}
            {% for column_name, custom_tags in manual_tags.copy().items() %}
                {% if column_name not in column_tags %}
                    {% do column_tags.update({ column_name: {} }) %}
                {% endif %}
                {% do column_tags[column_name].update( custom_tags ) %}
            {% endfor %}

            {{ log('Column Tags: ' ~ column_tags, info=False) }}

            {% set compare_column_tags_sql %}
                WITH SRC_TAG_REFERENCE AS (
                    {% if (column_tags | length) > 0 %}
                        {% for column_name, tags in column_tags.items() %}
                            {% set outer_loop_last = loop.last %}
                            {% for tag_name, tag_value in tags.items() %}
                                SELECT
                                    '{{ column_name }}' AS SRC_COLUMN,
                                    '{{ tag_name }}' AS SRC_TAG_NAME,
                                    '{{ tag_value }}' AS SRC_TAG_VALUE
                                {% if not (outer_loop_last and loop.last) %} UNION ALL {% endif %}
                            {% endfor %}
                        {% endfor %}
                    {% else %}
                        SELECT NULL AS SRC_COLUMN, NULL AS SRC_TAG_NAME, NULL AS SRC_TAG_VALUE
                        LIMIT 0
                    {% endif %}
                ),
                TGT_TAG_REFERENCE AS (
                    SELECT
                        COLUMN_NAME AS TGT_COLUMN,
                        CONCAT_WS('.', TAG_DATABASE, TAG_SCHEMA, TAG_NAME) AS TGT_TAG_NAME,
                        TAG_VALUE AS TGT_TAG_VALUE
                    FROM TABLE (
                        {{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES_ALL_COLUMNS('{{ this }}', 'TABLE')
                    )
                    WHERE LEVEL = 'COLUMN'
                ),
                SRC_TGT_TAG_REFERENCE AS (
                    SELECT
                        SRC_COLUMN, SRC_TAG_NAME, SRC_TAG_VALUE,
                        TGT_COLUMN, TGT_TAG_NAME, TGT_TAG_VALUE,
                        CASE
                            WHEN TGT_COLUMN IS NULL THEN 'SET'
                            WHEN SRC_COLUMN IS NULL THEN 'UNSET'
                            WHEN SRC_TAG_NAME = TGT_TAG_NAME AND SRC_TAG_VALUE != TGT_TAG_VALUE THEN 'SET'
                        END AS TAG_ACTION,
                        CASE
                            WHEN TAG_ACTION = 'SET' THEN 1
                            WHEN TAG_ACTION = 'UNSET' THEN 2
                        END AS ORDER_ACTION
                    FROM SRC_TAG_REFERENCE
                    FULL JOIN TGT_TAG_REFERENCE
                        ON  SRC_COLUMN = TGT_COLUMN
                        AND SRC_TAG_NAME = TGT_TAG_NAME
                ),
                FINAL_REFERENCE AS (
                    SELECT
                        ORDER_ACTION, TAG_ACTION,
                        IFF(TAG_ACTION = 'SET', SRC_COLUMN, TGT_COLUMN) AS COLUMN_NAME,
                        IFF(TAG_ACTION = 'SET', SRC_TAG_NAME, TGT_TAG_NAME) AS TAG_NAME,
                        IFF(TAG_ACTION = 'SET', SRC_TAG_VALUE, TGT_TAG_VALUE) AS TAG_VALUE
                    FROM SRC_TGT_TAG_REFERENCE
                    WHERE TAG_ACTION IS NOT NULL
                )
                SELECT
                    ORDER_ACTION, TAG_ACTION, COLUMN_NAME, TAG_NAME, TAG_VALUE
                FROM FINAL_REFERENCE
                ORDER BY ORDER_ACTION
                ;
            {% endset %}

            {% set compare_column_tags_results = run_query(compare_column_tags_sql) %}
            {% for (order_action, tag_action, column_name, tag_name, tag_value) in compare_column_tags_results.rows %}

                {% if tag_action == 'SET' %}

                    {% set call_set_column_tag_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_COLUMN_TAG(
                            '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                            '{{ column_name }}', '{{ tag_name.split(".")[2] }}', '{{ tag_value }}'
                        );
                    {% endset %}

                    {% do run_query(call_set_column_tag_sql) %}
                    {{ log('    SET: ' ~ column_name ~ ' → ' ~ tag_name ~ ' = ' ~ tag_value, info=True) }}

                {% elif tag_action == 'UNSET' %}

                    {% set call_unset_column_tag_sql %}
                        CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_COLUMN_TAG(
                            '{{ model_database }}', '{{ model_schema }}', '{{ model_alias }}',
                            '{{ column_name }}', '{{ tag_name.split(".")[2] }}'
                        );
                    {% endset %}

                    {% do run_query(call_unset_column_tag_sql) %}
                    {{ log('    UNSET: ' ~ column_name ~ ' → ' ~ tag_name, info=True) }}

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
