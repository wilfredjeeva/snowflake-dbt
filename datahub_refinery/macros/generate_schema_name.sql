{% macro generate_schema_name(custom_schema_name, node) %}
  {# Expecting models/<db_folder>/<schema_folder>/... #}
  {% set parts = node.fqn %}
  {# Example fqn: [project, bronze_adf, sonitus, sonitus_bronze_monitors] #}
  {% if parts|length >= 3 %}
    {{ parts[2] | upper }}
  {% else %}
    {{ target.schema | upper }}
  {% endif %}
{% endmacro %}
