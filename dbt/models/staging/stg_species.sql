-- Grain: one row per species.
SELECT resource_id                                          AS species_id,
       payload->>'name'                                     AS species_code,
       {{ en_name("payload->'names'") }}                        AS species_name,
       (SELECT g->>'genus' FROM jsonb_array_elements(payload->'genera') g
         WHERE g->'language'->>'name' = 'en' LIMIT 1)       AS genus,
       raw.url_id(payload->'generation'->>'url')            AS generation_id,
       raw.url_id(payload->'evolution_chain'->>'url')       AS evolution_chain_id,
       raw.url_id(payload->'evolves_from_species'->>'url')  AS evolves_from_species_id,
       (payload->>'is_baby')::boolean                       AS is_baby,
       (payload->>'is_legendary')::boolean                  AS is_legendary,
       (payload->>'is_mythical')::boolean                   AS is_mythical,
       (payload->>'capture_rate')::int                      AS capture_rate,
       (payload->>'base_happiness')::int                    AS base_happiness,
       (payload->>'gender_rate')::int                       AS gender_rate,
       (payload->>'hatch_counter')::int                     AS hatch_counter,
       (payload->>'has_gender_differences')::boolean        AS has_gender_differences,
       payload->'growth_rate'->>'name'                      AS growth_rate,
       payload->'color'->>'name'                            AS color,
       payload->'shape'->>'name'                            AS shape,
       payload->'habitat'->>'name'                          AS habitat
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'pokemon-species'
