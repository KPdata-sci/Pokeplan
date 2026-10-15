-- Grain: one row per move per ERA, with every attribute dim_move shows.
-- This is what the snapshot (snapshots/move_era_snapshot.yml) records.
--
-- An era is a range of version groups (by release sort_order) in which a
-- move behaved the same; stg_move_era works the ranges out from the API's
-- past_values. move_key is derived from the era itself (move_id * 10000 +
-- valid_from_order), so it is the same on every run and facts built in
-- different runs agree on it.
--
-- effective_damage_class applies the physical/special split: before
-- generation IV a damaging move's class came from its TYPE (all Fire moves
-- special, all Normal moves physical); from gen IV each move has its own.
WITH split AS (
    SELECT introduced_generation AS split_generation
    FROM {{ ref('mechanic') }} WHERE mechanic_code = 'physical-special-split'
)
SELECT (e.move_id * 10000 + e.valid_from_order)::integer AS move_key,
       e.move_id::integer                    AS move_id,
       e.valid_from_order::smallint          AS valid_from_order,
       e.valid_to_order::smallint            AS valid_to_order,
       e.is_current,
       e.era_generation_id::smallint         AS era_generation,
       m.move_code,
       m.move_name,
       t.type_code,
       m.damage_class,
       CASE WHEN m.damage_class = 'status' THEN 'status'
            WHEN e.era_generation_id < split.split_generation
                 THEN COALESCE(t.damage_class, m.damage_class)
            ELSE m.damage_class END          AS effective_damage_class,
       e.power::smallint                     AS power,
       e.accuracy::smallint                  AS accuracy,
       e.pp::smallint                        AS pp,
       m.priority::smallint                  AS priority,
       e.effect_chance::smallint             AS effect_chance,
       m.target,
       m.ailment,
       m.move_category,
       m.generation_id::smallint             AS introduced_generation,
       m.short_effect,
       m.description
FROM {{ ref('stg_move_era') }} e
JOIN {{ ref('stg_move') }} m USING (move_id)
LEFT JOIN {{ ref('stg_type') }} t ON t.type_id = e.type_id
CROSS JOIN split
