{% macro val_column_policies() %}

{% if execute %}

{# Macro variables #}
{% set database_layer = modules.re.sub('(DEV|TEST|PREPROD|PROD).', '', model.database | upper) | upper %}
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
{#
  FIX (2026-07-03): Added UNION with SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES to capture
  tag-based masking policies. INFORMATION_SCHEMA.POLICY_REFERENCES only returns DIRECTLY
  attached masking policies. When masking policies are applied via Snowflake Tags (tag-based
  dynamic data masking), they are NOT returned by INFORMATION_SCHEMA — causing the validation
  to falsely fail even though masking IS in place. ACCOUNT_USAGE includes both direct and
  tag-based policy references (POLICY_STATUS = 'ACTIVE').
  Note: DBT_TEST_ROLE / DBT_PREPROD_ROLE / DBT_PROD_ROLE requires GOVERNANCE_VIEWER privilege
  (or equivalent) on SNOWFLAKE.ACCOUNT_USAGE to use this.
#}
{% set validate_column_policy_sql %}
    WITH COLUMN_INFORMATION AS (
        SELECT
            CONCAT_WS('.', TABLE_CATALOG, TABLE_SCHEMA, TABLE_NAME) AS INF_TABLE_IDENTIFIER,
            COLUMN_NAME                                              AS INF_COLUMN_NAME
        FROM {{ model.database }}.INFORMATION_SCHEMA.COLUMNS
        WHERE UPPER(TABLE_CATALOG) = '{{ model.database | upper }}'
          AND UPPER(TABLE_SCHEMA)  = '{{ model.schema  | upper }}'
          AND UPPER(TABLE_NAME)    = '{{ model.alias   | upper }}'
          AND UPPER(DATA_TYPE) NOT IN (
            'BOOLEAN',
            'GEOGRAPHY',
            'GEOMETRY'
          )
    ),

    COLUMN_REFERENCE AS (
        -- Direct masking policies (policy attached directly to the column)
        SELECT
            CONCAT_WS('.', REF_DATABASE_NAME, REF_SCHEMA_NAME, REF_ENTITY_NAME) AS REF_TABLE_IDENTIFIER,
            REF_COLUMN_NAME,
            POLICY_NAME AS REF_POLICY_NAME
        FROM TABLE({{ model.database }}.INFORMATION_SCHEMA.POLICY_REFERENCES(
            ref_entity_name   => '{{ this }}',
            ref_entity_domain => 'TABLE'
        ))
        WHERE POLICY_KIND = 'MASKING_POLICY'

        UNION

        -- Tag-based masking policies (policy inherited via a Snowflake Tag on the column).
        -- ACCOUNT_USAGE includes both direct and tag-based policy references.
        SELECT
            CONCAT_WS('.', REF_DATABASE_NAME, REF_SCHEMA_NAME, REF_ENTITY_NAME) AS REF_TABLE_IDENTIFIER,
            REF_COLUMN_NAME,
            POLICY_NAME AS REF_POLICY_NAME
        FROM SNOWFLAKE.ACCOUNT_USAGE.POLICY_REFERENCES
        WHERE UPPER(REF_DATABASE_NAME) = UPPER('{{ model.database }}')
          AND UPPER(REF_SCHEMA_NAME)   = UPPER('{{ model.schema }}')
          AND UPPER(REF_ENTITY_NAME)   = UPPER('{{ model.alias }}')
          AND REF_ENTITY_DOMAIN        = 'Table'
          AND POLICY_KIND              = 'MASKING_POLICY'
          AND POLICY_STATUS            = 'ACTIVE'
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
