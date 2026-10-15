-- Each generation's type chart is a full square (n types x n types).
SELECT generation_key, count(*) AS n_rows, count(DISTINCT attacking_type_key) AS n_types
FROM {{ ref('fact_type_effectiveness') }}
GROUP BY generation_key
HAVING count(*) <> count(DISTINCT attacking_type_key) ^ 2
