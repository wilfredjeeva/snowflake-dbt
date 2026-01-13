{% test compare_row_count(model, target_database, target_schema, target_table) %}
with source_count as (
    select count(*) as cnt from {{ model }}
),
target_count as (
    select count(*) as cnt from {{ target_database }}.{{ target_schema }}.{{ target_table }}
)
select *
from source_count
join target_count
where source_count.cnt != target_count.cnt
{% endtest %}