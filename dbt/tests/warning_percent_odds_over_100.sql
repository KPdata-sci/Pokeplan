{{ config(severity='warn', warn_if='!= 19') }}
-- WARNING: a known quirk of the SOURCE data, not of the model. It returns
-- rows by design; it only warns when the count moves away from the 19
-- recorded in dbt/README.md, so a change in the source gets noticed.
-- Classic encounter tables should add up to at most 100% per area, game,
-- method and condition set. A few in the source do not: horde encounters
-- (X/Y, ORAS), Sun/Moon grass where day and night tables are not tagged
-- with a time condition, some HGSS/Crystal fishing tables. Overworld and
-- raid 'chances' are weights and are excluded.
SELECT v.version_group_code, m.encounter_method_code,
       count(*) AS groups, max(total) AS worst_total
FROM (
    SELECT version_key, encounter_method_key, location_area_key, condition_set_key,
           sum(chance_pct) AS total
    FROM {{ ref('fact_encounter') }}
    GROUP BY 1, 2, 3, 4
) x
JOIN {{ ref('dim_encounter_method') }} m USING (encounter_method_key)
JOIN {{ ref('dim_version') }} v USING (version_key)
WHERE m.chance_unit = 'percent' AND x.total > 100
GROUP BY 1, 2
