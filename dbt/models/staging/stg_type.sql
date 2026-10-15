-- Grain: one row per type. damage_class is the class that ALL damaging
-- moves of this type had before the physical/special split (gens I-III).
SELECT resource_id                                      AS type_id,
       payload->>'name'                                 AS type_code,
       {{ en_name("payload->'names'") }}                    AS type_name,
       raw.url_id(payload->'generation'->>'url')        AS generation_id,
       payload->'move_damage_class'->>'name'            AS damage_class
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'type'
