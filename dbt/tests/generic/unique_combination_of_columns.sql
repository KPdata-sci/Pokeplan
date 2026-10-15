-- The declared grain is unique: no two rows share these columns.
-- (dbt_utils has the same test; this copy keeps the project free of packages.)
{% test unique_combination_of_columns(model, combination_of_columns) %}
SELECT {{ combination_of_columns | join(', ') }}, count(*) AS n_rows
FROM {{ model }}
GROUP BY {{ combination_of_columns | join(', ') }}
HAVING count(*) > 1
{% endtest %}
