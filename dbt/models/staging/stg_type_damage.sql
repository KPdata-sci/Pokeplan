-- Grain: attacking type x defending type x era (multiplier from the
-- attacker's point of view). Missing pairs are neutral (1x) and are
-- densified in the mart load, not here.
WITH rel AS (
    SELECT t.resource_id AS attacking_type_id,
           NULL::int     AS valid_to_generation_id,
           t.payload->'damage_relations' AS dr
    FROM {{ source('raw', 'current_response') }} t WHERE t.endpoint = 'type'
    UNION ALL
    SELECT t.resource_id,
           raw.url_id(pd->'generation'->>'url'),
           pd->'damage_relations'
    FROM {{ source('raw', 'current_response') }} t
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(t.payload->'past_damage_relations', '[]')) pd
    WHERE t.endpoint = 'type'
)
SELECT r.attacking_type_id,
       raw.url_id(x->>'url') AS defending_type_id,
       k.multiplier,
       r.valid_to_generation_id
FROM rel r
CROSS JOIN LATERAL (VALUES ('no_damage_to', 0.0), ('half_damage_to', 0.5),
                           ('double_damage_to', 2.0)) AS k(rel_key, multiplier)
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(r.dr->k.rel_key, '[]')) x
