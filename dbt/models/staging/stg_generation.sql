-- Grain: one row per generation.
SELECT resource_id                                AS generation_id,
       payload->>'name'                           AS generation_code,
       {{ en_name("payload->'names'") }}              AS generation_name,
       raw.url_id(payload->'main_region'->>'url') AS main_region_id,
       payload->'main_region'->>'name'            AS main_region_code
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'generation'
