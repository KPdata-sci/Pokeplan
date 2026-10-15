-- Grain: move x version group in which some of its values CHANGED.
-- Domain check: Bite lists {type: normal, version_group: gold-silver}.
-- Bite was Normal in Red/Blue and became Dark in Gold/Silver, so the
-- values are the OLD ones, valid up to (not including) that version group.
-- The API docs describe this field the other way round; the games settle it.
SELECT m.resource_id                               AS move_id,
       raw.url_id(pv->'version_group'->>'url')     AS changed_in_version_group_id,
       raw.url_id(pv->'type'->>'url')              AS old_type_id,
       (pv->>'power')::int                         AS old_power,
       (pv->>'accuracy')::int                      AS old_accuracy,
       (pv->>'pp')::int                            AS old_pp,
       (pv->>'effect_chance')::int                 AS old_effect_chance
FROM {{ source('raw', 'current_response') }} m
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(m.payload->'past_values', '[]')) pv
WHERE m.endpoint = 'move'
