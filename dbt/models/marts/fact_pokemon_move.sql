{{ config(post_hook="{{ primary_key(['pokemon_key', 'move_key', 'version_group_key', 'learn_method_key', 'level_learned_at']) }}",
          indexes=[{'columns': ['move_key']}, {'columns': ['version_group_key']}]) }}
-- Grain: one row per pokemon x move x version_group x learn_method x level.
-- The largest table (~640k rows). Level is part of the grain because a
-- Pokémon can learn the same move at several levels (Smeargle: Sketch at
-- 1, 11, 21 ... 91). Answers "which moves can X learn in game Y, how, and
-- at what level". COUNT(DISTINCT move_key) = movepool size.
-- move_key points at the dim_move ERA live in that version group.
--
-- Fact pattern used throughout: look up each surrogate key on the natural
-- key and fall back to 0 (the Unknown member), so a fact row is never lost
-- because a dimension row is missing; the not_unknown_member tests count
-- how often that happens instead.
SELECT COALESCE(p.pokemon_key, 0)              AS pokemon_key,
       COALESCE(m.move_key, 0)                 AS move_key,
       COALESCE(vg.version_group_key, 0)::smallint AS version_group_key,
       COALESCE(lm.learn_method_key, 0)::smallint  AS learn_method_key,
       s.level_learned_at::smallint            AS level_learned_at,  -- (N) 0 when not level-up
       s.learn_order::smallint                 AS learn_order,       -- (N) tie-break within a level
       -- level-up at level 0 = learned on evolving, from Sun/Moon (gen VII) on
       (lm.learn_method_code = 'level-up' AND s.level_learned_at = 0
            AND vg.generation_number >= 7)     AS is_evolution_move,
       {{ audit_columns() }}
FROM {{ ref('stg_pokemon_move') }} s
LEFT JOIN {{ ref('dim_pokemon') }} p        ON p.pokemon_id = s.pokemon_id
LEFT JOIN {{ ref('dim_version_group') }} vg ON vg.version_group_id = s.version_group_id
LEFT JOIN {{ ref('dim_move') }} m           ON m.move_id = s.move_id
                                           AND vg.sort_order BETWEEN m.valid_from_order AND m.valid_to_order
LEFT JOIN {{ ref('dim_learn_method') }} lm  ON lm.learn_method_id = s.learn_method_id
