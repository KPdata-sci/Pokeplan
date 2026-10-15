{{ config(materialized='view') }}
-- AGGREGATE "one big table" for dashboards. Grain: one row per pokemon,
-- CURRENT stats only. Built from the star, never from raw.
SELECT p.pokemon_key, p.pokemon_code, p.species_name, p.species_generation,
       p.introduced_generation, p.form_category, p.species_class,
       p.primary_type, p.secondary_type,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'hp')              AS hp,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'attack')          AS attack,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'defense')         AS defense,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'special-attack')  AS special_attack,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'special-defense') AS special_defense,
       MAX(f.base_stat) FILTER (WHERE s.stat_code = 'speed')           AS speed,
       SUM(f.base_stat)                                                AS base_stat_total
FROM {{ ref('dim_pokemon') }} p
JOIN {{ ref('fact_pokemon_stat') }} f USING (pokemon_key)
JOIN {{ ref('dim_stat') }} s USING (stat_key)
WHERE f.is_current
GROUP BY p.pokemon_key, p.pokemon_code, p.species_name, p.species_generation,
         p.introduced_generation, p.form_category, p.species_class,
         p.primary_type, p.secondary_type
