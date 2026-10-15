-- The snapshot's current versions are exactly today's eras: every era in
-- int_move_era has one open version with the same values, and no open
-- version is left for an era that has gone.
WITH open_versions AS (
    SELECT move_key, move_id, valid_from_order, valid_to_order, is_current, era_generation,
           move_code, move_name, type_code, damage_class, effective_damage_class, power,
           accuracy, pp, priority, effect_chance, target, ailment, move_category,
           introduced_generation, short_effect, description
    FROM {{ ref('move_era_snapshot') }}
    WHERE dbt_valid_to IS NULL
)
(SELECT 'missing or stale in snapshot' AS problem, * FROM {{ ref('int_move_era') }}
 EXCEPT SELECT 'missing or stale in snapshot', * FROM open_versions)
UNION ALL
(SELECT 'open in snapshot but gone from source', * FROM open_versions
 EXCEPT SELECT 'open in snapshot but gone from source', * FROM {{ ref('int_move_era') }})
