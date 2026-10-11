-- =====================================================================
-- Pokeplan :: Data tests. Every query should return ZERO rows.
-- Run after CALL mart.load(...). Each one tests a promise the schema makes.
--   1. GRAIN       the declared grain is unique
--   2. REFERENTIAL facts did not fall back to the Unknown member
--   3. STRUCTURE   ranges do not overlap, squares are square
--   4. DOMAIN      facts any Pokémon player could check by hand. These are
--                  the most valuable tests: they catch a model that is
--                  internally consistent but wrong about the games.
--   5. WARNINGS    known quirks of the SOURCE data. These DO return rows;
--                  the README records how many, so a change is noticed.
-- =====================================================================

-- 1. GRAIN tests: the declared grain is unique in staging.
--    (Primary keys enforce it in the mart, but catching it in staging tells
--    you *which* assumption about the source broke.)
SELECT 'grain: stg.pokemon_move' AS test, pokemon_id, move_id, version_group_id, learn_method_id, level_learned_at
FROM stg.pokemon_move GROUP BY 2,3,4,5,6 HAVING count(*) > 1;

SELECT 'grain: stg.encounter' AS test, location_area_id, pokemon_id, version_id, slot_seq
FROM stg.encounter GROUP BY 2,3,4,5 HAVING count(*) > 1;

SELECT 'grain: stg.evolution' AS test, evolution_chain_id, to_species_id, detail_seq
FROM stg.evolution GROUP BY 2,3,4 HAVING count(*) > 1;

SELECT 'grain: stg.move_era' AS test, move_id, valid_from_order
FROM stg.move_era GROUP BY 2,3 HAVING count(*) > 1;

