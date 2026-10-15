-- Grain: one evolution condition = evolution_chain x to_species x
-- position in evolution_details[]. The chain is a tree of unknown depth,
-- so it is walked with a recursive CTE. One step can have several
-- alternative conditions: per game (Magnezone: level up at Mt. Coronet in
-- gen IV, Thunder Stone from Sword/Shield) and per form (Pikachu evolves
-- into Alolan Raichu only in Alola: region + evolved_form).
WITH RECURSIVE walk AS (
    SELECT c.resource_id                AS evolution_chain_id,
           NULL::int                    AS from_species_id,
           c.payload->'chain'           AS node,
           0                            AS depth
    FROM {{ source('raw', 'current_response') }} c WHERE c.endpoint = 'evolution-chain'
    UNION ALL
    SELECT w.evolution_chain_id,
           raw.url_id(w.node->'species'->>'url'),
           child,
           w.depth + 1
    FROM walk w
    CROSS JOIN LATERAL jsonb_array_elements(w.node->'evolves_to') child
)
SELECT w.evolution_chain_id,
       w.from_species_id,
       raw.url_id(w.node->'species'->>'url')             AS to_species_id,
       w.depth                                           AS stage,
       d.ord::int                                        AS detail_seq,
       raw.url_id(d.e->'trigger'->>'url')                AS evolution_trigger_id,
       raw.url_id(d.e->'version_group'->>'url')          AS version_group_id,
       COALESCE((d.e->>'is_default')::boolean, true)     AS is_default_path,
       raw.url_id(d.e->'item'->>'url')                   AS item_id,
       raw.url_id(d.e->'held_item'->>'url')              AS held_item_id,
       raw.url_id(d.e->'known_move'->>'url')             AS known_move_id,
       raw.url_id(d.e->'known_move_type'->>'url')        AS known_move_type_id,
       raw.url_id(d.e->'used_move'->>'url')              AS used_move_id,
       raw.url_id(d.e->'location'->>'url')               AS location_id,
       d.e->'region'->>'name'                            AS region_code,
       raw.url_id(d.e->'trade_species'->>'url')          AS trade_species_id,
       raw.url_id(d.e->'party_species'->>'url')          AS party_species_id,
       raw.url_id(d.e->'party_type'->>'url')             AS party_type_id,
       raw.url_id(d.e->'required_pokemon_form'->>'url')  AS required_form_id,
       raw.url_id(d.e->'evolved_pokemon_form'->>'url')   AS evolved_form_id,
       (d.e->>'min_level')::int                          AS min_level,
       (d.e->>'min_happiness')::int                      AS min_happiness,
       (d.e->>'min_beauty')::int                         AS min_beauty,
       (d.e->>'min_affection')::int                      AS min_affection,
       (d.e->>'min_move_count')::int                     AS min_move_count,
       (d.e->>'min_steps')::int                          AS min_steps,
       (d.e->>'min_damage_taken')::int                   AS min_damage_taken,
       (d.e->>'relative_physical_stats')::int            AS relative_physical_stats,
       NULLIF(d.e->>'time_of_day', '')                   AS time_of_day,
       (d.e->>'gender')::int                             AS gender_id,
       COALESCE((d.e->>'needs_overworld_rain')::boolean, false) AS needs_overworld_rain,
       COALESCE((d.e->>'turn_upside_down')::boolean, false)     AS turn_upside_down,
       COALESCE((d.e->>'near_special_rock')::boolean, false)    AS near_special_rock,
       COALESCE((d.e->>'needs_multiplayer')::boolean, false)    AS needs_multiplayer
FROM walk w
CROSS JOIN LATERAL jsonb_array_elements(w.node->'evolution_details') WITH ORDINALITY AS d(e, ord)
WHERE w.depth > 0
