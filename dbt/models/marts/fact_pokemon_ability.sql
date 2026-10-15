{{ config(post_hook="{{ primary_key(['pokemon_key', 'slot', 'valid_from_generation']) }}") }}
-- FACTLESS FACT with EFFECTIVE DATING. Grain: one row per pokemon x
-- ability slot x era. Abilities start in gen III and the hidden slot (3)
-- in gen V (both read from the mechanic seed); some Pokémon swapped
-- abilities later (Gengar: Levitate until gen VI, Cursed Body from gen VII).
-- "Slot did not exist yet" rows (ability NULL in the source) are dropped.
WITH mech AS (
    SELECT max(introduced_generation) FILTER (WHERE mechanic_code = 'abilities')        AS abilities_gen,
           max(introduced_generation) FILTER (WHERE mechanic_code = 'hidden-abilities') AS hidden_gen
    FROM {{ ref('mechanic') }}
), clamped AS (
    SELECT COALESCE(p.pokemon_key, 0) AS pokemon_key,
           s.slot,
           GREATEST(s.valid_from_generation_id, mech.abilities_gen,
                    CASE WHEN s.is_hidden THEN mech.hidden_gen ELSE 1 END,
                    COALESCE(p.introduced_generation, 1))  AS vf,
           COALESCE(s.valid_to_generation_id, 99)          AS vt,
           COALESCE(a.ability_key, 0) AS ability_key,
           s.is_hidden
    FROM {{ ref('stg_pokemon_ability') }} s
    CROSS JOIN mech
    LEFT JOIN {{ ref('dim_pokemon') }} p ON p.pokemon_id = s.pokemon_id
    LEFT JOIN {{ ref('dim_ability') }} a ON a.ability_id = s.ability_id
    WHERE s.ability_id IS NOT NULL
)
SELECT pokemon_key,
       slot::smallint  AS slot,                       -- 1, 2 = regular; 3 = hidden
       vf::smallint    AS valid_from_generation,
       vt::smallint    AS valid_to_generation,
       ability_key,
       is_hidden,
       vt = 99         AS is_current,
       {{ audit_columns() }}
FROM clamped
WHERE vf <= vt
