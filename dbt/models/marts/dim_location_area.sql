{{ config(post_hook="{{ primary_key(['location_area_key']) }}") }}
-- Grain: one row per location area; location and region flattened in.
SELECT location_area_id::integer         AS location_area_key,
       location_area_id::integer         AS location_area_id,
       location_area_code,
       NULLIF(location_area_name, '')    AS location_area_name,
       location_id::integer              AS location_id,
       location_code,
       location_name,
       region_code,
       {{ audit_columns() }}
FROM {{ ref('stg_location_area') }}
UNION ALL
SELECT 0, 0, 'unknown', NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
