-- Grain: one row per stat (hp, attack, ... plus accuracy/evasion and the
-- generation-I-only 'special').
SELECT resource_id                           AS stat_id,
       payload->>'name'                      AS stat_code,
       {{ en_name("payload->'names'") }}         AS stat_name,
       (payload->>'is_battle_only')::boolean AS is_battle_only,
       (payload->>'game_index')::int         AS game_index
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'stat'
