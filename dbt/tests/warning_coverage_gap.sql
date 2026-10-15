{{ config(severity='warn', warn_if='!= 10') }}
-- WARNING: games with no learnset or no encounter data in PokeAPI. It
-- returns rows by design (no wild-encounter data after Sword/Shield; DLC
-- learnsets are folded into the base game) and only warns when the count
-- moves away from the 10 recorded in dbt/README.md.
SELECT version_group_code, game_category, has_learnset_data, has_encounter_data
FROM {{ ref('dim_version_group') }}
WHERE version_group_key <> 0 AND NOT (has_learnset_data AND has_encounter_data)
