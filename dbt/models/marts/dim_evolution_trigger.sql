{{ config(post_hook="{{ primary_key(['evolution_trigger_key']) }}") }}
-- Grain: one row per evolution trigger (level-up, trade, use-item, shed,
-- spin, three-critical-hits, agile-style-move, gimmighoul-coins, ...).
SELECT lookup_id::smallint AS evolution_trigger_key,
       lookup_id::smallint AS evolution_trigger_id,
       lookup_code         AS evolution_trigger_code,
       lookup_name         AS evolution_trigger_name,
       {{ audit_columns() }}
FROM {{ ref('stg_lookup') }}
WHERE endpoint = 'evolution-trigger'
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, {{ audit_columns() }}
