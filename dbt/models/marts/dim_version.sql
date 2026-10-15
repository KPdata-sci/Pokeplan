{{ config(post_hook="{{ primary_key(['version_key']) }}") }}
-- Grain: one row per individual game version (red, blue, ...). The
-- version -> version group -> generation hierarchy is flattened in.
SELECT v.version_id::smallint            AS version_key,
       v.version_id::smallint            AS version_id,
       v.version_code,
       v.version_name,
       v.version_group_id::smallint      AS version_group_id,
       vg.version_group_code,
       vi.game_category,
       vi.release_year,
       vg.generation_id::smallint        AS generation_id,
       g.generation_code,
       vg.generation_id::smallint        AS generation_number,
       {{ audit_columns() }}
FROM {{ ref('stg_version') }} v
LEFT JOIN {{ ref('stg_version_group') }} vg USING (version_group_id)
LEFT JOIN {{ ref('stg_generation') }} g ON g.generation_id = vg.generation_id
LEFT JOIN {{ ref('version_group_info') }} vi ON vi.version_group_code = vg.version_group_code
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
