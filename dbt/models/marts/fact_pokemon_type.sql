{{ config(post_hook="{{ primary_key(['pokemon_key', 'slot', 'valid_from_generation']) }}") }}
-- FACTLESS FACT with EFFECTIVE DATING. Grain: one row per pokemon x slot
-- x type-era. A pokemon's typing can change between generations (Clefairy:
-- normal until gen V, fairy from gen VI), so each row is valid from one
-- generation to another, like an SCD2 row but versioned by generation.
-- An era never starts before this variety existed (Alolan Raichu's
-- Electric/Psychic typing starts in gen VII).
WITH clamped AS (
    SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key,
           s.slot,
           GREATEST(s.valid_from_generation_id, COALESCE(p.introduced_generation, 1)) AS vf,
           COALESCE(s.valid_to_generation_id, 99) AS vt,
           COALESCE(t.type_key, 0) AS type_key
    FROM {{ ref('stg_pokemon_type') }} s
    LEFT JOIN {{ ref('dim_pokemon') }} p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN {{ ref('dim_type') }} t    ON t.type_id = s.type_id
)
SELECT pokemon_key,
       slot::smallint      AS slot,                   -- 1 = primary, 2 = secondary
       vf::smallint        AS valid_from_generation,
       vt::smallint        AS valid_to_generation,    -- 99 = still current
       type_key::smallint  AS type_key,
       vt = 99             AS is_current,
       {{ audit_columns() }}
FROM clamped
WHERE vf <= vt
