-- Serving layer: the views the dashboard reads. One view per dashboard dataset,
-- built only from mart tables, so the dashboard never touches raw or staging.
-- Run after dbt build (see ../dbt), which creates the mart tables and tests them.

CREATE SCHEMA IF NOT EXISTS serve;

-- One row per species (its default form) with today's types and base stats.
CREATE OR REPLACE VIEW serve.pokemon_card AS
WITH stats AS (
    SELECT f.pokemon_key,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'hp')              AS hp,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'attack')          AS attack,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'defense')         AS defense,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'special-attack')  AS special_attack,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'special-defense') AS special_defense,
           max(f.base_stat) FILTER (WHERE s.stat_code = 'speed')           AS speed
    FROM mart.fact_pokemon_stat f
    JOIN mart.dim_stat s USING (stat_key)
    WHERE f.is_current
    GROUP BY f.pokemon_key
), types AS (
    SELECT f.pokemon_key,
           max(t.type_name) FILTER (WHERE f.slot = 1) AS type_1,
           max(t.type_name) FILTER (WHERE f.slot = 2) AS type_2
    FROM mart.fact_pokemon_type f
    JOIN mart.dim_type t USING (type_key)
    WHERE f.is_current
    GROUP BY f.pokemon_key
)
SELECT p.species_id                         AS dex_no,
       p.species_name                       AS name,
       p.species_generation                 AS generation,
       CASE WHEN p.is_mythical THEN 'mythical'
            WHEN p.is_legendary THEN 'legendary'
            ELSE 'regular' END              AS rarity,
       ty.type_1, ty.type_2,
       st.hp, st.attack, st.defense, st.special_attack, st.special_defense, st.speed,
       st.hp + st.attack + st.defense + st.special_attack + st.special_defense + st.speed AS base_stat_total,
       -- added for the detail panel; new columns go last so CREATE OR REPLACE keeps working
       sp.genus, p.height_m, p.weight_kg, sp.evolution_chain_id, p.capture_rate,
       NULLIF(p.habitat, '') AS habitat, p.is_baby
FROM mart.dim_pokemon p
JOIN stats st USING (pokemon_key)
JOIN types ty USING (pokemon_key)
JOIN mart.dim_species sp ON sp.species_id = p.species_id
WHERE p.is_default_form;

-- The type chart as it stood in each generation (standard types only).
CREATE OR REPLACE VIEW serve.type_chart AS
SELECT g.generation_number AS generation,
       a.type_name         AS attacking,
       d.type_name         AS defending,
       f.damage_multiplier AS multiplier
FROM mart.fact_type_effectiveness f
JOIN mart.dim_generation g USING (generation_key)
JOIN mart.dim_type a ON a.type_key = f.attacking_type_key
JOIN mart.dim_type d ON d.type_key = f.defending_type_key;

-- Generations with their names and years, for labels.
CREATE OR REPLACE VIEW serve.generation AS
SELECT generation_number AS generation, roman, generation_name, main_region_code AS region,
       first_release_year AS year
FROM mart.dim_generation
WHERE generation_number > 0;

-- What the last pipeline run did.
CREATE OR REPLACE VIEW serve.pipeline_run AS
SELECT b.batch_id, b.status, b.started_at, b.finished_at, b.notes,
       b.rows_fetched AS raw_responses, b.rows_changed AS raw_changed,
       cardinality(b.endpoints) AS endpoints
FROM etl.load_batch b
ORDER BY b.batch_id DESC
LIMIT 1;

-- ---------------------------------------------------------------------
-- Browsing views: games, moves, items, evolutions. Small ones are built
-- into the page; the per-game ones are split into one file per game.
-- Pokémon are identified by national dex number (dex_no) throughout.
-- ---------------------------------------------------------------------

-- Each Pokémon's abilities today (default form). Slot 3 is the hidden one.
CREATE OR REPLACE VIEW serve.pokemon_ability AS
SELECT p.species_id AS dex_no, f.slot, a.ability_name, f.is_hidden, a.short_effect
FROM mart.fact_pokemon_ability f
JOIN mart.dim_pokemon p USING (pokemon_key)
JOIN mart.dim_ability a USING (ability_key)
WHERE f.is_current AND p.is_default_form;

-- Every game (version group) in release order, with what PokeAPI covers.
CREATE OR REPLACE VIEW serve.game AS
SELECT vg.version_group_code AS game, vg.sort_order,
       string_agg(v.version_name, ' / ' ORDER BY v.version_id) AS name,
       string_agg(v.version_code, ',' ORDER BY v.version_id)   AS versions,
       vg.generation_number AS generation, vg.release_year AS year, vg.game_category AS category,
       vg.base_version_group_code AS base_game, vg.region_codes AS regions,
       vg.has_learnset_data, vg.has_encounter_data
