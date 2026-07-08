{% macro val_column_policies () %}

    {% if execute %}

    {# Macro variables #}
    {% set database_layer = modules.re.sub('^(DEV|TEST|PREPROD|PROD)_', '', model.database | upper) | upper %}
    {% set database_rules = {
        'BRONZE_ADF': ('SENSITIVE_TAG',        'BOOLAND_AGG'),
        'SILVER'    : ('SENSITIVE_TAG',        'BOOLAND_AGG'),
        'GOLD'      : ('SENSITIVEDATASET_TAG', 'BOOLOR_AGG'),
        'PLATINUM'  : ('SENSITIVEDATASET_TAG', 'BOOLOR_AGG')
    } %}

    {# Usage validation #}
    {% if database_layer not in database_rules %}
        {{ return(null) }}
    {% else %}

        {% set get_sensitive_tag_value_sql %}
            SELECT SYSTEM$GET_TAG('GOVERNANCE.TAGS.{{ database_rules[database_layer][0] }}', '{{ this }}', 'TABLE');
        {% endset %}

        {% set get_sensitive_tag_value_result = run_query(get_sensitive_tag_value_sql) %}
        {% set sensitive_tag_value = get_sensitive_tag_value_result.columns[0].values()[0] %}

        {% if sensitive_tag_value != 'SENSITIVE' %}
            {{ return(null) }}
        {% endif %}

    {% endif %}

    {# Policy validation #}
    {% set validate_column_policy_sql %}
        WITH COLUMN_INFORMATION AS (
            SELECT
                CONCAT_WS('.', TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME) AS INF_TABLE_IDENTIFIER,
                COLUMN_NAME AS INF_COLUMN_NAME
            FROM {{ model.database }}.INFORMATION_SCHEMA.COLUMNS
            WHERE UPPER(TABLE_CATALOG) = '{{ model.database | upper }}'
              AND UPPER(TABLE_SCHEMA)  = '{{ model.schema | upper }}'
              AND UPPER(TABLE_NAME)    = '{{ model.alias | upper }}'
              AND UPPER(DATA_TYPE) NOT IN (
                'BOOLEAN',
                'GEOGRAPHY',
                'GEOMETRY'
              )
        ),
        COLUMN_REFERENCE AS (
            SELECT
                CONCAT_WS('.', REF_DATABASE_NAME, REF_SCHEMA_NAME, REF_ENTITY_NAME) AS REF_TABLE_IDENTIFIER,
                REF_COLUMN_NAME,
                POLICY_NAME AS REF_POLICY_NAME
            FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.POLICY_REFERENCES(
                ref_entity_name => '{{ this }}',
                ref_entity_domain => 'TABLE'
            ))
            WHERE POLICY_KIND = 'MASKING_POLICY'
        )
        SELECT
            {{ database_rules[database_layer][1] }}(IFF(REF_POLICY_NAME IS NOT NULL, TRUE, FALSE)) AS VALIDATION_RESULT
        FROM COLUMN_INFORMATION
        LEFT JOIN COLUMN_REFERENCE
               ON INF_TABLE_IDENTIFIER = REF_TABLE_IDENTIFIER
              AND INF_COLUMN_NAME      = REF_COLUMN_NAME
        ;
    {% endset %}

    {% set validate_column_policy_result = run_query(validate_column_policy_sql) %}
    {% set validation_passed = validate_column_policy_result.columns[0].values()[0] %}

    {% if not validation_passed %}

        {{ exceptions.raise_compiler_error(
            'Column masking policy validation failed for ' ~ this ~
            ' | Layer: ' ~ database_layer ~
            ' | Sensitivity tag: ' ~ database_rules[database_layer][0] ~ '=SENSITIVE' ~
            ' | Validation rule: ' ~ (
                'All columns must have a masking policy'
                if database_rules[database_layer][1] == 'BOOLAND_AGG'
                    else 'At least one column must have a masking policy'
            )
        ) }}

    {% endif %}

    {% endif %}

{% endmacro %}
