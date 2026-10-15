-- The eras of one move tile the whole timeline: they start at 0, have no
-- gaps or overlaps (lengths add up to 10,000 sort-order slots) and exactly
-- one is current.
SELECT move_id
FROM {{ ref('dim_move') }}
WHERE move_key <> 0
GROUP BY move_id
HAVING count(*) FILTER (WHERE is_current) <> 1
    OR min(valid_from_order) <> 0
    OR sum(valid_to_order - valid_from_order + 1) <> 10000
