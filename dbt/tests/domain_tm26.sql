-- TM numbers mean different moves in different games.
SELECT x.*, mv.move_code
FROM (VALUES ('red-blue', 'earthquake'), ('sword-shield', 'scary-face')) AS x(game, expected)
JOIN {{ ref('dim_version_group') }} vg ON vg.version_group_code = x.game
JOIN {{ ref('dim_item') }} i ON i.item_code = 'tm26'
LEFT JOIN {{ ref('fact_machine') }} f ON f.item_key = i.item_key AND f.version_group_key = vg.version_group_key
LEFT JOIN {{ ref('dim_move') }} mv ON mv.move_key = f.move_key
WHERE mv.move_code IS DISTINCT FROM x.expected
