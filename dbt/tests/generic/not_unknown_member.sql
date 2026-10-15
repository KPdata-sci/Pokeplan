-- A fact row fell back to the Unknown member (key 0) because the dimension
-- row was missing, which means an endpoint was not crawled. Facts keep such
-- rows rather than lose them; this test counts them.
{% test not_unknown_member(model, column_name) %}
SELECT {{ column_name }}
FROM {{ model }}
WHERE {{ column_name }} = 0
{% endtest %}
