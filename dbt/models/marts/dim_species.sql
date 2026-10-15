{{ config(post_hook="{{ primary_key(['species_key']) }}") }}
-- Grain: one row per species (the "Pokédex entry": Raticate).
-- Used where the game treats all forms alike: evolution chains, Pokédexes.
WITH varieties AS (
    SELECT species_id, count(*) AS n FROM {{ ref('stg_pokemon') }} GROUP BY species_id
)
SELECT s.species_id::integer             AS species_key,
       s.species_id::integer             AS species_id,
       s.species_code,
       s.species_name,
       s.genus,                          -- 'Mouse Pokémon'
       s.generation_id::smallint         AS generation_number,
       s.evolution_chain_id::integer     AS evolution_chain_id,
       CASE WHEN s.is_mythical THEN 'mythical' WHEN s.is_legendary THEN 'legendary'
            WHEN s.is_baby THEN 'baby' ELSE 'regular' END AS species_class,
       s.is_baby,
       s.is_legendary,
       s.is_mythical,
       s.capture_rate::smallint          AS capture_rate,
       s.base_happiness::smallint        AS base_happiness,
       s.gender_rate::smallint           AS gender_rate,     -- eighths female, -1 = genderless
       s.has_gender_differences,
       s.hatch_counter::smallint         AS hatch_counter,
       s.growth_rate,
       s.color,
       s.shape,
       s.habitat,
       COALESCE(v.n, 0)::smallint        AS variety_count,   -- how many dim_pokemon rows it has
       {{ audit_columns() }}
FROM {{ ref('stg_species') }} s
LEFT JOIN varieties v USING (species_id)
UNION ALL
SELECT 0, 0, 'n/a', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
