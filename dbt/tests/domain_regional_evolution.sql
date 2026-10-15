-- Regional evolution: Pikachu becomes Alolan Raichu only via an Alola rule.
SELECT 'no pikachu -> raichu-alola rule in alola' AS problem
WHERE NOT EXISTS (
    SELECT 1 FROM {{ ref('fact_evolution') }} f
    JOIN {{ ref('dim_pokemon') }} fp ON fp.pokemon_key = f.from_pokemon_key
    JOIN {{ ref('dim_pokemon') }} tp ON tp.pokemon_key = f.to_pokemon_key
    WHERE fp.pokemon_code = 'pikachu' AND tp.pokemon_code = 'raichu-alola' AND f.region_code = 'alola')
