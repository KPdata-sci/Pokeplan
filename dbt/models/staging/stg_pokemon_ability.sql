-- Grain: pokemon x ability slot x era. past_abilities lists only the slots
-- that changed; an entry with ability = null means the slot did not exist
-- yet (Pikachu has no hidden-ability slot up to gen IV). Those rows are
-- kept here with ability_id NULL and dropped in the load.
WITH eras AS (
    SELECT p.resource_id                         AS pokemon_id,
           (a->>'slot')::int                     AS slot,
           raw.url_id(a->'ability'->>'url')      AS ability_id,
           (a->>'is_hidden')::boolean            AS is_hidden,
           raw.url_id(pa->'generation'->>'url')  AS valid_to_generation_id
    FROM {{ source('raw', 'current_response') }} p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_abilities', '[]')) pa
    CROSS JOIN LATERAL jsonb_array_elements(pa->'abilities') a
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, (a->>'slot')::int, raw.url_id(a->'ability'->>'url'),
           (a->>'is_hidden')::boolean, NULL
    FROM {{ source('raw', 'current_response') }} p
    CROSS JOIN LATERAL jsonb_array_elements(p.payload->'abilities') a
    WHERE p.endpoint = 'pokemon'
)
SELECT pokemon_id, slot, ability_id, is_hidden,
       COALESCE(lag(valid_to_generation_id) OVER (
           PARTITION BY pokemon_id, slot
           ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id,
       valid_to_generation_id
FROM eras
