-- Grain: pokemon x stat x stat-era. past_stats only lists the stats that
-- changed, so eras are built per (pokemon, stat). Each past entry is
-- valid up to and including its generation; the current value runs on.
-- Generation I's 'special' stat only appears in past_stats.
WITH eras AS (
    SELECT p.resource_id                         AS pokemon_id,
           raw.url_id(s->'stat'->>'url')         AS stat_id,
           (s->>'base_stat')::int                AS base_stat,
           (s->>'effort')::int                   AS effort,
           raw.url_id(ps->'generation'->>'url')  AS valid_to_generation_id
    FROM {{ source('raw', 'current_response') }} p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_stats', '[]')) ps
    CROSS JOIN LATERAL jsonb_array_elements(ps->'stats') s
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, raw.url_id(s->'stat'->>'url'),
           (s->>'base_stat')::int, (s->>'effort')::int, NULL
    FROM {{ source('raw', 'current_response') }} p
    CROSS JOIN LATERAL jsonb_array_elements(p.payload->'stats') s
    WHERE p.endpoint = 'pokemon'
)
SELECT pokemon_id, stat_id, base_stat, effort,
       COALESCE(lag(valid_to_generation_id) OVER (
           PARTITION BY pokemon_id, stat_id
           ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id,
       valid_to_generation_id                                 -- NULL = still current
FROM eras
