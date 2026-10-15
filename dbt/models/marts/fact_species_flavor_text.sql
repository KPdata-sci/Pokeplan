{{ config(post_hook="{{ primary_key(['species_key', 'version_key']) }}") }}
-- Grain: one row per species x game version: the Pokédex entry text that
-- version shows. Lets you read how a species was described in Red
-- compared with Scarlet.
SELECT COALESCE(sp.species_key, 0)         AS species_key,
       COALESCE(v.version_key, 0)::smallint AS version_key,
       s.flavor_text,
       {{ audit_columns() }}
FROM {{ ref('stg_species_flavor_text') }} s
LEFT JOIN {{ ref('dim_species') }} sp ON sp.species_id = s.species_id
LEFT JOIN {{ ref('dim_version') }} v  ON v.version_id = s.version_id
WHERE s.flavor_text IS NOT NULL
