-- Domain tests check facts any Pokémon player could verify by hand. They
-- catch a model that is internally consistent but wrong about the games.
--
-- 1,025 species, and the per-generation counts match the games
-- (151 in gen I, 100 in gen II, ... 120 in gen IX).
SELECT gi.generation_number, gi.new_species, count(s.species_key) AS species_in_mart
FROM {{ ref('generation_info') }} gi
LEFT JOIN {{ ref('dim_species') }} s ON s.generation_number = gi.generation_number
GROUP BY 1, 2
HAVING count(s.species_key) <> gi.new_species