FROM mart.dim_version_group vg
JOIN mart.dim_version v ON v.version_group_id = vg.version_group_id
WHERE vg.version_group_key <> 0
GROUP BY vg.version_group_key;

-- Which Pokémon each game's own Pokédex lists, and at what number.
CREATE OR REPLACE VIEW serve.game_pokedex AS
SELECT vg.version_group_code AS game, d.pokedex_name, sp.species_id AS dex_no, f.entry_number
FROM mart.bridge_version_group_pokedex b
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_pokedex d USING (pokedex_key)
JOIN mart.fact_pokedex_entry f USING (pokedex_key)
JOIN mart.dim_species sp USING (species_key);

-- The Pokédex text each game version shows for each species.
CREATE OR REPLACE VIEW serve.pokedex_text AS
SELECT v.version_group_code AS game, v.version_name, sp.species_id AS dex_no, f.flavor_text
FROM mart.fact_species_flavor_text f
JOIN mart.dim_version v USING (version_key)
JOIN mart.dim_species sp USING (species_key);

-- Every move as it is today.
CREATE OR REPLACE VIEW serve.move AS
SELECT m.move_id, m.move_name, t.type_name, m.effective_damage_class AS damage_class,
       m.power, m.accuracy, m.pp, m.priority, m.introduced_generation AS generation,
       m.short_effect, m.description,
       (SELECT count(*) FROM mart.dim_move e WHERE e.move_id = m.move_id) AS eras
FROM mart.dim_move m
LEFT JOIN mart.dim_type t ON t.type_code = m.type_code
WHERE m.is_current AND m.move_key <> 0;

-- How each move behaved in each era (a range of games by release order).
-- Bite is Normal in Red/Blue and Dark from Gold/Silver on.
CREATE OR REPLACE VIEW serve.move_era AS
SELECT m.move_id, m.valid_from_order, m.valid_to_order, t.type_name,
       m.effective_damage_class AS damage_class, m.power, m.accuracy, m.pp
FROM mart.dim_move m
LEFT JOIN mart.dim_type t ON t.type_code = m.type_code
WHERE m.move_key <> 0;

-- Which moves each Pokémon (default form) learns in each game, and how.
CREATE OR REPLACE VIEW serve.learnset AS
SELECT vg.version_group_code AS game, p.species_id AS dex_no, m.move_id,
       lm.learn_method_code AS method, f.level_learned_at AS level
FROM mart.fact_pokemon_move f
JOIN mart.dim_pokemon p USING (pokemon_key)
JOIN mart.dim_move m USING (move_key)
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_learn_method lm USING (learn_method_key)
WHERE p.is_default_form;

-- What each TM, HM and TR teaches in each game.
CREATE OR REPLACE VIEW serve.machine AS
SELECT vg.version_group_code AS game, i.item_id, f.machine_kind AS kind, f.machine_number AS number,
       m.move_id
FROM mart.fact_machine f
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_item i USING (item_key)
JOIN mart.dim_move m USING (move_key);

-- Every item. A TM's bag text describes whichever move it teaches in the
-- newest game, so machines get no description here (serve.machine says it).
CREATE OR REPLACE VIEW serve.item AS
SELECT item_id, item_name, category, NULLIF(cost, 0) AS cost, short_effect,
       CASE WHEN machine_kind IS NULL THEN description END AS description,
       machine_kind, is_holdable, item_code
FROM mart.dim_item
WHERE item_key <> 0;

-- Items wild Pokémon may be holding, per game version.
CREATE OR REPLACE VIEW serve.held_item AS
SELECT v.version_group_code AS game, v.version_name, p.species_id AS dex_no,
       NULLIF(p.form_region_code, '') AS form, i.item_id, f.rarity_pct
FROM mart.fact_pokemon_held_item f
JOIN mart.dim_pokemon p USING (pokemon_key)
JOIN mart.dim_item i USING (item_key)
JOIN mart.dim_version v USING (version_key);

-- Where to catch each Pokémon, per game version: one row per place x
-- Pokémon x method x conditions, with the level range and summed chance.
-- chance_unit says whether the chance is a percentage.
CREATE OR REPLACE VIEW serve.encounter AS
SELECT v.version_group_code AS game, v.version_name,
       COALESCE(NULLIF(la.location_area_name, ''), la.location_name, la.location_area_code) AS place,
       la.region_code AS region, p.species_id AS dex_no, NULLIF(p.form_region_code, '') AS form,
       em.encounter_method_name AS method, em.chance_unit,
       NULLIF(cs.condition_set_code, '') AS conditions,
       min(f.min_level) AS min_level, max(f.max_level) AS max_level, sum(f.chance_pct) AS chance
