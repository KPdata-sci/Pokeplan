-- Grain: one row per move, CURRENT values.
SELECT resource_id                                AS move_id,
       payload->>'name'                           AS move_code,
       {{ en_name("payload->'names'") }}              AS move_name,
       raw.url_id(payload->'type'->>'url')        AS type_id,
       payload->'damage_class'->>'name'           AS damage_class,
       (payload->>'power')::int                   AS power,
       (payload->>'accuracy')::int                AS accuracy,
       (payload->>'pp')::int                      AS pp,
       (payload->>'priority')::int                AS priority,
       (payload->>'effect_chance')::int           AS effect_chance,
       payload->'target'->>'name'                 AS target,
       payload->'meta'->'ailment'->>'name'        AS ailment,
       payload->'meta'->'category'->>'name'       AS move_category,
       raw.url_id(payload->'generation'->>'url')  AS generation_id,
       -- English texts. The short effect has a $effect_chance placeholder.
       {{ clean_text("replace(eff.short_effect, '$effect_chance', COALESCE(payload->>'effect_chance', ''))") }} AS short_effect,
       {{ en_flavor("payload->'flavor_text_entries'", "flavor_text") }} AS description
FROM {{ source('raw', 'current_response') }}
LEFT JOIN LATERAL ({{ en_short_effect("payload->'effect_entries'") }}) eff(short_effect) ON true
WHERE endpoint = 'move'
