-- =====================================================================
-- Pokeplan :: Example questions the star answers.
-- Notice the shape: one fact in the middle, filter/group by dimension
-- attributes, aggregate the measures. That shape is the point of a star.
-- =====================================================================

-- Q1. Strongest non-legendary pokemon by Base Stat Total, per generation.
SELECT generation_number, pokemon_code, base_stat_total
FROM (
    SELECT pp.*, rank() OVER (PARTITION BY generation_number ORDER BY base_stat_total DESC) AS r
    FROM mart.pokemon_profile pp
    WHERE NOT is_legendary AND NOT is_mythical
) x
WHERE r = 1 ORDER BY generation_number;

-- Q2. Movepool size per pokemon in Scarlet/Violet, split by learn method.
SELECT p.pokemon_code, lm.learn_method_code, count(*) AS moves
FROM mart.fact_pokemon_move f
JOIN mart.dim_pokemon p        USING (pokemon_key)
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_learn_method lm  USING (learn_method_key)
WHERE vg.version_group_code = 'scarlet-violet'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;

-- Q3. Where can I catch a Tentacool in Diamond, and how likely is it?
--     chance_pct is SEMI-ADDITIVE: summing it is only meaningful inside one
--     area + version + method + condition set, so we group by exactly that.
SELECT la.location_area_code, em.encounter_method_code, cs.condition_set_code,
       sum(f.chance_pct) AS total_chance_pct,
       min(f.min_level) AS min_level, max(f.max_level) AS max_level
FROM mart.fact_encounter f
JOIN mart.dim_pokemon p                 USING (pokemon_key)
JOIN mart.dim_version v                 USING (version_key)
JOIN mart.dim_location_area la          USING (location_area_key)
JOIN mart.dim_encounter_method em       USING (encounter_method_key)
JOIN mart.dim_encounter_condition_set cs USING (condition_set_key)
WHERE p.pokemon_code = 'tentacool' AND v.version_code = 'diamond'
GROUP BY 1, 2, 3 ORDER BY 4 DESC;

-- Q4. Type effectiveness of a move against a dual-type defender, in gen 9.
--     damage_multiplier is NON-ADDITIVE: combine with a product, not SUM.
--     (Postgres has no PRODUCT(); exp(sum(ln(x))) is the classic trick,
--     guarded for the 0x case.)
SELECT atk.type_code AS attacking,
       p.pokemon_code AS defender,
       CASE WHEN bool_or(f.damage_multiplier = 0) THEN 0
            ELSE round(exp(sum(ln(f.damage_multiplier)))::numeric, 2) END AS multiplier
FROM mart.dim_pokemon p
JOIN mart.fact_pokemon_type pt ON pt.pokemon_key = p.pokemon_key AND pt.is_current
JOIN mart.fact_type_effectiveness f ON f.defending_type_key = pt.type_key
JOIN mart.dim_type atk ON atk.type_key = f.attacking_type_key
JOIN mart.dim_generation g ON g.generation_key = f.generation_key
WHERE p.pokemon_code = 'gyarados' AND g.generation_number = 9
GROUP BY 1, 2 ORDER BY 3 DESC;

-- Q5. Point-in-time join with the effective-dated type fact:
--     what type was Clefairy in generation 5 vs generation 6?
SELECT g.n AS generation, p.pokemon_code, t.type_code
FROM generate_series(5, 6) AS g(n)
JOIN mart.fact_pokemon_type pt ON g.n BETWEEN pt.valid_from_generation AND pt.valid_to_generation
JOIN mart.dim_pokemon p ON p.pokemon_key = pt.pokemon_key
JOIN mart.dim_type t    ON t.type_key = pt.type_key
WHERE p.pokemon_code = 'clefairy' ORDER BY 1;

-- Q6. Role-playing dimensions: every item-triggered evolution.
SELECT fs.species_code AS from_species, ts.species_code AS to_species,
       et.evolution_trigger_code, ui.item_code AS used_item, hi.item_code AS held_item
FROM mart.fact_evolution f
JOIN mart.dim_species fs ON fs.species_key = f.from_species_key
JOIN mart.dim_species ts ON ts.species_key = f.to_species_key
JOIN mart.dim_evolution_trigger et USING (evolution_trigger_key)
JOIN mart.dim_item ui ON ui.item_key = f.used_item_key
JOIN mart.dim_item hi ON hi.item_key = f.held_item_key
WHERE f.used_item_key <> 0 OR f.held_item_key <> 0;
