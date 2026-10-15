-- Grain: one row per version group (e.g. red-blue, sun-moon).
-- sort_order is a global release order across ALL generations, so it is
-- the timeline that move history is measured on.
SELECT resource_id                               AS version_group_id,
       payload->>'name'                          AS version_group_code,
       (payload->>'order')::int                  AS sort_order,
       raw.url_id(payload->'generation'->>'url') AS generation_id
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'version-group'
