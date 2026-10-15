{{ config(post_hook="{{ primary_key(['version_group_key']) }}") }}
-- Grain: one row per version group = one game release (often a pair of
-- versions: Red and Blue). A version group's generation is when it was
-- RELEASED, not where it is set: HeartGold/SoulSilver are a gen IV remake
-- of the gen II games, set in Johto and Kanto.
-- sort_order is the global release order: the timeline of move history.
--
-- has_learnset_data / has_encounter_data say what PokeAPI covers (nothing
-- for encounters after Sword/Shield; DLC learnsets are folded into the base
-- game). They are read from staging, so a later API release that adds data
-- flips them on with no code change.
WITH learnset AS (
    SELECT DISTINCT version_group_id FROM {{ ref('stg_pokemon_move') }}
), encounters AS (
    SELECT DISTINCT v.version_group_id
    FROM {{ ref('stg_encounter') }} e
    JOIN {{ ref('stg_version') }} v USING (version_id)
)
SELECT vg.version_group_id::smallint     AS version_group_key,
       vg.version_group_id::smallint     AS version_group_id,
       vg.version_group_code,
       vg.sort_order::smallint           AS sort_order,
       vg.generation_id::smallint        AS generation_id,
       g.generation_code,
       vg.generation_id::smallint        AS generation_number,
       vi.release_year,
       vi.game_category,                 -- core / enhanced / remake / dlc / spin-off / japan-only
       vi.base_version_group_code,       -- DLC and enhanced games -> their base game
       vi.remake_of_generation,
       (SELECT string_agg(r.region_code, ',' ORDER BY r.region_code)
          FROM {{ ref('stg_version_group_region') }} r
         WHERE r.version_group_id = vg.version_group_id) AS region_codes,
       l.version_group_id IS NOT NULL    AS has_learnset_data,
       e.version_group_id IS NOT NULL    AS has_encounter_data,
       {{ audit_columns() }}
FROM {{ ref('stg_version_group') }} vg
LEFT JOIN {{ ref('stg_generation') }} g USING (generation_id)
LEFT JOIN {{ ref('version_group_info') }} vi USING (version_group_code)
LEFT JOIN learnset l USING (version_group_id)
LEFT JOIN encounters e USING (version_group_id)
UNION ALL
SELECT 0::smallint, 0::smallint, 'unknown', 0::smallint, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
