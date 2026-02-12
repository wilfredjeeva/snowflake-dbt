{% test compare_row_count(model, compare_model) %}

with target_count as (
    select count(*) as bronze_cnt from {{ model }}
),
source_count as (
    select count(*) as landing_cnt from {{ compare_model }}
)
select *
from source_count
join target_count
where source_count.landing_cnt != target_count.bronze_cnt

{% endtest %}
