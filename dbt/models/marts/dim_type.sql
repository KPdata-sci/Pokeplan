{{ config(post_hook="{{ primary_key(['type_key']) }}") }}
-- Grain: one row per type: the 18 battle types plus stellar (Tera only),
-- unknown (???) and shadow (Colosseum/XD).
SELECT t.type_id::smallint               AS type_key,
       t.type_id::integer                AS type_id,
       t.type_code,
       t.type_name,
       t.generation_id::smallint         AS introduced_generation,
       COALESCE(tr.type_role, 'standard') AS type_role,  -- standard / tera-only / non-battle
       t.damage_class                    AS pre_split_damage_class, -- class of ALL its moves in gens I-III
       {{ audit_columns() }}
FROM {{ ref('stg_type') }} t
LEFT JOIN {{ ref('type_role') }} tr USING (type_code)
UNION ALL
SELECT 0::smallint, 0, 'n/a', NULL, NULL, 'non-battle', NULL, {{ audit_columns() }}
