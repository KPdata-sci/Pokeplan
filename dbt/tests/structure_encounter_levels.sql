-- An encounter's level range makes sense.
SELECT * FROM {{ ref('fact_encounter') }}
WHERE min_level > max_level
