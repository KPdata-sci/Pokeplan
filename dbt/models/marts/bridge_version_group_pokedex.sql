{{ config(post_hook="{{ primary_key(['version_group_key', 'pokedex_key']) }}") }}
-- BRIDGE. Grain: one row per version group x Pokédex it uses.
SELECT vg.version_group_key, COALESCE(d.pokedex_key, 0)::smallint AS pokedex_key,
       {{ audit_columns() }}
FROM {{ ref('stg_version_group_pokedex') }} s
JOIN {{ ref('dim_version_group') }} vg USING (version_group_id)
LEFT JOIN {{ ref('dim_pokedex') }} d USING (pokedex_id)
