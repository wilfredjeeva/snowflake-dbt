{% macro apply_masking_policy(column_name, policy_name) %}

    {% set policy_parts = policy_name.split('.') %}
    {% set policy_identifier = policy_parts[0] ~ '.' ~ policy_parts[1] ~ '."' ~ policy_parts[2] ~ '"' %}
    
    ALTER TABLE {{ this }}
    MODIFY COLUMN "{{ column_name }}"
    SET MASKING POLICY {{ policy_identifier }}
    
{% endmacro %}