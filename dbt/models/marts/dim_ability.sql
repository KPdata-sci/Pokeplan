{{ config(post_hook="{{ primary_key(['ability_key']) }}") }}
-- Grain: one row per ability.
SELECT ability_id::integer               AS ability_key,
       ability_id::integer               AS ability_id,
       ability_code,
       ability_name,
       short_effect,
       is_main_series,
       generation_id::smallint           AS introduced_generation,
       {{ audit_columns() }}
FROM {{ ref('stg_ability') }}
UNION ALL
SELECT 0, 0, 'unknown', NULL, NULL, NULL, NULL, {{ audit_columns() }}