FROM mart.fact_encounter f
JOIN mart.dim_version v USING (version_key)
JOIN mart.dim_location_area la USING (location_area_key)
JOIN mart.dim_pokemon p USING (pokemon_key)
JOIN mart.dim_encounter_method em USING (encounter_method_key)
JOIN mart.dim_encounter_condition_set cs USING (condition_set_key)
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9;

-- Evolutions with the condition written out in words, e.g.
-- "Use Thunder Stone, in Alola" or "Level up, with high friendship, at night".
CREATE OR REPLACE VIEW serve.evolution AS
SELECT e.evolution_chain_id AS chain_id, fs.species_id AS from_dex, ts.species_id AS to_dex,
       NULLIF(tp.form_region_code, '') AS to_form, e.detail_seq, e.stage,
       NULLIF(ui.item_id, 0) AS used_item_id, NULLIF(hi.item_id, 0) AS held_item_id,
       concat_ws(', ',
         CASE tr.evolution_trigger_code
              WHEN 'level-up' THEN COALESCE('Level ' || e.min_level, 'Level up')
              WHEN 'trade'    THEN 'Trade'
              WHEN 'use-item' THEN 'Use ' || NULLIF(ui.item_name, '')
              ELSE NULLIF(tr.evolution_trigger_name, '') END,
         'holding ' || NULLIF(hi.item_name, ''),
         'knowing ' || NULLIF(km.move_name, ''),
         'knowing a ' || NULLIF(kt.type_name, '') || '-type move',
         'after using ' || NULLIF(um.move_name, '') || COALESCE(' ' || e.min_move_count || ' times', ''),
         CASE WHEN e.min_happiness IS NOT NULL THEN 'with high friendship' END,
         CASE WHEN e.min_beauty IS NOT NULL THEN 'with high Beauty' END,
         CASE WHEN e.min_affection IS NOT NULL THEN 'with high affection' END,
         CASE e.time_of_day WHEN 'day' THEN 'during the day' WHEN 'night' THEN 'at night'
                            WHEN 'dusk' THEN 'at dusk' WHEN 'full-moon' THEN 'under a full moon' END,
         CASE e.gender_id WHEN 1 THEN 'if female' WHEN 2 THEN 'if male' END,
         'at ' || (SELECT min(la.location_name) FROM mart.dim_location_area la
                    WHERE la.location_id = e.location_id),
         'in ' || initcap(NULLIF(e.region_code, '')),
         'with ' || NULLIF(ps.species_name, '') || ' in the party',
         'with a ' || NULLIF(pt.type_name, '') || '-type Pokémon in the party',
         'for ' || NULLIF(xs.species_name, ''),
         CASE WHEN e.needs_overworld_rain THEN 'while it is raining' END,
         CASE WHEN e.turn_upside_down THEN 'holding the console upside down' END,
         CASE e.relative_physical_stats WHEN 1 THEN 'if Attack is higher than Defense'
                                        WHEN 0 THEN 'if Attack equals Defense'
                                        WHEN -1 THEN 'if Defense is higher than Attack' END,
         'after walking ' || e.min_steps || ' steps',
         'after losing at least ' || e.min_damage_taken || ' HP',
         CASE WHEN e.needs_multiplayer THEN 'in a Union Circle' END
       ) AS how,
       vg.version_group_code AS since_game
FROM mart.fact_evolution e
JOIN mart.dim_species fs ON fs.species_key = e.from_species_key
JOIN mart.dim_species ts ON ts.species_key = e.to_species_key
JOIN mart.dim_pokemon tp ON tp.pokemon_key = e.to_pokemon_key
JOIN mart.dim_evolution_trigger tr USING (evolution_trigger_key)
JOIN mart.dim_version_group vg USING (version_group_key)
JOIN mart.dim_item ui ON ui.item_key = e.used_item_key
JOIN mart.dim_item hi ON hi.item_key = e.held_item_key
JOIN mart.dim_move km ON km.move_key = e.known_move_key
JOIN mart.dim_move um ON um.move_key = e.used_move_key
JOIN mart.dim_type kt ON kt.type_key = e.known_move_type_key
JOIN mart.dim_type pt ON pt.type_key = e.party_type_key
JOIN mart.dim_species ps ON ps.species_key = e.party_species_key
JOIN mart.dim_species xs ON xs.species_key = e.trade_species_key;
