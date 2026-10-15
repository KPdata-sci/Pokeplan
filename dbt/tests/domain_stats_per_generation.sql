-- Every variety has exactly the five gen-I stats in gen I (with one
-- Special) and six stats in every later generation it exists in.
SELECT p.pokemon_code, g.n AS generation, count(*) AS n_stats
FROM {{ ref('dim_pokemon') }} p
CROSS JOIN generate_series(1, 9) g(n)
JOIN {{ ref('fact_pokemon_stat') }} f
  ON f.pokemon_key = p.pokemon_key AND g.n BETWEEN f.valid_from_generation AND f.valid_to_generation
WHERE p.pokemon_key <> 0
GROUP BY p.pokemon_code, g.n
HAVING count(*) <> CASE WHEN g.n = 1 THEN 5 ELSE 6 END
