-- Serving layer: the views the dashboard reads. One view per dashboard dataset,
-- built only from mart tables, so the dashboard never touches raw or staging.
-- Run after CALL mart.load(...) and 06_tests.sql.

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
       st.hp + st.attack + st.defense + st.special_attack + st.special_defense + st.speed AS base_stat_total
FROM mart.dim_pokemon p
JOIN stats st USING (pokemon_key)
JOIN types ty USING (pokemon_key)
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
       (SELECT count(*) FROM raw.api_response r WHERE r.batch_id = b.batch_id) AS raw_responses,
       (SELECT count(DISTINCT endpoint) FROM raw.api_response r WHERE r.batch_id = b.batch_id) AS endpoints
FROM etl.load_batch b
ORDER BY b.batch_id DESC
LIMIT 1;
