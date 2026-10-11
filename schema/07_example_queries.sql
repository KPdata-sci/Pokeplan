-- =====================================================================
-- Pokeplan :: Example questions the star answers.
-- Notice the shape: one fact in the middle, filter/group by dimension
-- attributes, aggregate the measures. That shape is the point of a star.
-- v2 adds questions that only make sense once the model knows the games
-- change over time (Q5-Q10).
-- =====================================================================

-- Q1. Strongest non-legendary Pokémon by Base Stat Total, per generation,
--     counting only each species' standard variety (no megas, no forms).
SELECT species_generation, pokemon_code, base_stat_total
FROM (
    SELECT pp.*, rank() OVER (PARTITION BY species_generation ORDER BY base_stat_total DESC) AS r
    FROM mart.pokemon_profile pp
    WHERE species_class = 'regular' AND form_category = 'default'
) x
WHERE r = 1 ORDER BY species_generation;

-- Q2. Movepool size per Pokémon in Scarlet/Violet, split by learn method.
--     COUNT(DISTINCT move) because a move learnt at two levels is one move.
SELECT p.pokemon_code, lm.learn_method_code, count(DISTINCT m.move_id) AS moves
FROM mart.fact_pokemon_move f
JOIN mart.dim_pokemon p        USING (pokemon_key)
JOIN mart.dim_move m           USING (move_key)
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_learn_method lm  USING (learn_method_key)
WHERE vg.version_group_code = 'scarlet-violet'
GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 20;

-- Q3. Where can I catch a Tentacool in Diamond, and how likely is it?
--     chance_pct is SEMI-ADDITIVE: summing it is only meaningful inside one
--     area + version + method + condition set, and only where the method's
--     chance_unit is 'percent'.
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
  AND em.chance_unit = 'percent'
GROUP BY 1, 2, 3 ORDER BY 4 DESC;

-- Q4. Type effectiveness against a dual-type defender, in gen 9.
--     damage_multiplier is NON-ADDITIVE: combine with a product, not SUM.
--     (Postgres has no PRODUCT(); exp(sum(ln(x))) is the classic trick,
--     with NULLIF so ln() never sees the 0x case.)
SELECT atk.type_code AS attacking,
       p.pokemon_code AS defender,
       CASE WHEN bool_or(f.damage_multiplier = 0) THEN 0
            ELSE round(exp(sum(ln(NULLIF(f.damage_multiplier, 0))))::numeric, 2) END AS multiplier
FROM mart.dim_pokemon p
JOIN mart.fact_pokemon_type pt ON pt.pokemon_key = p.pokemon_key AND pt.is_current
JOIN mart.fact_type_effectiveness f ON f.defending_type_key = pt.type_key
JOIN mart.dim_type atk ON atk.type_key = f.attacking_type_key
JOIN mart.dim_generation g ON g.generation_key = f.generation_key
WHERE p.pokemon_code = 'gyarados' AND g.generation_number = 9
GROUP BY 1, 2 ORDER BY 3 DESC;

-- Q5. POINT-IN-TIME join on a generation-dated fact: the same Gyarados
--     question, asked of every generation. Electric is 4x throughout, but
--     the set of attacking types grows (Dark/Steel in II, Fairy in VI).
SELECT g.generation_number, count(*) AS attacking_types,
       count(*) FILTER (WHERE x.multiplier >= 2) AS weaknesses,
       count(*) FILTER (WHERE x.multiplier = 0)  AS immunities
FROM (
    SELECT f.generation_key, f.attacking_type_key,
           CASE WHEN bool_or(f.damage_multiplier = 0) THEN 0
                ELSE exp(sum(ln(NULLIF(f.damage_multiplier, 0)))) END AS multiplier
    FROM mart.dim_pokemon p
    JOIN mart.dim_generation g0 ON true
    JOIN mart.fact_pokemon_type pt ON pt.pokemon_key = p.pokemon_key
     AND g0.generation_number BETWEEN pt.valid_from_generation AND pt.valid_to_generation
    JOIN mart.fact_type_effectiveness f
      ON f.defending_type_key = pt.type_key AND f.generation_key = g0.generation_key
    WHERE p.pokemon_code = 'gyarados'
    GROUP BY 1, 2
) x
JOIN mart.dim_generation g USING (generation_key)
GROUP BY 1 ORDER BY 1;

