-- Every species has exactly one default variety.
SELECT species_id, count(*) AS defaults
FROM {{ ref('dim_pokemon') }}
WHERE pokemon_key <> 0 AND is_default_form
GROUP BY species_id
HAVING count(*) <> 1
