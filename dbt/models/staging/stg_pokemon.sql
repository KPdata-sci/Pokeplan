-- Grain: one row per pokemon (a "variety" of a species: e.g. raticate
-- and raticate-alola are two pokemon of one species).
SELECT resource_id                             AS pokemon_id,
       payload->>'name'                        AS pokemon_code,
       raw.url_id(payload->'species'->>'url')  AS species_id,
       (payload->>'is_default')::boolean       AS is_default,
       (payload->>'height')::int               AS height_dm,
       (payload->>'weight')::int               AS weight_hg,
       (payload->>'base_experience')::int      AS base_experience,
       (payload->>'order')::int                AS sort_order
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'pokemon'
