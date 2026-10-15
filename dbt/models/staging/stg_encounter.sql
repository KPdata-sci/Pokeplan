-- Grain: one encounter slot = location_area x pokemon x version x
-- position in encounter_details[]. The source can list two identical
-- slots (same method, levels and chance), so the array ordinal is part
-- of the grain: without it you would silently de-duplicate real slots.
-- (In the games, a grass area has 12 slots with fixed odds
-- 20/20/10/10/10/10/5/5/4/4/1/1; one Pokémon can fill several of them.)
SELECT la.resource_id                                AS location_area_id,
       raw.url_id(pe->'pokemon'->>'url')             AS pokemon_id,
       raw.url_id(vd->'version'->>'url')             AS version_id,
       ed.ord::int                                   AS slot_seq,
       raw.url_id(ed.e->'method'->>'url')            AS encounter_method_id,
       (ed.e->>'min_level')::int                     AS min_level,
       (ed.e->>'max_level')::int                     AS max_level,
       (ed.e->>'chance')::int                        AS chance_pct,
       COALESCE((SELECT string_agg(cv->>'name', ',' ORDER BY cv->>'name')
                   FROM jsonb_array_elements(ed.e->'condition_values') cv), '') AS condition_set_code
FROM {{ source('raw', 'current_response') }} la
CROSS JOIN LATERAL jsonb_array_elements(la.payload->'pokemon_encounters') pe
CROSS JOIN LATERAL jsonb_array_elements(pe->'version_details') vd
CROSS JOIN LATERAL jsonb_array_elements(vd->'encounter_details') WITH ORDINALITY AS ed(e, ord)
WHERE la.endpoint = 'location-area'
