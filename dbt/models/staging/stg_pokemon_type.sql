-- Grain: pokemon x slot x type-era. past_types replaces the WHOLE typing,
-- so eras are built per pokemon. Each past entry is valid up to and
-- including its generation (Clefairy: normal to gen V, fairy from gen VI).
WITH eras AS (
    SELECT p.resource_id AS pokemon_id,
           raw.url_id(pt->'generation'->>'url') AS valid_to_generation_id,
           pt->'types' AS types
    FROM {{ source('raw', 'current_response') }} p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_types', '[]')) pt
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, NULL, p.payload->'types'
    FROM {{ source('raw', 'current_response') }} p
    WHERE p.endpoint = 'pokemon'
), ranged AS (
    SELECT pokemon_id, types, valid_to_generation_id,
           COALESCE(lag(valid_to_generation_id) OVER (
               PARTITION BY pokemon_id
               ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id
    FROM eras
)
SELECT r.pokemon_id,
       (t->>'slot')::int                AS slot,
       raw.url_id(t->'type'->>'url')    AS type_id,
       r.valid_from_generation_id,
       r.valid_to_generation_id         -- NULL = still current
FROM ranged r
CROSS JOIN LATERAL jsonb_array_elements(r.types) t
