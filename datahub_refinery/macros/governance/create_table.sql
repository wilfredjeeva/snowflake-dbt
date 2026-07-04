{% macro snowflake__create_table_as(temporary, relation, compiled_sql, language='sql') %}

    {% if language != 'sql' %}
        {% do exceptions.raise_compiler_error(
            "snowflake__create_table_as macro didn't get supported language, it got %s" % language
        ) %}
    {% endif %}

    {% if execute %}
        {# Prefer scanning the authored SQL; fall back to compiled SQL #}
        {% set raw = (model.raw_sql or compiled_sql) | upper %}
        {% set hooks = (model.config.post_hook or []) %}

        {# Catch common patterns: "UNSET TAG", or "ALTER ... UNSET ... TAG" #}
        {% if 'UNSET TAG' in raw or (' UNSET ' in raw and ' TAG ' in raw) %}
            {{ exceptions.raise_compiler_error(
                "Forbidden tag operation detected (UNSET TAG) in model: " ~ model.unique_id ~
                ". Remove any UNSET TAG statements (direct or via ALTER ... UNSET ... TAG)."
            ) }}
        {% endif %}

        {% for hook in hooks %}
            {% if 'UNSET TAG' in hook | upper %}
                {{exceptions.raise_compiler_error(
                    ". UNSET TAG detected in post-hook in model."
                )}}
            {% endif %}
        {% endfor %}

    {% endif %}

    {%- set contract_config = config.get('contract') -%}
    {% if contract_config.enforced %}
        {{ get_assert_columns_equivalent(compiled_sql) }}
        {% set compiled_sql = get_select_subquery(compiled_sql) %}
    {% endif %}

    {% set wrapped_sql %}
        SELECT
            CAST(CURRENT_TIMESTAMP() AS TIMESTAMP_NTZ) AS SYSLOADDATE,
            '{{ invocation_id }}' AS SYSRUNID,
            'DBT' AS SYSPROCESSINGTOOL,
            '{{ project_name }}' AS SYSDATAPROCESSORNAME,
            src.*
        FROM ( {{ compiled_sql }} ) src
    {% endset %}

    {% if temporary %}

        CREATE OR REPLACE TEMPORARY TABLE {{ relation }} AS (
            {{ wrapped_sql }}
        );

    {% set database_layer = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', (relation.database | upper)) %}

    {% if database_layer in ['GOLD', 'PLATINUM'] %}

        {% set tmp_relation   = (relation | string).split('.') %}
        {% set tmp_database   = tmp_relation[0][1:-1] if tmp_relation[0].startswith('"') else (tmp_relation[0] | upper) %}
        {% set tmp_schema     = tmp_relation[1][1:-1] if tmp_relation[1].startswith('"') else (tmp_relation[1] | upper) %}
        {% set tmp_identifier = tmp_relation[2][1:-1] if tmp_relation[2].startswith('"') else (tmp_relation[2] | upper) %}

        CALL GOVERNANCE.GLOBAL_PROCEDURES.UNSET_TABLE_TAG(
            '{{ tmp_database }}', '{{ tmp_schema }}', '{{ tmp_identifier }}', 'SENSITIVE_TAG'
        );

    {% endif %}

    {% else %}

        CREATE OR REPLACE TABLE {{ relation }} AS (
            {{ wrapped_sql }}
        );

    {% endif %}

{% endmacro %}
