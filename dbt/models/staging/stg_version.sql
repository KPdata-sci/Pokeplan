-- Grain: one row per version (e.g. red, blue).
SELECT resource_id                                  AS version_id,
       payload->>'name'                             AS version_code,
       {{ en_name("payload->'names'") }}                AS version_name,
       raw.url_id(payload->'version_group'->>'url') AS version_group_id
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'version'
