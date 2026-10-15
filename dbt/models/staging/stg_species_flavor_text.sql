-- Grain: species x version. The Pokédex entry text each game shows for a
-- species, in English. A few games list the same text twice; keep one.
SELECT DISTINCT ON (s.resource_id, raw.url_id(f->'version'->>'url'))
       s.resource_id                         AS species_id,
       raw.url_id(f->'version'->>'url')      AS version_id,
       {{ clean_text("f->>'flavor_text'") }}     AS flavor_text
FROM {{ source('raw', 'current_response') }} s
CROSS JOIN LATERAL jsonb_array_elements(s.payload->'flavor_text_entries') f
WHERE s.endpoint = 'pokemon-species'
  AND f->'language'->>'name' = 'en'
ORDER BY s.resource_id, raw.url_id(f->'version'->>'url')
