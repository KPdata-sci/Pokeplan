-- Grain: version group x region. Usually one region per game, but
-- HeartGold/SoulSilver visit Johto AND Kanto, so this is many-to-many.
SELECT vg.resource_id                AS version_group_id,
       raw.url_id(r->>'url')         AS region_id,
       r->>'name'                    AS region_code
FROM {{ source('raw', 'current_response') }} vg
CROSS JOIN LATERAL jsonb_array_elements(vg.payload->'regions') r
WHERE vg.endpoint = 'version-group'
