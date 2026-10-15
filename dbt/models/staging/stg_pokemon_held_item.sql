-- Grain: pokemon x item x version.
SELECT p.resource_id                    AS pokemon_id,
       raw.url_id(h->'item'->>'url')    AS item_id,
       raw.url_id(v->'version'->>'url') AS version_id,
       (v->>'rarity')::int              AS rarity_pct
FROM {{ source('raw', 'current_response') }} p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'held_items') h
CROSS JOIN LATERAL jsonb_array_elements(h->'version_details') v
WHERE p.endpoint = 'pokemon'
