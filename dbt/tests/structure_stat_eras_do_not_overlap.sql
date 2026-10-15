-- Generation eras of one pokemon + stat do not overlap.
SELECT a.pokemon_key, a.stat_key
FROM {{ ref('fact_pokemon_stat') }} a
JOIN {{ ref('fact_pokemon_stat') }} b
  ON a.pokemon_key = b.pokemon_key AND a.stat_key = b.stat_key
 AND a.valid_from_generation < b.valid_from_generation
 AND a.valid_to_generation >= b.valid_from_generation
