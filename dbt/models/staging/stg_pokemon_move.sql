-- Grain: pokemon x move x version_group x learn_method x level.
-- Level IS part of the grain: Smeargle learns Sketch at levels 1, 11, 21,
-- ... 91 in the same game, and some Pokémon relearn a move at a later level.
-- Source: pokemon.moves[].version_group_details[] (two levels of nesting).
SELECT p.resource_id                                         AS pokemon_id,
       raw.url_id(m->'move'->>'url')                         AS move_id,
       raw.url_id(d->'version_group'->>'url')                AS version_group_id,
       raw.url_id(d->'move_learn_method'->>'url')            AS learn_method_id,
       (d->>'level_learned_at')::int                         AS level_learned_at,
       (d->>'order')::int                                    AS learn_order
FROM {{ source('raw', 'current_response') }} p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'moves') m
CROSS JOIN LATERAL jsonb_array_elements(m->'version_group_details') d
WHERE p.endpoint = 'pokemon'
