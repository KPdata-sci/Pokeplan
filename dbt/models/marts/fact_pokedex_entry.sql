{{ config(post_hook="{{ primary_key(['species_key', 'pokedex_key']) }}") }}
-- FACTLESS FACT. Grain: one row per species x Pokédex.
-- How the games scope "which Pokémon are in this game": a game uses one or
-- more regional dexes (bridge_version_group_pokedex), each dex lists species.
SELECT COALESCE(sp.species_key, 0)          AS species_key,
       COALESCE(d.pokedex_key, 0)::smallint AS pokedex_key,
       s.entry_number::smallint             AS entry_number,  -- (N) position in that dex
       {{ audit_columns() }}
FROM {{ ref('stg_pokedex_entry') }} s
LEFT JOIN {{ ref('dim_species') }} sp ON sp.species_id = s.species_id
LEFT JOIN {{ ref('dim_pokedex') }} d  ON d.pokedex_id = s.pokedex_id