-- 2. REFERENTIAL tests: facts that fell back to the Unknown member (key 0)
--    mean a dimension was not crawled. Expect zero after a full crawl.
SELECT 'unknown key: fact_pokemon_move' AS test, count(*) FROM mart.fact_pokemon_move
WHERE 0 IN (pokemon_key, move_key, version_group_key, learn_method_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_encounter' AS test, count(*) FROM mart.fact_encounter
WHERE 0 IN (location_area_key, pokemon_key, version_key, encounter_method_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_pokemon_stat' AS test, count(*) FROM mart.fact_pokemon_stat
WHERE 0 IN (pokemon_key, stat_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_evolution' AS test, count(*) FROM mart.fact_evolution
WHERE 0 IN (from_species_key, to_species_key, from_pokemon_key, to_pokemon_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_machine' AS test, count(*) FROM mart.fact_machine
WHERE 0 IN (item_key, version_group_key, move_key) HAVING count(*) > 0;

SELECT 'unmapped seed: version group missing from ref.version_group_info' AS test, version_group_code
FROM mart.dim_version_group WHERE version_group_key <> 0 AND game_category IS NULL;

-- 3. STRUCTURE tests.
-- Move eras of one move tile the timeline: no gaps, no overlaps, one current.
SELECT 'structure: move eras' AS test, move_id
FROM mart.dim_move WHERE move_key <> 0
GROUP BY move_id
HAVING count(*) FILTER (WHERE is_current) <> 1
    OR min(valid_from_order) <> 0
    OR sum(valid_to_order - valid_from_order + 1) <> 10000;

-- Generation eras for one pokemon + slot/stat do not overlap.
SELECT 'structure: type eras overlap' AS test, a.pokemon_key, a.slot
FROM mart.fact_pokemon_type a
JOIN mart.fact_pokemon_type b
  ON a.pokemon_key = b.pokemon_key AND a.slot = b.slot
 AND a.valid_from_generation < b.valid_from_generation
 AND a.valid_to_generation >= b.valid_from_generation;

SELECT 'structure: stat eras overlap' AS test, a.pokemon_key, a.stat_key
FROM mart.fact_pokemon_stat a
JOIN mart.fact_pokemon_stat b
  ON a.pokemon_key = b.pokemon_key AND a.stat_key = b.stat_key
 AND a.valid_from_generation < b.valid_from_generation
 AND a.valid_to_generation >= b.valid_from_generation;

-- A type chart generation is a full square (n types x n types).
SELECT 'structure: dense type chart' AS test, generation_key, count(*),
       count(DISTINCT attacking_type_key) AS n
FROM mart.fact_type_effectiveness GROUP BY generation_key
HAVING count(*) <> count(DISTINCT attacking_type_key) ^ 2;

-- Encounter levels make sense.
SELECT 'structure: min_level <= max_level' AS test, * FROM mart.fact_encounter
WHERE min_level > max_level;

-- 4. DOMAIN tests.
-- 1,025 species, and the per-generation counts match the games
-- (151 in gen I, 100 in gen II, ... 120 in gen IX).
SELECT 'domain: species per generation' AS test, gi.generation_number, gi.new_species, count(s.species_key)
FROM ref.generation_info gi
LEFT JOIN mart.dim_species s ON s.generation_number = gi.generation_number
GROUP BY 2, 3 HAVING count(s.species_key) <> gi.new_species;

-- Every species has exactly one default variety.
SELECT 'domain: one default variety per species' AS test, species_id, count(*)
FROM mart.dim_pokemon WHERE pokemon_key <> 0 AND is_default_form
GROUP BY species_id HAVING count(*) <> 1;

-- The type chart has 15 types in gen I, 17 in gens II-V, 18 from gen VI.
SELECT 'domain: types per generation' AS test, g.generation_number, count(DISTINCT f.attacking_type_key)
FROM mart.fact_type_effectiveness f JOIN mart.dim_generation g USING (generation_key)
GROUP BY 2
HAVING count(DISTINCT f.attacking_type_key) <> CASE WHEN g.generation_number = 1 THEN 15
                                                    WHEN g.generation_number < 6 THEN 17 ELSE 18 END;

-- Known type-chart changes (Bulbapedia, Type chart): Ghost could not hit
-- Psychic in gen I; Bug beat Poison in gen I; Steel resisted Ghost and
-- Dark until gen V.
SELECT 'domain: type chart history' AS test, a.type_code, d.type_code, g.generation_number,
       f.damage_multiplier, x.expected
FROM (VALUES ('ghost','psychic',1,0.0), ('ghost','psychic',2,2.0),
             ('bug','poison',1,2.0),    ('bug','poison',2,0.5),
             ('ice','fire',1,1.0),      ('ice','fire',2,0.5),
             ('ghost','steel',5,0.5),   ('ghost','steel',6,1.0),
             ('dark','steel',5,0.5),    ('dark','steel',6,1.0),
             ('dragon','fairy',6,0.0)) AS x(atk, dfn, gen, expected)
JOIN mart.dim_type a ON a.type_code = x.atk
JOIN mart.dim_type d ON d.type_code = x.dfn
JOIN mart.dim_generation g ON g.generation_number = x.gen
LEFT JOIN mart.fact_type_effectiveness f
       ON f.attacking_type_key = a.type_key AND f.defending_type_key = d.type_key
      AND f.generation_key = g.generation_key
WHERE f.damage_multiplier IS DISTINCT FROM x.expected;

-- Clefairy was Normal up to gen V and Fairy from gen VI; Magnemite gained
-- Steel in gen II.
SELECT 'domain: typing history' AS test, x.*
FROM (VALUES ('clefairy', 5, 1, 'normal'), ('clefairy', 6, 1, 'fairy'),
             ('magnemite', 1, 2, NULL),    ('magnemite', 2, 2, 'steel')) AS x(pokemon, gen, slot, expected)
JOIN mart.dim_pokemon p ON p.pokemon_code = x.pokemon
LEFT JOIN mart.fact_pokemon_type pt
       ON pt.pokemon_key = p.pokemon_key AND pt.slot = x.slot
      AND x.gen BETWEEN pt.valid_from_generation AND pt.valid_to_generation
LEFT JOIN mart.dim_type t ON t.type_key = pt.type_key
WHERE t.type_code IS DISTINCT FROM x.expected;

-- Every variety has exactly the five gen-I stats in gen I (with one
-- Special) and six stats in every later generation it exists in.
SELECT 'domain: stats per generation' AS test, p.pokemon_code, g.n, count(*)
FROM mart.dim_pokemon p
CROSS JOIN generate_series(1, 9) g(n)
JOIN mart.fact_pokemon_stat f
  ON f.pokemon_key = p.pokemon_key AND g.n BETWEEN f.valid_from_generation AND f.valid_to_generation
WHERE p.pokemon_key <> 0
GROUP BY p.pokemon_code, g.n
HAVING count(*) <> CASE WHEN g.n = 1 THEN 5 ELSE 6 END;

-- Nothing has an ability before gen III or a hidden ability before gen V.
SELECT 'domain: ability timeline' AS test, * FROM mart.fact_pokemon_ability
WHERE valid_from_generation < 3 OR (is_hidden AND valid_from_generation < 5);

-- Nothing exists before it was introduced: no typing for Alolan Raichu in gen I.
SELECT 'domain: no history before introduction' AS test, p.pokemon_code, t.valid_from_generation
FROM mart.fact_pokemon_type t JOIN mart.dim_pokemon p USING (pokemon_key)
WHERE t.valid_from_generation < p.introduced_generation;

-- Physical/special split: Bite was a Normal physical move in gen I, a
-- Dark SPECIAL move in gens II-III (all Dark moves were special), and Dark
-- physical from gen IV. Fire Punch was special until gen III.
SELECT 'domain: move history' AS test, x.*, m.type_code, m.effective_damage_class
FROM (VALUES ('bite', 'red-blue', 'normal', 'physical'),
             ('bite', 'gold-silver', 'dark', 'special'),
             ('bite', 'diamond-pearl', 'dark', 'physical'),
             ('fire-punch', 'emerald', 'fire', 'special'),
             ('fire-punch', 'scarlet-violet', 'fire', 'physical'),
             ('charm', 'black-white', 'normal', 'status'),
             ('charm', 'x-y', 'fairy', 'status')) AS x(move, game, exp_type, exp_class)
JOIN mart.move_in_version_group m ON m.move_code = x.move AND m.version_group_code = x.game
WHERE (m.type_code, m.effective_damage_class) IS DISTINCT FROM (x.exp_type, x.exp_class);

-- TM numbers mean different moves in different games.
SELECT 'domain: TM26' AS test, x.*, mv.move_code
FROM (VALUES ('red-blue', 'earthquake'), ('sword-shield', 'scary-face')) AS x(game, expected)
JOIN mart.dim_version_group vg ON vg.version_group_code = x.game
JOIN mart.dim_item i ON i.item_code = 'tm26'
LEFT JOIN mart.fact_machine f ON f.item_key = i.item_key AND f.version_group_key = vg.version_group_key
LEFT JOIN mart.dim_move mv ON mv.move_key = f.move_key
WHERE mv.move_code IS DISTINCT FROM x.expected;

-- Regional evolution: Pikachu becomes Alolan Raichu only via an Alola rule.
SELECT 'domain: regional evolution' AS test
WHERE NOT EXISTS (
    SELECT 1 FROM mart.fact_evolution f
    JOIN mart.dim_pokemon fp ON fp.pokemon_key = f.from_pokemon_key
    JOIN mart.dim_pokemon tp ON tp.pokemon_key = f.to_pokemon_key
    WHERE fp.pokemon_code = 'pikachu' AND tp.pokemon_code = 'raichu-alola' AND f.region_code = 'alola');

-- Battle-only transformations are never found in the wild. The one
-- exception is real: Gigantamax Pokémon are met in Sword/Shield Max Raids.
SELECT 'domain: no wild megas' AS test, p.pokemon_code, m.encounter_method_code, count(*)
FROM mart.fact_encounter f
JOIN mart.dim_pokemon p USING (pokemon_key)
JOIN mart.dim_encounter_method m USING (encounter_method_key)
WHERE p.form_category IN ('mega', 'primal', 'gigantamax') AND m.method_group <> 'raid'
GROUP BY 2, 3;

-- 5. WARNINGS (expected to return rows; see README for the current count).
-- Classic encounter tables should add up to at most 100% per area, game,
-- method and condition set. A few in the source do not: horde encounters
-- (X/Y, ORAS), Sun/Moon grass where day and night tables are not tagged
-- with a time condition, some HGSS/Crystal fishing tables. Overworld and
-- raid 'chances' are weights and are excluded.
SELECT 'warning: percent odds > 100' AS test, v.version_group_code, m.encounter_method_code,
       count(*) AS groups, max(total) AS worst_total
FROM (
    SELECT version_key, encounter_method_key, location_area_key, condition_set_key,
           sum(chance_pct) AS total
    FROM mart.fact_encounter
    GROUP BY 1, 2, 3, 4
) x
JOIN mart.dim_encounter_method m USING (encounter_method_key)
JOIN mart.dim_version v USING (version_key)
WHERE m.chance_unit = 'percent' AND x.total > 100
GROUP BY 2, 3 ORDER BY 2, 3;

-- Games with no learnset or encounter data in PokeAPI (coverage gaps).
SELECT 'warning: coverage gap' AS test, version_group_code, game_category,
       has_learnset_data, has_encounter_data
FROM mart.dim_version_group
WHERE version_group_key <> 0 AND NOT (has_learnset_data AND has_encounter_data)
ORDER BY sort_order;
