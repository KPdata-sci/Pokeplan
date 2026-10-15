{{ config(post_hook="{{ primary_key(['move_key']) }}",
          indexes=[{'columns': ['move_id', 'valid_from_order'], 'unique': True}]) }}
-- SCD TYPE 2. Grain: one row per move per ERA (a range of version groups
-- in which the move behaved the same).
--   move_id is the DURABLE key (same for every era of one move),
--   move_key is the surrogate key of one era. Facts store the move_key of
--   the era that was live in the fact's game, so a Red/Blue learnset row
--   points at the Normal-type, 10%-flinch Bite, and a Scarlet/Violet row
--   at the Dark-type, 30%-flinch Bite.
-- Built from the current version of each era in move_era_snapshot, which
-- keeps every earlier version too (see snapshots/move_era_snapshot.yml).
SELECT move_key, move_id, valid_from_order, valid_to_order, is_current,
       era_generation, move_code, move_name, type_code, damage_class,
       effective_damage_class, power, accuracy, pp, priority, effect_chance,
       target, ailment, move_category, introduced_generation, short_effect,
       description,
       dbt_valid_from AS version_valid_from,  -- when this version of the era was first loaded
       {{ audit_columns() }}
FROM {{ ref('move_era_snapshot') }}
WHERE dbt_valid_to IS NULL
UNION ALL
SELECT 0, 0, 0::smallint, 9999::smallint, true, NULL, 'n/a', NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
