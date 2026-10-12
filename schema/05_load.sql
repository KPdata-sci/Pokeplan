-- =====================================================================
-- Pokeplan :: Load staging -> mart
-- ---------------------------------------------------------------------
-- Usage:  CALL mart.load(<batch_id>);
-- Patterns:
--   * Idempotent: running it twice with the same raw data changes nothing.
--   * Dimensions: UPSERT on the natural key (INSERT ... ON CONFLICT). The
--     surrogate key of an existing member never changes. The row hash
--     skips no-op updates (SCD type 1).
--   * dim_move is SCD type 2: one row per (move_id, era). Eras are upserted
--     on (move_id, valid_from_order); an era that disappeared from the
--     source (because the API's history was corrected) is deleted.
--   * Facts: full refresh inside one transaction (TRUNCATE + INSERT).
--     The whole PokeAPI dataset is small, so this is the simplest correct
--     choice. Facts are truncated FIRST so stale move eras can be removed.
--   * Lookups of surrogate keys COALESCE to 0 (the Unknown member), so a
--     fact row is never lost because a dimension row is missing; 06_tests
--     counts how often that happens instead.
--   * Domain rules come from the ref schema (02_reference.sql), not from
--     literals in this file: e.g. ability rows are clamped to start no
--     earlier than ref.mechanic 'abilities'.
-- =====================================================================

CREATE OR REPLACE PROCEDURE mart.load(p_batch bigint)
LANGUAGE plpgsql
AS $$
DECLARE
    v_abilities_gen  smallint := (SELECT introduced_generation FROM ref.mechanic WHERE mechanic_code = 'abilities');
    v_hidden_gen     smallint := (SELECT introduced_generation FROM ref.mechanic WHERE mechanic_code = 'hidden-abilities');
    v_split_gen      smallint := (SELECT introduced_generation FROM ref.mechanic WHERE mechanic_code = 'physical-special-split');
    v_evo_move_gen   smallint := 7;  -- level 0 = "learned on evolution" from Sun/Moon on
BEGIN
    TRUNCATE mart.fact_pokemon_move, mart.fact_pokemon_stat, mart.fact_encounter,
             mart.fact_pokemon_held_item, mart.fact_evolution, mart.fact_pokemon_type,
             mart.fact_pokemon_ability, mart.fact_type_effectiveness,
             mart.fact_pokedex_entry, mart.fact_machine, mart.fact_species_flavor_text,
             mart.bridge_version_group_region, mart.bridge_version_group_pokedex;

    -- ------------------------------------------- unknown members (key 0)
    INSERT INTO mart.dim_generation (generation_key, generation_id, generation_code, generation_name, generation_number)
        VALUES (0, 0, 'unknown', 'Unknown', 0) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_version_group (version_group_key, version_group_id, version_group_code, sort_order)
        VALUES (0, 0, 'unknown', 0) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_version (version_key, version_id, version_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_pokedex (pokedex_key, pokedex_id, pokedex_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_type (type_key, type_id, type_code, type_role)
        VALUES (0, 0, 'n/a', 'non-battle') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_stat (stat_key, stat_id, stat_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_ability (ability_key, ability_id, ability_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_move (move_key, move_id, valid_from_order, valid_to_order, is_current, move_code)
        VALUES (0, 0, 0, 9999, true, 'n/a') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_item (item_key, item_id, item_code)
        VALUES (0, 0, 'n/a') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_location_area (location_area_key, location_area_id, location_area_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_species (species_key, species_id, species_code)
        VALUES (0, 0, 'n/a') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_pokemon (pokemon_key, pokemon_id, pokemon_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_learn_method (learn_method_key, learn_method_id, learn_method_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_encounter_method (encounter_method_key, encounter_method_id, encounter_method_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_encounter_condition_set (condition_set_key, condition_set_code, condition_types,
            condition_count, has_time_condition, has_season_condition, has_weather_condition,
            has_swarm_condition, has_story_condition)
        VALUES (0, '', '', 0, false, false, false, false, false) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_evolution_trigger (evolution_trigger_key, evolution_trigger_id, evolution_trigger_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;

    -- ------------------------------------------------------- dimensions
    -- Pattern for every dim: SELECT from staging (+ ref), hash the
    -- attributes, upsert on the natural key, update only when the hash changed.

    INSERT INTO mart.dim_generation AS d (generation_id, generation_code, generation_name,
            generation_number, roman, main_region_code, first_release_year, last_release_year,
            platform, mechanics_introduced, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT g.generation_id, g.generation_code, g.generation_name, g.generation_id,
               gi.roman, g.main_region_code, gi.first_release_year, gi.last_release_year,
               gi.platform,
               (SELECT string_agg(mc.mechanic_code, ', ' ORDER BY mc.mechanic_code)
                  FROM ref.mechanic mc WHERE mc.introduced_generation = g.generation_id)
        FROM stg.generation g
        LEFT JOIN ref.generation_info gi ON gi.generation_number = g.generation_id
    ) x
    ON CONFLICT (generation_id) DO UPDATE
       SET generation_code = EXCLUDED.generation_code, generation_name = EXCLUDED.generation_name,
           roman = EXCLUDED.roman, main_region_code = EXCLUDED.main_region_code,
           first_release_year = EXCLUDED.first_release_year,
           last_release_year = EXCLUDED.last_release_year, platform = EXCLUDED.platform,
           mechanics_introduced = EXCLUDED.mechanics_introduced,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_version_group AS d (version_group_id, version_group_code, sort_order,
            generation_id, generation_code, generation_number, release_year, game_category,
            base_version_group_code, remake_of_generation, region_codes, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT vg.version_group_id, vg.version_group_code, vg.sort_order,
               vg.generation_id, g.generation_code, vg.generation_id,
               vi.release_year, vi.game_category, vi.base_version_group_code, vi.remake_of_generation,
               (SELECT string_agg(r.region_code, ',' ORDER BY r.region_code)
                  FROM stg.version_group_region r WHERE r.version_group_id = vg.version_group_id)
        FROM stg.version_group vg
        LEFT JOIN stg.generation g USING (generation_id)
        LEFT JOIN ref.version_group_info vi USING (version_group_code)
    ) x
    ON CONFLICT (version_group_id) DO UPDATE
       SET version_group_code = EXCLUDED.version_group_code, sort_order = EXCLUDED.sort_order,
           generation_id = EXCLUDED.generation_id, generation_code = EXCLUDED.generation_code,
           generation_number = EXCLUDED.generation_number, release_year = EXCLUDED.release_year,
           game_category = EXCLUDED.game_category,
           base_version_group_code = EXCLUDED.base_version_group_code,
           remake_of_generation = EXCLUDED.remake_of_generation, region_codes = EXCLUDED.region_codes,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_version AS d (version_id, version_code, version_name, version_group_id,
            version_group_code, game_category, release_year, generation_id, generation_code,
            generation_number, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT v.version_id, v.version_code, v.version_name, v.version_group_id,
               vg.version_group_code, vi.game_category, vi.release_year,
               vg.generation_id, g.generation_code, vg.generation_id
        FROM stg.version v
        LEFT JOIN stg.version_group vg USING (version_group_id)
        LEFT JOIN stg.generation g ON g.generation_id = vg.generation_id
        LEFT JOIN ref.version_group_info vi ON vi.version_group_code = vg.version_group_code
    ) x
    ON CONFLICT (version_id) DO UPDATE
       SET version_code = EXCLUDED.version_code, version_name = EXCLUDED.version_name,
           version_group_id = EXCLUDED.version_group_id, version_group_code = EXCLUDED.version_group_code,
           game_category = EXCLUDED.game_category, release_year = EXCLUDED.release_year,
           generation_id = EXCLUDED.generation_id, generation_code = EXCLUDED.generation_code,
           generation_number = EXCLUDED.generation_number,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_pokedex AS d (pokedex_id, pokedex_code, pokedex_name, region_code,
            is_national, is_main_series, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT pokedex_id, pokedex_code, pokedex_name, region_code,
               pokedex_code = 'national', is_main_series
        FROM stg.pokedex
    ) x
    ON CONFLICT (pokedex_id) DO UPDATE
       SET pokedex_code = EXCLUDED.pokedex_code, pokedex_name = EXCLUDED.pokedex_name,
           region_code = EXCLUDED.region_code, is_national = EXCLUDED.is_national,
           is_main_series = EXCLUDED.is_main_series,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_type AS d (type_id, type_code, type_name, introduced_generation,
            type_role, pre_split_damage_class, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT t.type_id, t.type_code, t.type_name, t.generation_id,
               COALESCE(tr.type_role, 'standard'), t.damage_class
        FROM stg.type t
        LEFT JOIN ref.type_role tr USING (type_code)
    ) x
    ON CONFLICT (type_id) DO UPDATE
       SET type_code = EXCLUDED.type_code, type_name = EXCLUDED.type_name,
           introduced_generation = EXCLUDED.introduced_generation,
           type_role = EXCLUDED.type_role, pre_split_damage_class = EXCLUDED.pre_split_damage_class,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_stat AS d (stat_id, stat_code, stat_name, is_battle_only,
            valid_from_generation, valid_to_generation, display_order, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT s.stat_id, s.stat_code, s.stat_name, s.is_battle_only,
               COALESCE(sv.valid_from_generation, 1), COALESCE(sv.valid_to_generation, 99), s.stat_id
        FROM stg.stat s
        LEFT JOIN ref.stat_validity sv USING (stat_code)
    ) x
    ON CONFLICT (stat_id) DO UPDATE
       SET stat_code = EXCLUDED.stat_code, stat_name = EXCLUDED.stat_name,
           is_battle_only = EXCLUDED.is_battle_only,
           valid_from_generation = EXCLUDED.valid_from_generation,
           valid_to_generation = EXCLUDED.valid_to_generation,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_ability AS d (ability_id, ability_code, ability_name, short_effect,
            is_main_series, introduced_generation, _batch_id, _row_hash)
    SELECT ability_id, ability_code, ability_name, short_effect, is_main_series, generation_id, p_batch,
           md5(row(ability_code, ability_name, short_effect, is_main_series, generation_id)::text)
    FROM stg.ability
    ON CONFLICT (ability_id) DO UPDATE
       SET ability_code = EXCLUDED.ability_code, ability_name = EXCLUDED.ability_name,
           short_effect = EXCLUDED.short_effect, is_main_series = EXCLUDED.is_main_series,
           introduced_generation = EXCLUDED.introduced_generation,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    -- dim_move, SCD type 2: one row per era from stg.move_era.
    INSERT INTO mart.dim_move AS d (move_id, valid_from_order, valid_to_order, is_current,
            era_generation, move_code, move_name, type_code, damage_class, effective_damage_class,
            power, accuracy, pp, priority, effect_chance, target, ailment, move_category,
            introduced_generation, short_effect, description, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT e.move_id, e.valid_from_order, e.valid_to_order, e.is_current, e.era_generation_id,
               m.move_code, m.move_name, t.type_code, m.damage_class,
               CASE WHEN m.damage_class = 'status' THEN 'status'
                    WHEN e.era_generation_id < v_split_gen
                         THEN COALESCE(t.damage_class, m.damage_class)
                    ELSE m.damage_class END,
               e.power, e.accuracy, e.pp, m.priority, e.effect_chance, m.target, m.ailment,
               m.move_category, m.generation_id, m.short_effect, m.description
        FROM stg.move_era e
        JOIN stg.move m USING (move_id)
        LEFT JOIN stg.type t ON t.type_id = e.type_id
    ) x
    ON CONFLICT (move_id, valid_from_order) DO UPDATE
       SET valid_to_order = EXCLUDED.valid_to_order, is_current = EXCLUDED.is_current,
           era_generation = EXCLUDED.era_generation,
           move_code = EXCLUDED.move_code, move_name = EXCLUDED.move_name,
           type_code = EXCLUDED.type_code, damage_class = EXCLUDED.damage_class,
           effective_damage_class = EXCLUDED.effective_damage_class,
           power = EXCLUDED.power, accuracy = EXCLUDED.accuracy, pp = EXCLUDED.pp,
           priority = EXCLUDED.priority, effect_chance = EXCLUDED.effect_chance,
           target = EXCLUDED.target, ailment = EXCLUDED.ailment,
           move_category = EXCLUDED.move_category,
           introduced_generation = EXCLUDED.introduced_generation,
           short_effect = EXCLUDED.short_effect, description = EXCLUDED.description,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    DELETE FROM mart.dim_move d
    WHERE d.move_key <> 0
      AND NOT EXISTS (SELECT 1 FROM stg.move_era e
                       WHERE e.move_id = d.move_id AND e.valid_from_order = d.valid_from_order);

    INSERT INTO mart.dim_item AS d (item_id, item_code, item_name, category, cost, fling_power,
            fling_effect, is_holdable, machine_kind, short_effect, description, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT item_id, item_code, item_name, category, cost, fling_power, fling_effect, is_holdable,
               substring(item_code FROM '^(tm|hm|tr)\d+$'), short_effect, description
        FROM stg.item
    ) x
    ON CONFLICT (item_id) DO UPDATE
       SET item_code = EXCLUDED.item_code, item_name = EXCLUDED.item_name,
           category = EXCLUDED.category, cost = EXCLUDED.cost,
           fling_power = EXCLUDED.fling_power, fling_effect = EXCLUDED.fling_effect,
           is_holdable = EXCLUDED.is_holdable, machine_kind = EXCLUDED.machine_kind,
           short_effect = EXCLUDED.short_effect, description = EXCLUDED.description,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_location_area AS d (location_area_id, location_area_code, location_area_name,
            location_id, location_code, location_name, region_code, _batch_id, _row_hash)
    SELECT location_area_id, location_area_code, NULLIF(location_area_name, ''), location_id,
           location_code, location_name, region_code, p_batch,
           md5(row(location_area_code, location_area_name, location_id, location_code,
                   location_name, region_code)::text)
    FROM stg.location_area
    ON CONFLICT (location_area_id) DO UPDATE
       SET location_area_code = EXCLUDED.location_area_code,
           location_area_name = EXCLUDED.location_area_name,
           location_id = EXCLUDED.location_id, location_code = EXCLUDED.location_code,
           location_name = EXCLUDED.location_name, region_code = EXCLUDED.region_code,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_species AS d (species_id, species_code, species_name, genus,
            generation_number, evolution_chain_id, species_class, is_baby, is_legendary, is_mythical,
            capture_rate, base_happiness, gender_rate, has_gender_differences, hatch_counter,
            growth_rate, color, shape, habitat, variety_count, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT s.species_id, s.species_code, s.species_name, s.genus, s.generation_id,
               s.evolution_chain_id,
               CASE WHEN s.is_mythical THEN 'mythical' WHEN s.is_legendary THEN 'legendary'
                    WHEN s.is_baby THEN 'baby' ELSE 'regular' END,
               s.is_baby, s.is_legendary, s.is_mythical, s.capture_rate, s.base_happiness,
               s.gender_rate, s.has_gender_differences, s.hatch_counter, s.growth_rate,
               s.color, s.shape, s.habitat,
               COALESCE(vc.n, 0)::smallint
        FROM stg.species s
        LEFT JOIN (SELECT species_id, count(*) AS n FROM stg.pokemon GROUP BY species_id) vc
               USING (species_id)
    ) x
    ON CONFLICT (species_id) DO UPDATE
       SET species_code = EXCLUDED.species_code, species_name = EXCLUDED.species_name,
           genus = EXCLUDED.genus, generation_number = EXCLUDED.generation_number,
           evolution_chain_id = EXCLUDED.evolution_chain_id, species_class = EXCLUDED.species_class,
           is_baby = EXCLUDED.is_baby, is_legendary = EXCLUDED.is_legendary,
           is_mythical = EXCLUDED.is_mythical, capture_rate = EXCLUDED.capture_rate,
           base_happiness = EXCLUDED.base_happiness, gender_rate = EXCLUDED.gender_rate,
           has_gender_differences = EXCLUDED.has_gender_differences,
           hatch_counter = EXCLUDED.hatch_counter, growth_rate = EXCLUDED.growth_rate,
           color = EXCLUDED.color, shape = EXCLUDED.shape, habitat = EXCLUDED.habitat,
           variety_count = EXCLUDED.variety_count,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    -- dim_pokemon: pokemon + its default form (category, introduction)
    -- + its species (denormalised) + current types.
    INSERT INTO mart.dim_pokemon AS d (pokemon_id, pokemon_code, is_default_form, form_category,
            form_region_code, is_battle_only, is_mega, cosmetic_form_count, introduced_version_group,
            introduced_generation, height_m, weight_kg, base_experience, primary_type, secondary_type,
            species_id, species_code, species_name, species_generation, species_class,
            is_legendary, is_mythical, is_baby, capture_rate, growth_rate, color, habitat,
            _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT p.pokemon_id, p.pokemon_code, p.is_default,
               CASE WHEN rule.form_category IS NOT NULL THEN rule.form_category
                    WHEN p.is_default THEN 'default'
                    WHEN f.is_battle_only THEN 'battle-only'
                    ELSE 'alternate' END,
               rule.region_code, f.is_battle_only, f.is_mega,
               (COALESCE(fc.n, 1) - 1)::smallint,
               vg.version_group_code, vg.generation_id,
               p.height_dm / 10.0, p.weight_hg / 10.0, p.base_experience,
               t1.type_code, t2.type_code,
               s.species_id, s.species_code, s.species_name, s.generation_id,
               CASE WHEN s.is_mythical THEN 'mythical' WHEN s.is_legendary THEN 'legendary'
                    WHEN s.is_baby THEN 'baby' ELSE 'regular' END,
               s.is_legendary, s.is_mythical, s.is_baby, s.capture_rate, s.growth_rate,
               s.color, s.habitat
        FROM stg.pokemon p
        LEFT JOIN stg.species s USING (species_id)
        -- the pokemon's own default form (a few, e.g. koraidon-limited-build,
        -- have a single form not flagged default, hence DISTINCT ON)
        LEFT JOIN (SELECT DISTINCT ON (pokemon_id) * FROM stg.pokemon_form
                    ORDER BY pokemon_id, is_default DESC, form_id) f ON f.pokemon_id = p.pokemon_id
        LEFT JOIN (SELECT pokemon_id, count(*) AS n FROM stg.pokemon_form GROUP BY pokemon_id) fc
               ON fc.pokemon_id = p.pokemon_id
        LEFT JOIN stg.version_group vg ON vg.version_group_id = f.introduced_version_group_id
        LEFT JOIN LATERAL (SELECT r.form_category, r.region_code FROM ref.form_rule r
                            WHERE p.pokemon_code ~ r.code_pattern
                            ORDER BY r.priority LIMIT 1) rule ON true
        LEFT JOIN stg.pokemon_type pt1 ON pt1.pokemon_id = p.pokemon_id AND pt1.slot = 1
                                      AND pt1.valid_to_generation_id IS NULL
        LEFT JOIN stg.type t1 ON t1.type_id = pt1.type_id
        LEFT JOIN stg.pokemon_type pt2 ON pt2.pokemon_id = p.pokemon_id AND pt2.slot = 2
                                      AND pt2.valid_to_generation_id IS NULL
        LEFT JOIN stg.type t2 ON t2.type_id = pt2.type_id
    ) x
    ON CONFLICT (pokemon_id) DO UPDATE
       SET pokemon_code = EXCLUDED.pokemon_code, is_default_form = EXCLUDED.is_default_form,
           form_category = EXCLUDED.form_category, form_region_code = EXCLUDED.form_region_code,
           is_battle_only = EXCLUDED.is_battle_only, is_mega = EXCLUDED.is_mega,
           cosmetic_form_count = EXCLUDED.cosmetic_form_count,
           introduced_version_group = EXCLUDED.introduced_version_group,
           introduced_generation = EXCLUDED.introduced_generation,
           height_m = EXCLUDED.height_m, weight_kg = EXCLUDED.weight_kg,
           base_experience = EXCLUDED.base_experience,
           primary_type = EXCLUDED.primary_type, secondary_type = EXCLUDED.secondary_type,
           species_id = EXCLUDED.species_id, species_code = EXCLUDED.species_code,
           species_name = EXCLUDED.species_name, species_generation = EXCLUDED.species_generation,
           species_class = EXCLUDED.species_class,
           is_legendary = EXCLUDED.is_legendary, is_mythical = EXCLUDED.is_mythical,
           is_baby = EXCLUDED.is_baby, capture_rate = EXCLUDED.capture_rate,
           growth_rate = EXCLUDED.growth_rate, color = EXCLUDED.color, habitat = EXCLUDED.habitat,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_learn_method AS d (learn_method_id, learn_method_code, learn_method_name, _batch_id, _row_hash)
    SELECT lookup_id, lookup_code, lookup_name, p_batch, md5(row(lookup_code, lookup_name)::text)
    FROM stg.lookup WHERE endpoint = 'move-learn-method'
    ON CONFLICT (learn_method_id) DO UPDATE
       SET learn_method_code = EXCLUDED.learn_method_code, learn_method_name = EXCLUDED.learn_method_name,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_encounter_method AS d (encounter_method_id, encounter_method_code,
            encounter_method_name, method_group, chance_unit, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT l.lookup_id, l.lookup_code, l.lookup_name, rule.method_group, rule.chance_unit
        FROM stg.lookup l
        LEFT JOIN LATERAL (SELECT r.method_group, r.chance_unit FROM ref.encounter_method_rule r
                            WHERE l.lookup_code ~ r.code_pattern
                            ORDER BY r.priority LIMIT 1) rule ON true
        WHERE l.endpoint = 'encounter-method'
    ) x
    ON CONFLICT (encounter_method_id) DO UPDATE
       SET encounter_method_code = EXCLUDED.encounter_method_code,
           encounter_method_name = EXCLUDED.encounter_method_name,
           method_group = EXCLUDED.method_group, chance_unit = EXCLUDED.chance_unit,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_evolution_trigger AS d (evolution_trigger_id, evolution_trigger_code, evolution_trigger_name, _batch_id, _row_hash)
    SELECT lookup_id, lookup_code, lookup_name, p_batch, md5(row(lookup_code, lookup_name)::text)
    FROM stg.lookup WHERE endpoint = 'evolution-trigger'
    ON CONFLICT (evolution_trigger_id) DO UPDATE
       SET evolution_trigger_code = EXCLUDED.evolution_trigger_code,
           evolution_trigger_name = EXCLUDED.evolution_trigger_name,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    -- Junk dimension: insert any condition combination not seen before.
    -- Condition TYPES come from the encounter-condition-value endpoint,
    -- because value codes do not always start with their type
    -- ('defeated-ghetsis' is a story-progress condition).
    INSERT INTO mart.dim_encounter_condition_set (condition_set_code, condition_types,
            condition_count, has_time_condition, has_season_condition, has_weather_condition,
            has_swarm_condition, has_story_condition, _batch_id)
    SELECT cs.condition_set_code, cs.types, cs.n,
           'time' = ANY (cs.type_arr), 'season' = ANY (cs.type_arr), 'weather' = ANY (cs.type_arr),
           'swarm' = ANY (cs.type_arr), 'story-progress' = ANY (cs.type_arr), p_batch
    FROM (
        SELECT e.condition_set_code,
               cardinality(string_to_array(e.condition_set_code, ','))       AS n,
               array_agg(DISTINCT cv.condition_code)                         AS type_arr,
               string_agg(DISTINCT cv.condition_code, ',' ORDER BY cv.condition_code) AS types
        FROM (SELECT DISTINCT condition_set_code FROM stg.encounter WHERE condition_set_code <> '') e
        CROSS JOIN LATERAL unnest(string_to_array(e.condition_set_code, ',')) AS v(code)
        LEFT JOIN stg.encounter_condition_value cv ON cv.condition_value_code = v.code
        GROUP BY e.condition_set_code
    ) cs
    ON CONFLICT (condition_set_code) DO NOTHING;

    -- --------------------------------------------------------- bridges
    INSERT INTO mart.bridge_version_group_region (version_group_key, region_code, _batch_id)
    SELECT vg.version_group_key, r.region_code, p_batch
    FROM stg.version_group_region r
    JOIN mart.dim_version_group vg USING (version_group_id);

    INSERT INTO mart.bridge_version_group_pokedex (version_group_key, pokedex_key, _batch_id)
    SELECT vg.version_group_key, COALESCE(d.pokedex_key, 0), p_batch
    FROM stg.version_group_pokedex s
    JOIN mart.dim_version_group vg USING (version_group_id)
    LEFT JOIN mart.dim_pokedex d USING (pokedex_id);

    -- ------------------------------------------------------------ facts

    INSERT INTO mart.fact_pokemon_move (pokemon_key, move_key, version_group_key, learn_method_key,
            level_learned_at, learn_order, is_evolution_move, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), COALESCE(m.move_key, 0), COALESCE(vg.version_group_key, 0),
           COALESCE(lm.learn_method_key, 0), s.level_learned_at, s.learn_order,
           lm.learn_method_code = 'level-up' AND s.level_learned_at = 0
               AND vg.generation_number >= v_evo_move_gen,
           p_batch
    FROM stg.pokemon_move s
    LEFT JOIN mart.dim_pokemon p        ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_version_group vg ON vg.version_group_id = s.version_group_id
    LEFT JOIN mart.dim_move m           ON m.move_id = s.move_id
                                       AND vg.sort_order BETWEEN m.valid_from_order AND m.valid_to_order
    LEFT JOIN mart.dim_learn_method lm  ON lm.learn_method_id = s.learn_method_id;

    -- Stats: clamp each era to when the stat existed (ref.stat_validity)
    -- and to when this variety existed (dim_pokemon.introduced_generation).
    INSERT INTO mart.fact_pokemon_stat (pokemon_key, stat_key, valid_from_generation,
            valid_to_generation, is_current, base_stat, effort_yield, _batch_id)
    SELECT pokemon_key, stat_key, vf, vt, vt = 99, base_stat, effort, p_batch
    FROM (
        SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key, COALESCE(st.stat_key, 0) AS stat_key,
               GREATEST(s.valid_from_generation_id, COALESCE(st.valid_from_generation, 1),
                        COALESCE(p.introduced_generation, 1))                     AS vf,
               LEAST(COALESCE(s.valid_to_generation_id, 99),
                     COALESCE(st.valid_to_generation, 99))                        AS vt,
               s.base_stat, s.effort
        FROM stg.pokemon_stat s
        LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
        LEFT JOIN mart.dim_stat st   ON st.stat_id = s.stat_id
    ) x
    WHERE vf <= vt;

    INSERT INTO mart.fact_encounter (location_area_key, pokemon_key, version_key, slot_seq,
            encounter_method_key, condition_set_key, min_level, max_level, chance_pct, _batch_id)
    SELECT COALESCE(la.location_area_key, 0), COALESCE(p.pokemon_key, 0), COALESCE(v.version_key, 0),
           s.slot_seq, COALESCE(em.encounter_method_key, 0), COALESCE(cs.condition_set_key, 0),
           s.min_level, s.max_level, s.chance_pct, p_batch
    FROM stg.encounter s
    LEFT JOIN mart.dim_location_area la ON la.location_area_id = s.location_area_id
    LEFT JOIN mart.dim_pokemon p        ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_version v        ON v.version_id = s.version_id
    LEFT JOIN mart.dim_encounter_method em ON em.encounter_method_id = s.encounter_method_id
    LEFT JOIN mart.dim_encounter_condition_set cs ON cs.condition_set_code = s.condition_set_code;

    INSERT INTO mart.fact_pokemon_held_item (pokemon_key, item_key, version_key, rarity_pct, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), COALESCE(i.item_key, 0), COALESCE(v.version_key, 0),
           s.rarity_pct, p_batch
    FROM stg.pokemon_held_item s
    LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_item i    ON i.item_id = s.item_id
    LEFT JOIN mart.dim_version v ON v.version_id = s.version_id;

    -- Evolution: species-level steps resolved to concrete varieties.
    -- No required form = the species' default variety evolves; no evolved
    -- form = it becomes the target species' default variety.
    INSERT INTO mart.fact_evolution (evolution_chain_id, to_species_key, detail_seq, from_species_key,
            from_pokemon_key, to_pokemon_key, evolution_trigger_key, version_group_key,
            used_item_key, held_item_key, known_move_key, used_move_key, known_move_type_key,
            party_type_key, trade_species_key, party_species_key, location_id, region_code, stage,
            is_default_path, min_level, min_happiness, min_beauty, min_affection, min_move_count,
            min_steps, min_damage_taken, relative_physical_stats, time_of_day, gender_id,
            needs_overworld_rain, turn_upside_down, near_special_rock, needs_multiplayer, _batch_id)
    SELECT s.evolution_chain_id, COALESCE(ts.species_key, 0), s.detail_seq,
           COALESCE(fs.species_key, 0), COALESCE(fp.pokemon_key, 0), COALESCE(tp.pokemon_key, 0),
           COALESCE(et.evolution_trigger_key, 0), COALESCE(vg.version_group_key, 0),
           COALESCE(ui.item_key, 0), COALESCE(hi.item_key, 0),
           COALESCE(km.move_key, 0), COALESCE(um.move_key, 0),
           COALESCE(kt.type_key, 0), COALESCE(pty.type_key, 0),
           COALESCE(tr.species_key, 0), COALESCE(ps.species_key, 0),
           s.location_id, s.region_code, s.stage, s.is_default_path,
           s.min_level, s.min_happiness, s.min_beauty, s.min_affection, s.min_move_count,
           s.min_steps, s.min_damage_taken, s.relative_physical_stats, s.time_of_day, s.gender_id,
           s.needs_overworld_rain, s.turn_upside_down, s.near_special_rock, s.needs_multiplayer,
           p_batch
    FROM stg.evolution s
    LEFT JOIN mart.dim_species ts ON ts.species_id = s.to_species_id
    LEFT JOIN mart.dim_species fs ON fs.species_id = s.from_species_id
    LEFT JOIN mart.dim_species tr ON tr.species_id = s.trade_species_id
    LEFT JOIN mart.dim_species ps ON ps.species_id = s.party_species_id
    LEFT JOIN stg.pokemon_form rf ON rf.form_id = s.required_form_id
    LEFT JOIN stg.pokemon_form ef ON ef.form_id = s.evolved_form_id
    LEFT JOIN mart.dim_pokemon fd ON fd.species_id = s.from_species_id AND fd.is_default_form
    LEFT JOIN mart.dim_pokemon td ON td.species_id = s.to_species_id AND td.is_default_form
    LEFT JOIN mart.dim_pokemon fp ON fp.pokemon_id = COALESCE(rf.pokemon_id, fd.pokemon_id)
    LEFT JOIN mart.dim_pokemon tp ON tp.pokemon_id = COALESCE(ef.pokemon_id, td.pokemon_id)
    LEFT JOIN mart.dim_evolution_trigger et ON et.evolution_trigger_id = s.evolution_trigger_id
    LEFT JOIN mart.dim_version_group vg ON vg.version_group_id = s.version_group_id
    LEFT JOIN mart.dim_item ui ON ui.item_id = s.item_id
    LEFT JOIN mart.dim_item hi ON hi.item_id = s.held_item_id
    LEFT JOIN mart.dim_move km ON km.move_id = s.known_move_id AND km.is_current
    LEFT JOIN mart.dim_move um ON um.move_id = s.used_move_id AND um.is_current
    LEFT JOIN mart.dim_type kt ON kt.type_id = s.known_move_type_id
    LEFT JOIN mart.dim_type pty ON pty.type_id = s.party_type_id;

    -- Types: an era never starts before this variety existed
    -- (Alolan Raichu's Electric/Psychic typing starts in gen VII).
    INSERT INTO mart.fact_pokemon_type (pokemon_key, slot, valid_from_generation, valid_to_generation,
            type_key, is_current, _batch_id)
    SELECT pokemon_key, slot, vf, vt, type_key, vt = 99, p_batch
    FROM (
        SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key, s.slot,
               GREATEST(s.valid_from_generation_id, COALESCE(p.introduced_generation, 1)) AS vf,
               COALESCE(s.valid_to_generation_id, 99) AS vt,
               COALESCE(t.type_key, 0) AS type_key
        FROM stg.pokemon_type s
        LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
        LEFT JOIN mart.dim_type t    ON t.type_id = s.type_id
    ) x
    WHERE vf <= vt;

    -- Abilities: no era before gen III, no hidden slot before gen V, none
    -- before the variety existed; "slot did not exist yet" rows are dropped.
    INSERT INTO mart.fact_pokemon_ability (pokemon_key, slot, valid_from_generation,
            valid_to_generation, ability_key, is_hidden, is_current, _batch_id)
    SELECT pokemon_key, slot, vf, vt, ability_key, is_hidden, vt = 99, p_batch
    FROM (
        SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key, s.slot,
               GREATEST(s.valid_from_generation_id, v_abilities_gen,
                        CASE WHEN s.is_hidden THEN v_hidden_gen ELSE 1 END,
                        COALESCE(p.introduced_generation, 1))            AS vf,
               COALESCE(s.valid_to_generation_id, 99)                    AS vt,
               COALESCE(a.ability_key, 0) AS ability_key, s.is_hidden
        FROM stg.pokemon_ability s
        LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
        LEFT JOIN mart.dim_ability a ON a.ability_id = s.ability_id
        WHERE s.ability_id IS NOT NULL
    ) x
    WHERE vf <= vt;

    INSERT INTO mart.fact_pokedex_entry (species_key, pokedex_key, entry_number, _batch_id)
    SELECT COALESCE(sp.species_key, 0), COALESCE(d.pokedex_key, 0), s.entry_number, p_batch
    FROM stg.pokedex_entry s
    LEFT JOIN mart.dim_species sp ON sp.species_id = s.species_id
    LEFT JOIN mart.dim_pokedex d  ON d.pokedex_id = s.pokedex_id;

    INSERT INTO mart.fact_species_flavor_text (species_key, version_key, flavor_text, _batch_id)
    SELECT COALESCE(sp.species_key, 0), COALESCE(v.version_key, 0), s.flavor_text, p_batch
    FROM stg.species_flavor_text s
    LEFT JOIN mart.dim_species sp ON sp.species_id = s.species_id
    LEFT JOIN mart.dim_version v  ON v.version_id = s.version_id
    WHERE s.flavor_text IS NOT NULL;

    INSERT INTO mart.fact_machine (item_key, version_group_key, move_key, machine_kind,
            machine_number, _batch_id)
    SELECT COALESCE(i.item_key, 0), COALESCE(vg.version_group_key, 0), COALESCE(m.move_key, 0),
           COALESCE(i.machine_kind, 'other'),
           substring(s.item_code FROM '^(?:tm|hm|tr)(\d+)$')::smallint, p_batch
    FROM stg.machine s
    LEFT JOIN mart.dim_item i           ON i.item_id = s.item_id
    LEFT JOIN mart.dim_version_group vg ON vg.version_group_id = s.version_group_id
    LEFT JOIN mart.dim_move m           ON m.move_id = s.move_id
                                       AND vg.sort_order BETWEEN m.valid_from_order AND m.valid_to_order;

    -- Densified type chart. For each generation g and each pair of
    -- STANDARD types that both exist in g: pick the era whose valid_to is
    -- the first one >= g (or the current era), default to 1x when the pair
    -- is absent. Stellar (Tera only), ??? and Shadow are left out.
    INSERT INTO mart.fact_type_effectiveness (attacking_type_key, defending_type_key, generation_key,
            damage_multiplier, _batch_id)
    SELECT atk.type_key, dfn.type_key, g.generation_key,
           COALESCE((SELECT td.multiplier
                       FROM stg.type_damage td
                      WHERE td.attacking_type_id = atk.type_id
                        AND td.defending_type_id = dfn.type_id
                        AND COALESCE(td.valid_to_generation_id, 99) = era.valid_to), 1.0),
           p_batch
    FROM mart.dim_generation g
    JOIN mart.dim_type atk ON atk.type_role = 'standard' AND atk.introduced_generation <= g.generation_number
    JOIN mart.dim_type dfn ON dfn.type_role = 'standard' AND dfn.introduced_generation <= g.generation_number
    CROSS JOIN LATERAL (
        SELECT MIN(COALESCE(x.valid_to_generation_id, 99)) AS valid_to
        FROM (SELECT DISTINCT valid_to_generation_id FROM stg.type_damage
               WHERE attacking_type_id = atk.type_id) x
        WHERE COALESCE(x.valid_to_generation_id, 99) >= g.generation_number
    ) era
    WHERE g.generation_key <> 0;

    -- ------------------------------------------------ coverage flags
    -- Derived from the facts just loaded, so a later API release that adds
    -- encounter data for newer games flips these on with no code change.
    UPDATE mart.dim_version_group vg
       SET has_learnset_data  = EXISTS (SELECT 1 FROM mart.fact_pokemon_move f
                                         WHERE f.version_group_key = vg.version_group_key),
           has_encounter_data = EXISTS (SELECT 1 FROM mart.fact_encounter f
                                          JOIN mart.dim_version v USING (version_key)
                                         WHERE v.version_group_id = vg.version_group_id)
     WHERE vg.version_group_key <> 0;
END;
$$;
