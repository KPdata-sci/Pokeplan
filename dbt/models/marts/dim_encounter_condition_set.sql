{{ config(post_hook="{{ primary_key(['condition_set_key']) }}",
          indexes=[{'columns': ['condition_set_code'], 'unique': True}]) }}
-- JUNK DIMENSION. Grain: one row per distinct *combination* of encounter
-- condition values (e.g. 'season-winter,time-night'). An encounter can
-- have 0..n conditions from 30 condition types (time, season, weather,
-- swarm, radar, GBA cartridge in slot 2, story progress, ...). Instead of
-- a bridge table each observed combination is stored once and the fact
-- gets a single key. Key 0 = no condition.
-- This dimension has no natural integer id, so the key is the combination's
-- position in alphabetical order. It can shift when a new combination
-- appears, which is safe because the facts are rebuilt in the same run.
-- Condition TYPES come from the encounter-condition-value endpoint,
-- because value codes do not always start with their type
-- ('defeated-ghetsis' is a story-progress condition).
WITH sets AS (
    SELECT e.condition_set_code,
           cardinality(string_to_array(e.condition_set_code, ','))       AS n,
           array_agg(DISTINCT cv.condition_code)                         AS type_arr,
           string_agg(DISTINCT cv.condition_code, ',' ORDER BY cv.condition_code) AS types
    FROM (SELECT DISTINCT condition_set_code FROM {{ ref('stg_encounter') }}
           WHERE condition_set_code <> '') e
    CROSS JOIN LATERAL unnest(string_to_array(e.condition_set_code, ',')) AS v(code)
    LEFT JOIN {{ ref('stg_encounter_condition_value') }} cv ON cv.condition_value_code = v.code
    GROUP BY e.condition_set_code
)
SELECT (row_number() OVER (ORDER BY condition_set_code))::integer AS condition_set_key,
       condition_set_code,               -- sorted, comma-joined values
       types                             AS condition_types,  -- sorted, comma-joined types: 'season,time'
       n::smallint                       AS condition_count,
       'time'           = ANY (type_arr) AS has_time_condition,
       'season'         = ANY (type_arr) AS has_season_condition,
       'weather'        = ANY (type_arr) AS has_weather_condition,
       'swarm'          = ANY (type_arr) AS has_swarm_condition,
       'story-progress' = ANY (type_arr) AS has_story_condition,
       {{ audit_columns() }}
FROM sets
UNION ALL
SELECT 0, '', '', 0::smallint, false, false, false, false, false, {{ audit_columns() }}