-- Q6. SCD TYPE 2 in action: the physical/special split. In Emerald every
--     Fire move is special and every Dark move is special; in
--     Scarlet/Violet each move has its own class. move_in_version_group
--     hides the range join. (It lists every move that existed by then;
--     a game can still leave some out, as Scarlet/Violet did.)
SELECT version_group_code, type_code, effective_damage_class, count(*) AS moves
FROM mart.move_in_version_group
WHERE type_code IN ('fire', 'dark') AND effective_damage_class <> 'status'
  AND version_group_code IN ('emerald', 'scarlet-violet')
GROUP BY 1, 2, 3 ORDER BY 1, 2, 3;

-- Q7. A Pokémon's base stats AS OF a generation (Pikachu got sturdier in
--     gen VI; in gen I it had one Special stat).
SELECT g.n AS generation, s.stat_code, f.base_stat
FROM generate_series(1, 9) AS g(n)
JOIN mart.fact_pokemon_stat f ON g.n BETWEEN f.valid_from_generation AND f.valid_to_generation
JOIN mart.dim_pokemon p ON p.pokemon_key = f.pokemon_key
JOIN mart.dim_stat s    ON s.stat_key = f.stat_key
WHERE p.pokemon_code = 'pikachu' AND g.n IN (1, 5, 6)
ORDER BY 1, s.display_order;

-- Q8. Which Pokémon are in a game? Game -> its regional dexes (bridge) ->
--     species (factless fact). Paldea dex order with current BST.
SELECT d.pokedex_code, e.entry_number, sp.species_code, pp.base_stat_total
FROM mart.dim_version_group vg
JOIN mart.bridge_version_group_pokedex b USING (version_group_key)
JOIN mart.dim_pokedex d                  USING (pokedex_key)
JOIN mart.fact_pokedex_entry e           USING (pokedex_key)
JOIN mart.dim_species sp                 USING (species_key)
JOIN mart.pokemon_profile pp ON pp.species_name = sp.species_name AND pp.form_category = 'default'
WHERE vg.version_group_code = 'scarlet-violet' AND d.pokedex_code = 'paldea'
ORDER BY e.entry_number LIMIT 20;

-- Q9. What does TM26 teach in each game? Same item, different move.
SELECT vg.version_group_code, vg.release_year, m.move_code
FROM mart.fact_machine f
JOIN mart.dim_item i           USING (item_key)
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_move m           USING (move_key)
WHERE i.item_code = 'tm26'
ORDER BY vg.sort_order;

-- Q10. Role-playing dimensions and form-aware evolution: every evolution
--      that needs an item, with the concrete variety it produces.
SELECT fs.species_code AS from_species, tp.pokemon_code AS becomes,
       et.evolution_trigger_code, ui.item_code AS used_item, hi.item_code AS held_item,
       f.region_code
FROM mart.fact_evolution f
JOIN mart.dim_species fs ON fs.species_key = f.from_species_key
JOIN mart.dim_pokemon tp ON tp.pokemon_key = f.to_pokemon_key
JOIN mart.dim_evolution_trigger et USING (evolution_trigger_key)
JOIN mart.dim_item ui ON ui.item_key = f.used_item_key
JOIN mart.dim_item hi ON hi.item_key = f.held_item_key
WHERE f.used_item_key <> 0 OR f.held_item_key <> 0
ORDER BY 1, 2;

-- Q11. Data coverage before you trust an answer: which games have
--      learnsets and wild encounters in this dataset?
SELECT version_group_code, generation_number, game_category, release_year,
       has_learnset_data, has_encounter_data
FROM mart.dim_version_group WHERE version_group_key <> 0
ORDER BY sort_order;
