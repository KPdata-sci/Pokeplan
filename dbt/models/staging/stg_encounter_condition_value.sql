-- Grain: one row per encounter condition value (time-night, season-winter,
-- weather-raining, story-progress-..., ~360 of them in 30 condition types).
SELECT resource_id                         AS condition_value_id,
       payload->>'name'                    AS condition_value_code,
       payload->'condition'->>'name'       AS condition_code
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'encounter-condition-value'
