-- Grain: one row per pokemon form. Most pokemon have exactly one form;
-- cosmetic variants (Unown's 28 letters, Vivillon's patterns) are extra
-- FORMS of one pokemon, while battle-relevant variants (megas, regional
-- forms) are separate POKEMON, each with its own default form.
SELECT resource_id                                   AS form_id,
       payload->>'name'                              AS form_code,
       NULLIF(payload->>'form_name', '')             AS form_name,
       raw.url_id(payload->'pokemon'->>'url')        AS pokemon_id,
       (payload->>'is_default')::boolean             AS is_default,
       (payload->>'is_battle_only')::boolean         AS is_battle_only,
       (payload->>'is_mega')::boolean                AS is_mega,
       raw.url_id(payload->'version_group'->>'url')  AS introduced_version_group_id
FROM {{ source('raw', 'current_response') }} WHERE endpoint = 'pokemon-form'
