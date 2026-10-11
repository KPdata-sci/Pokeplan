-- Writes the dashboard's data as one JSON document to stdout.
-- psql -At -f export_dashboard.sql > dashboard_data.json
SELECT json_build_object(
  'pokemon',     (SELECT json_agg(c ORDER BY dex_no) FROM serve.pokemon_card c),
  'type_chart',  (SELECT json_agg(json_build_array(generation, attacking, defending, multiplier)) FROM serve.type_chart),
  'generations', (SELECT json_agg(g ORDER BY generation) FROM serve.generation g),
  'run',         (SELECT row_to_json(r) FROM serve.pipeline_run r),
  'mart_rows',   json_build_object(
      'fact_pokemon_move',       (SELECT count(*) FROM mart.fact_pokemon_move),
      'fact_encounter',          (SELECT count(*) FROM mart.fact_encounter),
      'fact_pokemon_stat',       (SELECT count(*) FROM mart.fact_pokemon_stat),
      'fact_pokedex_entry',      (SELECT count(*) FROM mart.fact_pokedex_entry),
      'fact_pokemon_held_item',  (SELECT count(*) FROM mart.fact_pokemon_held_item),
      'fact_pokemon_ability',    (SELECT count(*) FROM mart.fact_pokemon_ability),
      'fact_type_effectiveness', (SELECT count(*) FROM mart.fact_type_effectiveness),
      'fact_machine',            (SELECT count(*) FROM mart.fact_machine),
      'fact_pokemon_type',       (SELECT count(*) FROM mart.fact_pokemon_type),
      'fact_evolution',          (SELECT count(*) FROM mart.fact_evolution))
);
