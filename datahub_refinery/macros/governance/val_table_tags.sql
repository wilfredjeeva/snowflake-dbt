{% macro val_table_tags () %}

    {% if execute %}

        {# Macro variables #}
        {% set ingestion_layer_required_tags   = ['SENSITIVE_TAG', 'SOURCESYSTEM_TAG'] %}
        {% set consumption_layer_required_tags = ['SENSITIVEDATASET_TAG', 'SOURCESYSTEM_TAG', 'DATASET_TAG'] %}
        {% set database_layer = modules.re.sub('^(DEV|TEST|PREPROD|PROD).', '', model.database | upper) | upper %}
        {% set database_rules = {
            'BRONZE_ADF' : ingestion_layer_required_tags,
            'SILVER'     : ingestion_layer_required_tags,
            'GOLD'       : consumption_layer_required_tags,
            'PLATINUM'   : consumption_layer_required_tags
        } %}

        {# Usage validation #}
        {% if database_layer not in database_rules %}
            {{ return(null) }}
        {% endif %}

        {# Tag validation #}
        {% set validation_tags = database_rules[database_layer] %}

        {% set validate_table_tag_sql %}
            SELECT
                IFF(COUNT(*) = {{ validation_tags | length }}, TRUE, FALSE) AS TGT_COUNT
            FROM TABLE(
                {{ model.database }}.INFORMATION_SCHEMA.TAG_REFERENCES('{{ this }}', 'TABLE')
            )
            WHERE TAG_DATABASE = 'GOVERNANCE' AND TAG_SCHEMA = 'TAGS' AND TAG_NAME IN (
                {% for validation_tag in validation_tags %}
                    '{{ validation_tag }}' {% if not loop.last %}, {% endif %}
                {% endfor %}
            )
            ;
        {% endset %}

        {% set validate_table_tag_result = run_query(validate_table_tag_sql) %}
        {% set validation_passed = validate_table_tag_result.columns[0].values()[0] %}

        {% if not validation_passed %}
            {{ exceptions.raise_compiler_error(
                'Table tag validation failed for ' ~ this ~
                ' | Layer: ' ~ database_layer ~
                ' | Expected tags: ' ~ validation_tags
            ) }}
        {% endif %}

    {% endif %}
{% endmacro %}
