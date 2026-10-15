-- The type chart has 15 types in gen I, 17 in gens II-V, 18 from gen VI.
SELECT g.generation_number, count(DISTINCT f.attacking_type_key) AS n_types
FROM {{ ref('fact_type_effectiveness') }} f
JOIN {{ ref('dim_generation') }} g USING (generation_key)
GROUP BY 1
HAVING count(DISTINCT f.attacking_type_key) <> CASE WHEN g.generation_number = 1 THEN 15
                                                    WHEN g.generation_number < 6 THEN 17 ELSE 18 END
