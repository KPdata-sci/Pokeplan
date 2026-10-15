{{ config(post_hook="{{ primary_key(['attacking_type_key', 'defending_type_key', 'generation_key']) }}") }}
-- DENSE MATRIX FACT. Grain: one row per attacking type x defending type
-- x generation, for every pair of STANDARD types that exist in that
-- generation (15 types in gen I, 17 in II-V, 18 from VI).
-- The API only lists the non-neutral pairs; this model fills in the 1x
-- rows ("densification") so that a missing row always means "this matchup
-- did not exist", never "neutral". For each generation g and pair, it picks
-- the era whose valid_to is the first one >= g (or the current era).
-- Stellar (Tera only), ??? and Shadow are left out. Legends: Arceus uses
-- different numbers (2.5x / 0.4x) that the API does not carry.
SELECT atk.type_key                     AS attacking_type_key,
       dfn.type_key                     AS defending_type_key,
       g.generation_key,
       COALESCE((SELECT td.multiplier
                   FROM {{ ref('stg_type_damage') }} td
                  WHERE td.attacking_type_id = atk.type_id
                    AND td.defending_type_id = dfn.type_id
                    AND COALESCE(td.valid_to_generation_id, 99) = era.valid_to), 1.0
       )::numeric(2,1)                  AS damage_multiplier,  -- (N) 0, 0.5, 1, 2: multiply, never sum
       {{ audit_columns() }}
FROM {{ ref('dim_generation') }} g
JOIN {{ ref('dim_type') }} atk ON atk.type_role = 'standard' AND atk.introduced_generation <= g.generation_number
JOIN {{ ref('dim_type') }} dfn ON dfn.type_role = 'standard' AND dfn.introduced_generation <= g.generation_number
CROSS JOIN LATERAL (
    SELECT MIN(COALESCE(x.valid_to_generation_id, 99)) AS valid_to
    FROM (SELECT DISTINCT valid_to_generation_id FROM {{ ref('stg_type_damage') }}
           WHERE attacking_type_id = atk.type_id) x
    WHERE COALESCE(x.valid_to_generation_id, 99) >= g.generation_number
) era
WHERE g.generation_key <> 0
