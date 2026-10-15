-- Moves change between games (the SCD2 in dim_move). Bite was a Normal
-- physical move in gen I, a Dark SPECIAL move in gens II-III (all Dark
-- moves were special before the physical/special split), and Dark physical
-- from gen IV. Fire Punch was special until gen III. Charm became Fairy.
SELECT x.*, m.type_code, m.effective_damage_class
FROM (VALUES ('bite', 'red-blue', 'normal', 'physical'),
             ('bite', 'gold-silver', 'dark', 'special'),
             ('bite', 'diamond-pearl', 'dark', 'physical'),
             ('fire-punch', 'emerald', 'fire', 'special'),
             ('fire-punch', 'scarlet-violet', 'fire', 'physical'),
             ('charm', 'black-white', 'normal', 'status'),
             ('charm', 'x-y', 'fairy', 'status')) AS x(move, game, exp_type, exp_class)
LEFT JOIN {{ ref('move_in_version_group') }} m ON m.move_code = x.move AND m.version_group_code = x.game
WHERE (m.type_code, m.effective_damage_class) IS DISTINCT FROM (x.exp_type, x.exp_class)
