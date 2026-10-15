-- Grain: one row per item.
SELECT resource_id                         AS item_id,
       payload->>'name'                    AS item_code,
       {{ en_name("payload->'names'") }}       AS item_name,
       payload->'category'->>'name'        AS category,
       (payload->>'cost')::int             AS cost,
       (payload->>'fling_power')::int      AS fling_power,
       payload->'fling_effect'->>'name'    AS fling_effect,
       EXISTS (SELECT 1 FROM jsonb_array_elements(payload->'attributes') a
                WHERE a->>'name' = 'holdable')  AS is_holdable,
       {{ clean_text("eff.short_effect") }} AS short_effect,
       {{ en_flavor("payload->'flavor_text_entries'", "text") }} AS description
FROM {{ source('raw', 'current_response') }}
LEFT JOIN LATERAL ({{ en_short_effect("payload->'effect_entries'") }}) eff(short_effect) ON true
WHERE endpoint = 'item'
