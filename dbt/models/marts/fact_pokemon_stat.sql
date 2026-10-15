{{ config(post_hook="{{ primary_key(['pokemon_key', 'stat_key', 'valid_from_generation']) }}") }}
-- EFFECTIVE-DATED. Grain: one row per pokemon x stat x stat-era.
-- Base stats changed between generations (Pikachu's defence and special
-- defence rose in gen VI) and gen I had one Special stat instead of two.
-- SUM(base_stat) over the six core stats of one era = Base Stat Total.
-- Each era is clamped to when the stat existed (stat_validity seed) and to
-- when this variety existed (dim_pokemon.introduced_generation).
WITH clamped AS (
    SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key,
           COALESCE(st.stat_key, 0)   AS stat_key,
           GREATEST(s.valid_from_generation_id, COALESCE(st.valid_from_generation, 1),
                    COALESCE(p.introduced_generation, 1))  AS vf,
           LEAST(COALESCE(s.valid_to_generation_id, 99),
                 COALESCE(st.valid_to_generation, 99))     AS vt,
           s.base_stat, s.effort
    FROM {{ ref('stg_pokemon_stat') }} s
    LEFT JOIN {{ ref('dim_pokemon') }} p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN {{ ref('dim_stat') }} st   ON st.stat_id = s.stat_id
)
SELECT pokemon_key,
       stat_key::smallint      AS stat_key,
       vf::smallint            AS valid_from_generation,
       vt::smallint            AS valid_to_generation,   -- 99 = still current
       vt = 99                 AS is_current,
       base_stat::smallint     AS base_stat,     -- (A across stats of one era, N across pokemon)
       effort::smallint        AS effort_yield,  -- (A) EVs awarded when defeated
       {{ audit_columns() }}
FROM clamped
WHERE vf <= vt
