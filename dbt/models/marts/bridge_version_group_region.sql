{{ config(post_hook="{{ primary_key(['version_group_key', 'region_code']) }}") }}
-- BRIDGE. Grain: one row per version group x region it takes place in.
-- Needed because the relationship is many-to-many (HGSS = Johto + Kanto).
SELECT vg.version_group_key, r.region_code, {{ audit_columns() }}
FROM {{ ref('stg_version_group_region') }} r
JOIN {{ ref('dim_version_group') }} vg USING (version_group_id)
