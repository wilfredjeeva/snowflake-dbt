{% macro set_tags_for_unpivot() %}
    {% if execute %}

        {% set model_sql       = model.raw_code | lower %}
        {% set materialization = model.config.materialized %}
        {% set model_database  = model.database | upper %}
        {% set model_schema    = model.schema   | upper %}
        {% set model_alias     = model.alias    | upper %}

        {% if materialization in ('table', 'incremental')
            and 'unpivot' in model_sql %}

            {% for node in model.depends_on.nodes %}

                {% set source_node = graph.nodes.get(node) or
                                     graph.sources.get(node) %}

                {% if source_node %}

                    {% set source_db     = source_node.database | upper %}
                    {% set source_schema = source_node.schema   | upper %}
                    {% set source_name   = source_node.name     | upper %}

                    {% set get_source_tags_sql %}
                        SELECT DISTINCT TAG_NAME, TAG_VALUE
                        FROM TABLE(
                            {{ source_db }}.INFORMATION_SCHEMA.TAG_REFERENCES(
                                '{{ source_db }}.{{ source_schema }}.{{ source_name }}',
                                'TABLE'
                            )
                        )
                        WHERE TAG_DATABASE = 'GOVERNANCE'
                        AND TAG_SCHEMA = 'TAGS'
                    {% endset %}

                    {% set tag_results = run_query(get_source_tags_sql) %}

                    {% if tag_results.rows | length > 0 %}

                        {% for row in tag_results.rows %}

                            {# Use same stored procedure as set_table_tags #}
                            {% set apply_tag_sql %}
                                CALL GOVERNANCE.GLOBAL_PROCEDURES.SET_TABLE_TAG(
                                    '{{ model_database }}',
                                    '{{ model_schema }}',
                                    '{{ model_alias }}',
                                    '{{ row[0].split(".")[2] if "." in row[0] else row[0] }}',
                                    '{{ row[1] }}'
                                )
                            {% endset %}

                            {% do run_query(apply_tag_sql) %}

                            {{ log("TAG SET via procedure: " ~ row[0] ~ " = " ~ row[1], info=true) }}

                        {% endfor %}

                        {% break %}

                    {% endif %}

                {% endif %}

            {% endfor %}

        {% endif %}

    {% endif %}
{% endmacro %}
