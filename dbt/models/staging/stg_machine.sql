-- Grain: one row per machine = one TM/HM/TR item in one version group.
-- The same item teaches different moves in different games
-- (TM26 is Earthquake in Red/Blue, Scary Face in Sword/Shield).
SELECT resource_id                                  AS machine_id,
       raw.url_id(payload->'item'->>'url')          AS item_id,
       payload->'item'->>'name'                     AS item_code,
       raw.url_id(payload->'move'->>'url')          AS move_id,
       raw.url_id(payload->'version_group'->>'url') AS version_group_id
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'machine'
