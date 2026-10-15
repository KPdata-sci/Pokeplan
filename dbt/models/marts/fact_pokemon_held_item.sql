{{ config(post_hook="{{ primary_key(['pokemon_key', 'item_key', 'version_key']) }}") }}
-- Grain: one row per pokemon x item x version.
SELECT COALESCE(p.pokemon_key, 0)            AS pokemon_key,
       COALESCE(i.item_key, 0)               AS item_key,
       COALESCE(v.version_key, 0)::smallint  AS version_key,
       s.rarity_pct::smallint                AS rarity_pct,  -- (S) adds up per pokemon + version only
       {{ audit_columns() }}
FROM {{ ref('stg_pokemon_held_item') }} s
LEFT JOIN {{ ref('dim_pokemon') }} p ON p.pokemon_id = s.pokemon_id
LEFT JOIN {{ ref('dim_item') }} i    ON i.item_id = s.item_id
LEFT JOIN {{ ref('dim_version') }} v ON v.version_id = s.version_id
