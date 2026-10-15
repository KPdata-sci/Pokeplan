-- Generation eras of one pokemon + slot do not overlap.
SELECT a.pokemon_key, a.slot
FROM {{ ref('fact_pokemon_type') }} a
JOIN {{ ref('fact_pokemon_type') }} b
  ON a.pokemon_key = b.pokemon_key AND a.slot = b.slot
 AND a.valid_from_generation < b.valid_from_generation
 AND a.valid_to_generation >= b.valid_from_generation
