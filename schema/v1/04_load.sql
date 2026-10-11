-- =====================================================================
-- Pokeplan :: Load staging -> mart
-- ---------------------------------------------------------------------
-- Usage:  CALL mart.load(<batch_id>);
-- Patterns:
--   * Idempotent: running it twice with the same raw data changes nothing.
--   * Dimensions: UPSERT on the natural key (INSERT ... ON CONFLICT). The
--     surrogate key of an existing member never changes, so facts stay
--     valid. The row hash skips no-op updates (SCD type 1).
--   * Facts: full refresh inside one transaction (TRUNCATE + INSERT).
--     The whole PokeAPI dataset is small, so this is the simplest correct
--     choice. Incremental fact loads are a later exercise.
--   * Lookups of surrogate keys COALESCE to 0 (the Unknown member), so a
--     fact row is never lost because a dimension row is missing; 05_tests
--     counts how often that happens instead.
-- =====================================================================

CREATE OR REPLACE PROCEDURE mart.load(p_batch bigint)
LANGUAGE plpgsql
AS $$
BEGIN
    -- ------------------------------------------- unknown members (key 0)
    INSERT INTO mart.dim_generation (generation_key, generation_id, generation_code, generation_name, generation_number)
        VALUES (0, 0, 'unknown', 'Unknown', 0) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_version_group (version_group_key, version_group_id, version_group_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_version (version_key, version_id, version_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_type (type_key, type_id, type_code, is_battle_type)
        VALUES (0, 0, 'n/a', false) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_stat (stat_key, stat_id, stat_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_ability (ability_key, ability_id, ability_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_move (move_key, move_id, move_code)
        VALUES (0, 0, 'n/a') ON CONFLICT DO NOTHING;
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
    INSERT INTO mart.dim_encounter_condition_set (condition_set_key, condition_set_code, condition_count,
            has_time_condition, has_season_condition, has_swarm_condition, has_radar_condition)
        VALUES (0, '', 0, false, false, false, false) ON CONFLICT DO NOTHING;
    INSERT INTO mart.dim_evolution_trigger (evolution_trigger_key, evolution_trigger_id, evolution_trigger_code)
        VALUES (0, 0, 'unknown') ON CONFLICT DO NOTHING;

    -- ------------------------------------------------------- dimensions
    -- Pattern for every dim: SELECT from staging, hash the attributes,
    -- upsert on the natural key, update only when the hash changed.

    INSERT INTO mart.dim_generation AS d (generation_id, generation_code, generation_name,
            generation_number, main_region_code, _batch_id, _row_hash)
    SELECT generation_id, generation_code, generation_name, generation_id,
           main_region_code, p_batch, md5(row(generation_code, generation_name, main_region_code)::text)
    FROM stg.generation
    ON CONFLICT (generation_id) DO UPDATE
       SET generation_code = EXCLUDED.generation_code, generation_name = EXCLUDED.generation_name,
           main_region_code = EXCLUDED.main_region_code,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_version_group AS d (version_group_id, version_group_code, sort_order,
            generation_id, generation_code, generation_number, _batch_id, _row_hash)
    SELECT vg.version_group_id, vg.version_group_code, vg.sort_order,
           vg.generation_id, g.generation_code, vg.generation_id, p_batch,
           md5(row(vg.version_group_code, vg.sort_order, vg.generation_id, g.generation_code)::text)
    FROM stg.version_group vg
    LEFT JOIN stg.generation g USING (generation_id)
    ON CONFLICT (version_group_id) DO UPDATE
       SET version_group_code = EXCLUDED.version_group_code, sort_order = EXCLUDED.sort_order,
           generation_id = EXCLUDED.generation_id, generation_code = EXCLUDED.generation_code,
           generation_number = EXCLUDED.generation_number,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_version AS d (version_id, version_code, version_name, version_group_id,
            version_group_code, generation_id, generation_code, generation_number, _batch_id, _row_hash)
    SELECT v.version_id, v.version_code, v.version_name, v.version_group_id,
           vg.version_group_code, vg.generation_id, g.generation_code, vg.generation_id, p_batch,
           md5(row(v.version_code, v.version_name, v.version_group_id, vg.version_group_code,
                   vg.generation_id, g.generation_code)::text)
    FROM stg.version v
    LEFT JOIN stg.version_group vg USING (version_group_id)
    LEFT JOIN stg.generation g ON g.generation_id = vg.generation_id
    ON CONFLICT (version_id) DO UPDATE
       SET version_code = EXCLUDED.version_code, version_name = EXCLUDED.version_name,
           version_group_id = EXCLUDED.version_group_id, version_group_code = EXCLUDED.version_group_code,
           generation_id = EXCLUDED.generation_id, generation_code = EXCLUDED.generation_code,
           generation_number = EXCLUDED.generation_number,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_type AS d (type_id, type_code, type_name, introduced_generation,
            is_battle_type, _batch_id, _row_hash)
    SELECT type_id, type_code, type_name, generation_id, type_id < 10000, p_batch,
           md5(row(type_code, type_name, generation_id)::text)
    FROM stg.type
    ON CONFLICT (type_id) DO UPDATE
       SET type_code = EXCLUDED.type_code, type_name = EXCLUDED.type_name,
           introduced_generation = EXCLUDED.introduced_generation,
           is_battle_type = EXCLUDED.is_battle_type,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_stat AS d (stat_id, stat_code, stat_name, is_battle_only, display_order,
            _batch_id, _row_hash)
    SELECT stat_id, stat_code, stat_name, is_battle_only, stat_id, p_batch,
           md5(row(stat_code, stat_name, is_battle_only)::text)
    FROM stg.stat
    ON CONFLICT (stat_id) DO UPDATE
       SET stat_code = EXCLUDED.stat_code, stat_name = EXCLUDED.stat_name,
           is_battle_only = EXCLUDED.is_battle_only,
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

    INSERT INTO mart.dim_move AS d (move_id, move_code, move_name, type_code, damage_class, power,
            accuracy, pp, priority, effect_chance, target, ailment, move_category,
            introduced_generation, _batch_id, _row_hash)
    SELECT m.move_id, m.move_code, m.move_name, t.type_code, m.damage_class, m.power, m.accuracy,
           m.pp, m.priority, m.effect_chance, m.target, m.ailment, m.move_category, m.generation_id,
           p_batch,
           md5(row(m.move_code, m.move_name, t.type_code, m.damage_class, m.power, m.accuracy, m.pp,
                   m.priority, m.effect_chance, m.target, m.ailment, m.move_category, m.generation_id)::text)
    FROM stg.move m
    LEFT JOIN stg.type t USING (type_id)
    ON CONFLICT (move_id) DO UPDATE
       SET move_code = EXCLUDED.move_code, move_name = EXCLUDED.move_name,
           type_code = EXCLUDED.type_code, damage_class = EXCLUDED.damage_class,
           power = EXCLUDED.power, accuracy = EXCLUDED.accuracy, pp = EXCLUDED.pp,
           priority = EXCLUDED.priority, effect_chance = EXCLUDED.effect_chance,
           target = EXCLUDED.target, ailment = EXCLUDED.ailment,
           move_category = EXCLUDED.move_category,
           introduced_generation = EXCLUDED.introduced_generation,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    INSERT INTO mart.dim_item AS d (item_id, item_code, item_name, category, cost, fling_power,
            fling_effect, is_holdable, _batch_id, _row_hash)
    SELECT item_id, item_code, item_name, category, cost, fling_power, fling_effect, is_holdable,
           p_batch,
           md5(row(item_code, item_name, category, cost, fling_power, fling_effect, is_holdable)::text)
    FROM stg.item
    ON CONFLICT (item_id) DO UPDATE
       SET item_code = EXCLUDED.item_code, item_name = EXCLUDED.item_name,
           category = EXCLUDED.category, cost = EXCLUDED.cost,
           fling_power = EXCLUDED.fling_power, fling_effect = EXCLUDED.fling_effect,
           is_holdable = EXCLUDED.is_holdable,
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
            generation_number, evolution_chain_id, is_baby, is_legendary, is_mythical,
            capture_rate, base_happiness, gender_rate, hatch_counter, growth_rate, color,
            shape, habitat, _batch_id, _row_hash)
    SELECT species_id, species_code, species_name, genus, generation_id, evolution_chain_id,
           is_baby, is_legendary, is_mythical, capture_rate, base_happiness, gender_rate,
           hatch_counter, growth_rate, color, shape, habitat, p_batch,
           md5(row(species_code, species_name, genus, generation_id, evolution_chain_id, is_baby,
                   is_legendary, is_mythical, capture_rate, base_happiness, gender_rate,
                   hatch_counter, growth_rate, color, shape, habitat)::text)
    FROM stg.species
    ON CONFLICT (species_id) DO UPDATE
       SET species_code = EXCLUDED.species_code, species_name = EXCLUDED.species_name,
           genus = EXCLUDED.genus, generation_number = EXCLUDED.generation_number,
           evolution_chain_id = EXCLUDED.evolution_chain_id, is_baby = EXCLUDED.is_baby,
           is_legendary = EXCLUDED.is_legendary, is_mythical = EXCLUDED.is_mythical,
           capture_rate = EXCLUDED.capture_rate, base_happiness = EXCLUDED.base_happiness,
           gender_rate = EXCLUDED.gender_rate, hatch_counter = EXCLUDED.hatch_counter,
           growth_rate = EXCLUDED.growth_rate, color = EXCLUDED.color,
           shape = EXCLUDED.shape, habitat = EXCLUDED.habitat,
           _batch_id = EXCLUDED._batch_id, _loaded_at = now(), _row_hash = EXCLUDED._row_hash
     WHERE d._row_hash IS DISTINCT FROM EXCLUDED._row_hash;

    -- dim_pokemon: pokemon + its species (denormalised) + current types.
    INSERT INTO mart.dim_pokemon AS d (pokemon_id, pokemon_code, is_default_form, height_m, weight_kg,
            base_experience, primary_type, secondary_type, species_id, species_code, species_name,
            generation_number, is_legendary, is_mythical, is_baby, capture_rate, growth_rate,
            color, habitat, _batch_id, _row_hash)
    SELECT x.*, p_batch, md5(x::text)
    FROM (
        SELECT p.pokemon_id, p.pokemon_code, p.is_default,
               p.height_dm / 10.0, p.weight_hg / 10.0, p.base_experience,
               t1.type_code, t2.type_code,
               s.species_id, s.species_code, s.species_name, s.generation_id,
               s.is_legendary, s.is_mythical, s.is_baby, s.capture_rate, s.growth_rate,
               s.color, s.habitat
        FROM stg.pokemon p
        LEFT JOIN stg.species s USING (species_id)
        LEFT JOIN stg.pokemon_type pt1 ON pt1.pokemon_id = p.pokemon_id AND pt1.slot = 1
                                      AND pt1.valid_to_generation_id IS NULL
        LEFT JOIN stg.type t1 ON t1.type_id = pt1.type_id
        LEFT JOIN stg.pokemon_type pt2 ON pt2.pokemon_id = p.pokemon_id AND pt2.slot = 2
                                      AND pt2.valid_to_generation_id IS NULL
        LEFT JOIN stg.type t2 ON t2.type_id = pt2.type_id
    ) x
    ON CONFLICT (pokemon_id) DO UPDATE
       SET pokemon_code = EXCLUDED.pokemon_code, is_default_form = EXCLUDED.is_default_form,
           height_m = EXCLUDED.height_m, weight_kg = EXCLUDED.weight_kg,
           base_experience = EXCLUDED.base_experience,
           primary_type = EXCLUDED.primary_type, secondary_type = EXCLUDED.secondary_type,
           species_id = EXCLUDED.species_id, species_code = EXCLUDED.species_code,
           species_name = EXCLUDED.species_name, generation_number = EXCLUDED.generation_number,
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

    INSERT INTO mart.dim_encounter_method AS d (encounter_method_id, encounter_method_code, encounter_method_name, _batch_id, _row_hash)
    SELECT lookup_id, lookup_code, lookup_name, p_batch, md5(row(lookup_code, lookup_name)::text)
    FROM stg.lookup WHERE endpoint = 'encounter-method'
    ON CONFLICT (encounter_method_id) DO UPDATE
       SET encounter_method_code = EXCLUDED.encounter_method_code,
           encounter_method_name = EXCLUDED.encounter_method_name,
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
    INSERT INTO mart.dim_encounter_condition_set (condition_set_code, condition_count,
            has_time_condition, has_season_condition, has_swarm_condition, has_radar_condition, _batch_id)
    SELECT DISTINCT e.condition_set_code,
           cardinality(string_to_array(e.condition_set_code, ',')),
           e.condition_set_code LIKE '%time-%', e.condition_set_code LIKE '%season-%',
           e.condition_set_code LIKE '%swarm-%', e.condition_set_code LIKE '%radar-%', p_batch
    FROM stg.encounter e
    WHERE e.condition_set_code <> ''
    ON CONFLICT (condition_set_code) DO NOTHING;

    -- ------------------------------------------------------------ facts
    TRUNCATE mart.fact_pokemon_move, mart.fact_pokemon_stat, mart.fact_encounter,
             mart.fact_pokemon_held_item, mart.fact_evolution, mart.fact_pokemon_type,
             mart.fact_pokemon_ability, mart.fact_type_effectiveness;

    INSERT INTO mart.fact_pokemon_move (pokemon_key, move_key, version_group_key, learn_method_key,
            level_learned_at, learn_order, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), COALESCE(m.move_key, 0), COALESCE(vg.version_group_key, 0),
           COALESCE(lm.learn_method_key, 0), s.level_learned_at, s.learn_order, p_batch
    FROM stg.pokemon_move s
    LEFT JOIN mart.dim_pokemon p        ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_move m           ON m.move_id = s.move_id
    LEFT JOIN mart.dim_version_group vg ON vg.version_group_id = s.version_group_id
    LEFT JOIN mart.dim_learn_method lm  ON lm.learn_method_id = s.learn_method_id;

    INSERT INTO mart.fact_pokemon_stat (pokemon_key, stat_key, base_stat, effort_yield, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), COALESCE(st.stat_key, 0), s.base_stat, s.effort, p_batch
    FROM stg.pokemon_stat s
    LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_stat st   ON st.stat_id = s.stat_id;

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

    INSERT INTO mart.fact_evolution (evolution_chain_id, to_species_key, detail_seq, from_species_key,
            evolution_trigger_key, version_group_key, used_item_key, held_item_key, known_move_key,
            known_move_type_key, trade_species_key, location_id, stage, min_level, min_happiness,
            min_beauty, min_affection, time_of_day, gender_id, needs_overworld_rain,
            turn_upside_down, _batch_id)
    SELECT s.evolution_chain_id, COALESCE(ts.species_key, 0), s.detail_seq,
           COALESCE(fs.species_key, 0), COALESCE(et.evolution_trigger_key, 0),
           COALESCE(vg.version_group_key, 0), COALESCE(ui.item_key, 0), COALESCE(hi.item_key, 0),
           COALESCE(km.move_key, 0), COALESCE(kt.type_key, 0), COALESCE(tr.species_key, 0),
           s.location_id, s.stage, s.min_level, s.min_happiness, s.min_beauty, s.min_affection,
           s.time_of_day, s.gender_id, s.needs_overworld_rain, s.turn_upside_down, p_batch
    FROM stg.evolution s
    LEFT JOIN mart.dim_species ts ON ts.species_id = s.to_species_id
    LEFT JOIN mart.dim_species fs ON fs.species_id = s.from_species_id
    LEFT JOIN mart.dim_species tr ON tr.species_id = s.trade_species_id
    LEFT JOIN mart.dim_evolution_trigger et ON et.evolution_trigger_id = s.evolution_trigger_id
    LEFT JOIN mart.dim_version_group vg ON vg.version_group_id = s.version_group_id
    LEFT JOIN mart.dim_item ui ON ui.item_id = s.item_id
    LEFT JOIN mart.dim_item hi ON hi.item_id = s.held_item_id
    LEFT JOIN mart.dim_move km ON km.move_id = s.known_move_id
    LEFT JOIN mart.dim_type kt ON kt.type_id = s.known_move_type_id;

    INSERT INTO mart.fact_pokemon_type (pokemon_key, slot, valid_from_generation, valid_to_generation,
            type_key, is_current, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), s.slot, s.valid_from_generation_id,
           COALESCE(s.valid_to_generation_id, 99), COALESCE(t.type_key, 0),
           s.valid_to_generation_id IS NULL, p_batch
    FROM stg.pokemon_type s
    LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_type t    ON t.type_id = s.type_id;

    INSERT INTO mart.fact_pokemon_ability (pokemon_key, slot, ability_key, is_hidden, _batch_id)
    SELECT COALESCE(p.pokemon_key, 0), s.slot, COALESCE(a.ability_key, 0), s.is_hidden, p_batch
    FROM stg.pokemon_ability s
    LEFT JOIN mart.dim_pokemon p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN mart.dim_ability a ON a.ability_id = s.ability_id;

    -- Densified type chart. For each generation g and each pair of battle
    -- types that both exist in g: pick the era whose valid_to is the first
    -- one >= g (or the current era), default to 1x when the pair is absent.
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
    JOIN mart.dim_type atk ON atk.is_battle_type AND atk.introduced_generation <= g.generation_number
    JOIN mart.dim_type dfn ON dfn.is_battle_type AND dfn.introduced_generation <= g.generation_number
    CROSS JOIN LATERAL (
        SELECT MIN(COALESCE(x.valid_to_generation_id, 99)) AS valid_to
        FROM (SELECT DISTINCT valid_to_generation_id FROM stg.type_damage
               WHERE attacking_type_id = atk.type_id) x
        WHERE COALESCE(x.valid_to_generation_id, 99) >= g.generation_number
    ) era
    WHERE g.generation_key <> 0;
END;
$$;
