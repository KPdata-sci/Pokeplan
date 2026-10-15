{{ config(post_hook="{{ primary_key(['pokedex_key']) }}") }}
-- Grain: one row per Pokédex (national, kanto, paldea, kitakami, ...).
SELECT pokedex_id::smallint              AS pokedex_key,
       pokedex_id::smallint              AS pokedex_id,
       pokedex_code,
       pokedex_name,
       region_code,                      -- NULL for the national dex
       pokedex_code = 'national'         AS is_national,
       is_main_series,
       {{ audit_columns() }}
FROM {{ ref('stg_pokedex') }}
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, NULL, NULL, NULL, {{ audit_columns() }}
