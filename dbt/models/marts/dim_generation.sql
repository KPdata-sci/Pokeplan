{{ config(post_hook="{{ primary_key(['generation_key']) }}") }}
-- Grain: one row per generation (I .. IX), plus the Unknown member (key 0).
--
-- Keys: every dimension's surrogate key is derived from its natural key
-- (here generation_key = generation_id), so a full rebuild gives every
-- member the same key as last time. Key 0 is the "Unknown / Not applicable"
-- member: facts never hold NULL foreign keys and inner joins never drop rows.
SELECT g.generation_id::smallint        AS generation_key,
       g.generation_id::smallint        AS generation_id,
       g.generation_code,
       g.generation_name,
       g.generation_id::smallint        AS generation_number,
       gi.roman,
       g.main_region_code,               -- the NEW region of that generation
       gi.first_release_year,
       gi.last_release_year,
       gi.platform,
       (SELECT string_agg(mc.mechanic_code, ', ' ORDER BY mc.mechanic_code)
          FROM {{ ref('mechanic') }} mc
         WHERE mc.introduced_generation = g.generation_id) AS mechanics_introduced,
       {{ audit_columns() }}
FROM {{ ref('stg_generation') }} g
LEFT JOIN {{ ref('generation_info') }} gi ON gi.generation_number = g.generation_id
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', 'Unknown', 0::smallint, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
