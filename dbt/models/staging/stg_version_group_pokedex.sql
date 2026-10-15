-- Grain: version group x pokedex (which regional dexes a game uses).
SELECT vg.resource_id                AS version_group_id,
       raw.url_id(d->>'url')         AS pokedex_id
FROM {{ source('raw', 'current_response') }} vg
CROSS JOIN LATERAL jsonb_array_elements(vg.payload->'pokedexes') d
WHERE vg.endpoint = 'version-group'
