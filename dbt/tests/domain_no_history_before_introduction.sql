-- Nothing exists before it was introduced: no typing for Alolan Raichu in gen I.
SELECT p.pokemon_code, t.valid_from_generation, p.introduced_generation
FROM {{ ref('fact_pokemon_type') }} t
JOIN {{ ref('dim_pokemon') }} p USING (pokemon_key)
WHERE t.valid_from_generation < p.introduced_generation
