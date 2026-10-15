{{ config(materialized='view') }}
-- AS-OF HELPER. Grain: one row per move x version group: the move exactly
-- as it worked in that game. Saves every query from repeating the SCD2
-- range join.
SELECT vg.version_group_key, vg.version_group_code, vg.generation_number,
       m.move_key, m.move_id, m.move_code, m.type_code, m.effective_damage_class,
       m.power, m.accuracy, m.pp, m.effect_chance
FROM {{ ref('dim_version_group') }} vg
JOIN {{ ref('dim_move') }} m
  ON vg.sort_order BETWEEN m.valid_from_order AND m.valid_to_order
WHERE vg.version_group_key <> 0 AND m.move_key <> 0
  AND m.introduced_generation <= vg.generation_number
