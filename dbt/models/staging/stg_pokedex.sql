-- Grain: one row per pokedex (national, kanto, paldea, ...).
SELECT resource_id                             AS pokedex_id,
       payload->>'name'                        AS pokedex_code,
       {{ en_name("payload->'names'") }}           AS pokedex_name,
       payload->'region'->>'name'              AS region_code,
       (payload->>'is_main_series')::boolean   AS is_main_series
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'pokedex'
