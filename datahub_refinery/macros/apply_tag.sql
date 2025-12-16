{% macro apply_tag(column_name, tag_name, tag_value) %}

    {% set tag_parts = tag_name.split('.') %}
    {% set tag_identifier = tag_parts[0] ~ '.' ~ tag_parts[1] ~ '."' ~ tag_parts[2] ~ '"' %}
    
    ALTER TABLE {{ this }}
    MODIFY COLUMN "{{ column_name }}"
    SET TAG {{ tag_identifier }} = '{{ tag_value }}';
    
{% endmacro %}