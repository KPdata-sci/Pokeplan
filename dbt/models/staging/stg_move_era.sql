-- Grain: move x era. An era is a range of version groups (by sort_order)
-- in which the move behaved the same. Eras break wherever the move's values
-- changed, and also at the first generation-IV game for moves older than
-- that, because the physical/special split changed every damaging move's
-- class there without the API recording it as a change.
-- past_values only lists the fields that changed, so each field is
-- rebuilt as "the first recorded old value at or after this era, else the
-- current value".
WITH vg AS (
    SELECT version_group_id, sort_order, generation_id FROM {{ ref('stg_version_group') }}
), chg AS (
    SELECT c.*, vg.sort_order AS change_order
    FROM {{ ref('stg_move_change') }} c JOIN vg ON vg.version_group_id = c.changed_in_version_group_id
), split AS (
    SELECT min(vg.sort_order) AS split_order
    FROM vg JOIN {{ ref('mechanic') }} mc ON mc.mechanic_code = 'physical-special-split'
    WHERE vg.generation_id = mc.introduced_generation
), breaks AS (
    SELECT move_id, change_order AS brk FROM chg
    UNION
    SELECT m.move_id, s.split_order FROM {{ ref('stg_move') }} m CROSS JOIN split s
    WHERE m.generation_id < (SELECT introduced_generation FROM {{ ref('mechanic') }}
                              WHERE mechanic_code = 'physical-special-split')
), eras AS (
    SELECT move_id,
           COALESCE(lag(brk) OVER (PARTITION BY move_id ORDER BY brk), 0) AS valid_from_order,
           brk - 1                                                          AS valid_to_order
    FROM breaks
    UNION ALL
    SELECT m.move_id, COALESCE(max(b.brk), 0), 9999
    FROM {{ ref('stg_move') }} m LEFT JOIN breaks b USING (move_id)
    GROUP BY m.move_id
)
SELECT e.move_id, e.valid_from_order, e.valid_to_order,
       (e.valid_to_order = 9999) AS is_current,
       COALESCE((SELECT vg.generation_id FROM vg WHERE vg.sort_order >= e.valid_from_order
                  ORDER BY vg.sort_order LIMIT 1), 1)                   AS era_generation_id,
       COALESCE((SELECT c.old_type_id FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_type_id IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.type_id)          AS type_id,
       COALESCE((SELECT c.old_power FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_power IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.power)            AS power,
       COALESCE((SELECT c.old_accuracy FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_accuracy IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.accuracy)         AS accuracy,
       COALESCE((SELECT c.old_pp FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_pp IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.pp)               AS pp,
       COALESCE((SELECT c.old_effect_chance FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_effect_chance IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.effect_chance)    AS effect_chance
FROM eras e
JOIN {{ ref('stg_move') }} m USING (move_id)
