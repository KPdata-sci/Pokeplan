{{ config(post_hook="{{ primary_key(['learn_method_key']) }}") }}
-- Grain: one row per move learn method (level-up, machine, egg, tutor,
-- plus game-specific ones such as xd-shadow).
SELECT lookup_id::smallint AS learn_method_key,
       lookup_id::smallint AS learn_method_id,
       lookup_code         AS learn_method_code,
       lookup_name         AS learn_method_name,
       {{ audit_columns() }}
FROM {{ ref('stg_lookup') }}
WHERE endpoint = 'move-learn-method'
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, {{ audit_columns() }}
