{{ config(post_hook="{{ primary_key(['item_key', 'version_group_key']) }}") }}
-- FACTLESS FACT. Grain: one row per machine item x version group.
-- Which move a TM/HM/TR teaches depends on the game: TM26 is Earthquake
-- in Red/Blue, Scary Face in Sword/Shield. move_key is the era of the
-- move live in that game.
SELECT COALESCE(i.item_key, 0)                 AS item_key,
       COALESCE(vg.version_group_key, 0)::smallint AS version_group_key,
       COALESCE(m.move_key, 0)                 AS move_key,
       COALESCE(i.machine_kind, 'other')       AS machine_kind,    -- tm / hm / tr
       substring(s.item_code FROM '^(?:tm|hm|tr)(\d+)$')::smallint AS machine_number,  -- 26 for tm26
       {{ audit_columns() }}
FROM {{ ref('stg_machine') }} s
LEFT JOIN {{ ref('dim_item') }} i           ON i.item_id = s.item_id
LEFT JOIN {{ ref('dim_version_group') }} vg ON vg.version_group_id = s.version_group_id
LEFT JOIN {{ ref('dim_move') }} m           ON m.move_id = s.move_id
                                           AND vg.sort_order BETWEEN m.valid_from_order AND m.valid_to_order
