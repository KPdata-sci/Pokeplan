-- Grain: species x pokedex. The same species has a different number in
-- every regional dex (Pikachu: #25 national, #74 Paldea).
SELECT s.resource_id                         AS species_id,
       raw.url_id(d->'pokedex'->>'url')      AS pokedex_id,
       (d->>'entry_number')::int             AS entry_number
FROM {{ source('raw', 'current_response') }} s
CROSS JOIN LATERAL jsonb_array_elements(s.payload->'pokedex_numbers') d
WHERE s.endpoint = 'pokemon-species'
