{{ config(post_hook="{{ primary_key(['location_area_key', 'pokemon_key', 'version_key', 'slot_seq']) }}",
          indexes=[{'columns': ['pokemon_key']}]) }}
-- Grain: one encounter slot = location_area x pokemon x version x slot_seq.
-- slot_seq is a DEGENERATE DIMENSION (the position in the source array):
-- the API can list two identical slots, and both are real.
-- Coverage: PokeAPI has encounter data up to Sword/Shield and its DLC only.
SELECT COALESCE(la.location_area_key, 0)          AS location_area_key,
       COALESCE(p.pokemon_key, 0)                 AS pokemon_key,
       COALESCE(v.version_key, 0)::smallint       AS version_key,
       s.slot_seq::smallint                       AS slot_seq,
       COALESCE(em.encounter_method_key, 0)::smallint AS encounter_method_key,
       COALESCE(cs.condition_set_key, 0)          AS condition_set_key,
       s.min_level::smallint                      AS min_level,   -- (N)
       s.max_level::smallint                      AS max_level,   -- (N)
       -- (S) adds up within one area + version + method + conditions, and is
       -- a percentage only when dim_encounter_method.chance_unit = 'percent'
       s.chance_pct::smallint                     AS chance_pct,
       {{ audit_columns() }}
FROM {{ ref('stg_encounter') }} s
LEFT JOIN {{ ref('dim_location_area') }} la ON la.location_area_id = s.location_area_id
LEFT JOIN {{ ref('dim_pokemon') }} p        ON p.pokemon_id = s.pokemon_id
LEFT JOIN {{ ref('dim_version') }} v        ON v.version_id = s.version_id
LEFT JOIN {{ ref('dim_encounter_method') }} em ON em.encounter_method_id = s.encounter_method_id
LEFT JOIN {{ ref('dim_encounter_condition_set') }} cs ON cs.condition_set_code = s.condition_set_code
