{{ config(post_hook="{{ primary_key(['item_key']) }}") }}
-- Grain: one row per item.
SELECT item_id::integer                  AS item_key,
       item_id::integer                  AS item_id,
       item_code,
       item_name,
       category,
       cost,
       fling_power::smallint             AS fling_power,
       fling_effect,
       is_holdable,
       substring(item_code FROM '^(tm|hm|tr)\d+$') AS machine_kind,  -- NULL for other items
       short_effect,                     -- English, what it does
       description,                      -- English, the newest game's bag text
       {{ audit_columns() }}
FROM {{ ref('stg_item') }}
UNION ALL
SELECT 0, 0, 'n/a', NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, {{ audit_columns() }}
