{{ config(post_hook="{{ primary_key(['stat_key']) }}") }}
-- Grain: one row per stat: hp, attack, defense, special-attack,
-- special-defense, speed, the battle-only accuracy and evasion, and the
-- generation-I-only special.
SELECT s.stat_id::smallint                AS stat_key,
       s.stat_id::smallint                AS stat_id,
       s.stat_code,
       s.stat_name,
       s.is_battle_only,
       COALESCE(sv.valid_from_generation, 1)::smallint AS valid_from_generation,
       COALESCE(sv.valid_to_generation, 99)::smallint  AS valid_to_generation,
       s.stat_id::smallint                AS display_order,
       {{ audit_columns() }}
FROM {{ ref('stg_stat') }} s
LEFT JOIN {{ ref('stat_validity') }} sv USING (stat_code)
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
