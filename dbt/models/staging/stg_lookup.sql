-- Small lookup dims share one shape, so one view serves them all.
-- Grain: one row per (endpoint, resource).
SELECT endpoint,
       resource_id                    AS lookup_id,
       payload->>'name'               AS lookup_code,
       {{ en_name("payload->'names'") }}  AS lookup_name
FROM {{ source('raw', 'current_response') }}
WHERE endpoint IN ('move-learn-method', 'encounter-method', 'evolution-trigger')
