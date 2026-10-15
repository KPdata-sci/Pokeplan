-- Writes the dashboard's data as one JSON document to stdout.
-- psql -At -f export_dashboard.sql > dashboard_data.json
-- Big lists are arrays of arrays (column order noted) to keep the file small;
-- build_dashboard.py splits the per-game ones into one file per game.
-- Every list has a full ORDER BY, so the file only changes when the data does.
SELECT json_build_object(
  'pokemon',     (SELECT json_agg(c ORDER BY dex_no) FROM serve.pokemon_card c),
  'type_chart',  (SELECT json_agg(json_build_array(generation, attacking, defending, multiplier)
                                ORDER BY generation, attacking, defending) FROM serve.type_chart),
  'generations', (SELECT json_agg(g ORDER BY generation) FROM serve.generation g),
  'games',       (SELECT json_agg(g ORDER BY sort_order) FROM serve.game g),
  'run',         (SELECT row_to_json(r) FROM serve.pipeline_run r),
  'mart_rows',   json_build_object(
      'fact_pokemon_move',        (SELECT count(*) FROM mart.fact_pokemon_move),
      'fact_encounter',           (SELECT count(*) FROM mart.fact_encounter),
      'fact_species_flavor_text', (SELECT count(*) FROM mart.fact_species_flavor_text),
      'fact_pokemon_stat',        (SELECT count(*) FROM mart.fact_pokemon_stat),
      'fact_pokedex_entry',       (SELECT count(*) FROM mart.fact_pokedex_entry),
      'fact_pokemon_held_item',   (SELECT count(*) FROM mart.fact_pokemon_held_item),
      'fact_pokemon_ability',     (SELECT count(*) FROM mart.fact_pokemon_ability),
      'fact_type_effectiveness',  (SELECT count(*) FROM mart.fact_type_effectiveness),
      'fact_machine',             (SELECT count(*) FROM mart.fact_machine),
      'fact_pokemon_type',        (SELECT count(*) FROM mart.fact_pokemon_type),
      'fact_evolution',           (SELECT count(*) FROM mart.fact_evolution)),
  -- [dex_no, slot, ability_name, is_hidden, short_effect]
  'abilities',   (SELECT json_agg(json_build_array(dex_no, slot, ability_name, is_hidden, short_effect) ORDER BY dex_no, slot)
                  FROM serve.pokemon_ability),
  -- [chain_id, from_dex, to_dex, to_form, how, since_game, used_item_id, held_item_id]
  'evolutions',  (SELECT json_agg(json_build_array(chain_id, from_dex, to_dex, to_form, how, since_game, used_item_id, held_item_id)
                         ORDER BY chain_id, stage, to_dex, detail_seq)
                  FROM serve.evolution),
  -- [move_id, name, type, damage_class, power, accuracy, pp, priority, generation, short_effect, description]
  'moves',       (SELECT json_agg(json_build_array(move_id, move_name, type_name, damage_class, power, accuracy, pp,
                                                   priority, generation, short_effect, description) ORDER BY move_name, move_id)
                  FROM serve.move),
  -- [move_id, valid_from_order, valid_to_order, type, damage_class, power, accuracy, pp]; only moves that changed
  'move_eras',   (SELECT json_agg(json_build_array(move_id, valid_from_order, valid_to_order, type_name, damage_class,
                                                   power, accuracy, pp) ORDER BY move_id, valid_from_order)
                  FROM serve.move_era WHERE move_id IN (SELECT move_id FROM serve.move WHERE eras > 1)),
  -- [item_id, name, category, cost, short_effect, description, machine_kind, is_holdable, item_code]
  'items',       (SELECT json_agg(json_build_array(item_id, item_name, category, cost, short_effect, description,
                                                   machine_kind, is_holdable, item_code) ORDER BY item_name, item_id)
                  FROM serve.item),
  -- [game, item_id, kind, number, move_id]
  'machines',    (SELECT json_agg(json_build_array(game, item_id, kind, number, move_id) ORDER BY game, kind, number)
                  FROM serve.machine),
  -- [game, version_name, dex_no, form, item_id, rarity_pct]
  'held_items',  (SELECT json_agg(json_build_array(game, version_name, dex_no, form, item_id, rarity_pct)
                                   ORDER BY game, version_name, dex_no, form, item_id)
                  FROM serve.held_item),
  -- [game, pokedex_name, dex_no, entry_number]
  'game_pokedex', (SELECT json_agg(json_build_array(game, pokedex_name, dex_no, entry_number) ORDER BY game, pokedex_name, entry_number)
                   FROM serve.game_pokedex),
  -- [game, dex_no, move_id, method, level]
  'learnset',    (SELECT json_agg(json_build_array(game, dex_no, move_id, method, level) ORDER BY game, dex_no, method, level, move_id)
                  FROM serve.learnset),
  -- [game, version_name, place, region, dex_no, form, method, chance_unit, conditions, min_level, max_level, chance]
  'encounters',  (SELECT json_agg(json_build_array(game, version_name, place, region, dex_no, form, method, chance_unit,
                                                   conditions, min_level, max_level, chance)
                                   ORDER BY game, place, dex_no, version_name, region, form, method, chance_unit, conditions)
                  FROM serve.encounter),
  -- [game, version_name, dex_no, flavor_text]
  'pokedex_text', (SELECT json_agg(json_build_array(game, version_name, dex_no, flavor_text) ORDER BY game, dex_no, version_name)
                   FROM serve.pokedex_text)
);
