-- Known type-chart changes (Bulbapedia, Type chart): Ghost could not hit
-- Psychic in gen I; Bug beat Poison in gen I; Steel resisted Ghost and
-- Dark until gen V.
SELECT a.type_code AS attacking, d.type_code AS defending, g.generation_number,
       f.damage_multiplier, x.expected
FROM (VALUES ('ghost','psychic',1,0.0), ('ghost','psychic',2,2.0),
             ('bug','poison',1,2.0),    ('bug','poison',2,0.5),
             ('ice','fire',1,1.0),      ('ice','fire',2,0.5),
             ('ghost','steel',5,0.5),   ('ghost','steel',6,1.0),
             ('dark','steel',5,0.5),    ('dark','steel',6,1.0),
             ('dragon','fairy',6,0.0)) AS x(atk, dfn, gen, expected)
JOIN {{ ref('dim_type') }} a ON a.type_code = x.atk
JOIN {{ ref('dim_type') }} d ON d.type_code = x.dfn
JOIN {{ ref('dim_generation') }} g ON g.generation_number = x.gen
LEFT JOIN {{ ref('fact_type_effectiveness') }} f
       ON f.attacking_type_key = a.type_key AND f.defending_type_key = d.type_key
      AND f.generation_key = g.generation_key
WHERE f.damage_multiplier IS DISTINCT FROM x.expected
