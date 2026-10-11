-- =====================================================================
-- Pokeplan :: Data tests. Every query should return ZERO rows.
-- Run after CALL mart.load(...). Each one tests a promise the schema makes.
-- =====================================================================

-- 1. GRAIN tests: the declared grain is unique in staging.
--    (Primary keys enforce it in the mart, but catching it in staging tells
--    you *which* assumption about the source broke.)
SELECT 'grain: stg.pokemon_move' AS test, pokemon_id, move_id, version_group_id, learn_method_id
FROM stg.pokemon_move GROUP BY 2,3,4,5 HAVING count(*) > 1;

SELECT 'grain: stg.encounter' AS test, location_area_id, pokemon_id, version_id, slot_seq
FROM stg.encounter GROUP BY 2,3,4,5 HAVING count(*) > 1;

SELECT 'grain: stg.evolution' AS test, evolution_chain_id, to_species_id, detail_seq
FROM stg.evolution GROUP BY 2,3,4 HAVING count(*) > 1;

-- 2. REFERENTIAL tests: facts that fell back to the Unknown member (key 0)
--    mean a dimension was not crawled. Expect zero after a full crawl.
SELECT 'unknown key: fact_pokemon_move' AS test, count(*) FROM mart.fact_pokemon_move
WHERE 0 IN (pokemon_key, move_key, version_group_key, learn_method_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_encounter' AS test, count(*) FROM mart.fact_encounter
WHERE 0 IN (location_area_key, pokemon_key, version_key, encounter_method_key) HAVING count(*) > 0;

SELECT 'unknown key: fact_pokemon_stat' AS test, count(*) FROM mart.fact_pokemon_stat
WHERE 0 IN (pokemon_key, stat_key) HAVING count(*) > 0;

-- 3. BUSINESS RULE tests.
-- Every pokemon has exactly 6 core stats.
SELECT 'rule: six stats' AS test, pokemon_key, count(*) FROM mart.fact_pokemon_stat
GROUP BY pokemon_key HAVING count(*) <> 6;

-- A type chart generation is a full square (n types x n types).
SELECT 'rule: dense type chart' AS test, generation_key, count(*),
       count(DISTINCT attacking_type_key) AS n
FROM mart.fact_type_effectiveness GROUP BY generation_key
HAVING count(*) <> count(DISTINCT attacking_type_key) ^ 2;

-- Type eras for one pokemon+slot do not overlap.
SELECT 'rule: type eras overlap' AS test, a.pokemon_key, a.slot
FROM mart.fact_pokemon_type a
JOIN mart.fact_pokemon_type b
  ON a.pokemon_key = b.pokemon_key AND a.slot = b.slot
 AND a.valid_from_generation < b.valid_from_generation
 AND a.valid_to_generation >= b.valid_from_generation;

-- Encounter levels make sense.
SELECT 'rule: min_level <= max_level' AS test, * FROM mart.fact_encounter
WHERE min_level > max_level;
