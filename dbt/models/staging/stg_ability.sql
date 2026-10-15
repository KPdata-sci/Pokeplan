-- Grain: one row per ability.
SELECT resource_id                                AS ability_id,
       payload->>'name'                           AS ability_code,
       {{ en_name("payload->'names'") }}              AS ability_name,
       (payload->>'is_main_series')::boolean      AS is_main_series,
       raw.url_id(payload->'generation'->>'url')  AS generation_id,
       (SELECT e->>'short_effect'
          FROM jsonb_array_elements(payload->'effect_entries') e
         WHERE e->'language'->>'name' = 'en' LIMIT 1) AS short_effect
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'ability'
