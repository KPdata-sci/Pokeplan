{{ config(post_hook="{{ primary_key(['encounter_method_key']) }}") }}
-- Grain: one row per encounter method (walk, surf, old-rod, gift,
-- overworld, max-raid, ...). method_group and chance_unit come from the
-- encounter_method_rule seed and say what fact_encounter.chance_pct means.
SELECT l.lookup_id::smallint AS encounter_method_key,
       l.lookup_id::smallint AS encounter_method_id,
       l.lookup_code         AS encounter_method_code,
       l.lookup_name         AS encounter_method_name,
       rule.method_group,    -- land / water / fishing / overworld / raid / roaming / one-off
       rule.chance_unit,     -- percent / weight / n/a
       {{ audit_columns() }}
FROM {{ ref('stg_lookup') }} l
LEFT JOIN LATERAL (SELECT r.method_group, r.chance_unit FROM {{ ref('encounter_method_rule') }} r
                    WHERE l.lookup_code ~ r.code_pattern
                    ORDER BY r.priority LIMIT 1) rule ON true
WHERE l.endpoint = 'encounter-method'
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, NULL, NULL, {{ audit_columns() }}
