-- Grain: one row per location area (an area belongs to one location,
-- a location to one region: we flatten that hierarchy into the dim).
SELECT la.resource_id                                 AS location_area_id,
       la.payload->>'name'                            AS location_area_code,
       {{ en_name("la.payload->'names'") }}               AS location_area_name,
       raw.url_id(la.payload->'location'->>'url')     AS location_id,
       la.payload->'location'->>'name'                AS location_code,
       {{ en_name("l.payload->'names'") }}                AS location_name,
       raw.url_id(l.payload->'region'->>'url')        AS region_id,
       l.payload->'region'->>'name'                   AS region_code
FROM {{ source('raw', 'current_response') }} la
LEFT JOIN {{ source('raw', 'current_response') }} l
       ON l.endpoint = 'location'
      AND l.resource_id = raw.url_id(la.payload->'location'->>'url')
WHERE la.endpoint = 'location-area'
