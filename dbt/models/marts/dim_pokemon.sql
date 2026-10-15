{{ config(post_hook="{{ primary_key(['pokemon_key']) }}") }}
-- Grain: one row per pokemon = one battle-relevant variety of a species.
-- raticate and raticate-alola are two rows; charizard-mega-x and
-- charizard-gmax are rows too. Purely cosmetic forms (Unown A..Z, Vivillon
-- patterns) are NOT rows: they share stats, types and moves, so they are
-- counted in cosmetic_form_count instead.
-- form_category tells them apart, so "all Pokémon" questions can choose:
--   default    the species' standard variety
--   regional   Alolan / Galarian / Hisuian / Paldean variants
--   mega, primal, gigantamax, totem   temporary or battle-only transformations
--   battle-only  other in-battle forms (Aegislash Blade, Darmanitan Zen)
--   alternate  permanent alternative varieties (Rotom appliances, Therian forms)
WITH default_form AS (
    -- the pokemon's own default form (a few, e.g. koraidon-limited-build,
    -- have a single form not flagged default, hence DISTINCT ON)
    SELECT DISTINCT ON (pokemon_id) *
    FROM {{ ref('stg_pokemon_form') }}
    ORDER BY pokemon_id, is_default DESC, form_id
), form_count AS (
    SELECT pokemon_id, count(*) AS n FROM {{ ref('stg_pokemon_form') }} GROUP BY pokemon_id
), current_type AS (
    SELECT pt.pokemon_id, pt.slot, t.type_code
    FROM {{ ref('stg_pokemon_type') }} pt
    JOIN {{ ref('stg_type') }} t USING (type_id)
    WHERE pt.valid_to_generation_id IS NULL
)
SELECT p.pokemon_id::integer             AS pokemon_key,
       p.pokemon_id::integer             AS pokemon_id,
       p.pokemon_code,                   -- 'raticate-alola'
       p.is_default                      AS is_default_form,
       CASE WHEN rule.form_category IS NOT NULL THEN rule.form_category
            WHEN p.is_default THEN 'default'
            WHEN f.is_battle_only THEN 'battle-only'
            ELSE 'alternate' END         AS form_category,
       rule.region_code                  AS form_region_code,
       f.is_battle_only,
       f.is_mega,
       (COALESCE(fc.n, 1) - 1)::smallint AS cosmetic_form_count,
       vg.version_group_code             AS introduced_version_group,  -- when THIS variety first appeared
       vg.generation_id::smallint        AS introduced_generation,     -- raichu-alola: 7, though raichu is gen I
       (p.height_dm / 10.0)::numeric(5,1) AS height_m,                -- API gives decimetres
       (p.weight_hg / 10.0)::numeric(6,1) AS weight_kg,               -- API gives hectograms
       p.base_experience::smallint       AS base_experience,
       t1.type_code                      AS primary_type,              -- current typing, convenience copy
       t2.type_code                      AS secondary_type,
       -- denormalised from species
       s.species_id::integer             AS species_id,
       s.species_code,
       s.species_name,
       s.generation_id::smallint         AS species_generation,
       CASE WHEN s.is_mythical THEN 'mythical' WHEN s.is_legendary THEN 'legendary'
            WHEN s.is_baby THEN 'baby' ELSE 'regular' END AS species_class,
       s.is_legendary,
       s.is_mythical,
       s.is_baby,
       s.capture_rate::smallint          AS capture_rate,
       s.growth_rate,
       s.color,
       s.habitat,
       {{ audit_columns() }}
FROM {{ ref('stg_pokemon') }} p
LEFT JOIN {{ ref('stg_species') }} s USING (species_id)
LEFT JOIN default_form f ON f.pokemon_id = p.pokemon_id
LEFT JOIN form_count fc ON fc.pokemon_id = p.pokemon_id
LEFT JOIN {{ ref('stg_version_group') }} vg ON vg.version_group_id = f.introduced_version_group_id
LEFT JOIN LATERAL (SELECT r.form_category, r.region_code FROM {{ ref('form_rule') }} r
                    WHERE p.pokemon_code ~ r.code_pattern
                    ORDER BY r.priority LIMIT 1) rule ON true
LEFT JOIN current_type t1 ON t1.pokemon_id = p.pokemon_id AND t1.slot = 1
LEFT JOIN current_type t2 ON t2.pokemon_id = p.pokemon_id AND t2.slot = 2
UNION ALL
SELECT 0, 0, 'unknown', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL,
       {{ audit_columns() }}
