-- Clefairy was Normal up to gen V and Fairy from gen VI; Magnemite gained
-- Steel in gen II.
SELECT x.*, t.type_code AS actual
FROM (VALUES ('clefairy', 5, 1, 'normal'), ('clefairy', 6, 1, 'fairy'),
             ('magnemite', 1, 2, NULL),    ('magnemite', 2, 2, 'steel')) AS x(pokemon, gen, slot, expected)
JOIN {{ ref('dim_pokemon') }} p ON p.pokemon_code = x.pokemon
LEFT JOIN {{ ref('fact_pokemon_type') }} pt
       ON pt.pokemon_key = p.pokemon_key AND pt.slot = x.slot
      AND x.gen BETWEEN pt.valid_from_generation AND pt.valid_to_generation
LEFT JOIN {{ ref('dim_type') }} t ON t.type_key = pt.type_key
WHERE t.type_code IS DISTINCT FROM x.expected
