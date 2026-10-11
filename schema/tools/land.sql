-- Land a CSV made by dump_to_csv.py into raw.api_response as a new load batch.
--
--   psql -X -v csv=/full/path/raw.csv [-v notes='...'] -f land.sql
--
-- Needs 01_raw.sql applied. Prints the new batch_id last, so a script can
-- capture it and pass it on to CALL mart.load(batch_id).
--
-- Safe to rerun (idempotent): a resource only gets a new row when its payload
-- hash differs from its current version. That row becomes the current one and
-- the old version stays as history. Re-landing the same dump changes nothing.
--
-- All or nothing (atomic): everything runs in one transaction, so a failed
-- load leaves no half-landed rows and no batch behind.
--
-- The batch is left as 'running'. Whoever runs the transform and the tests
-- marks it 'succeeded' or 'failed' (pipeline/run_pipeline.sh does this).

\set ON_ERROR_STOP on
\if :{?csv}
\else
  \echo 'usage: psql -v csv=/full/path/raw.csv -f land.sql'
  SELECT 1/0 AS missing_csv_variable;  -- stop with an error, not a silent success
\endif
\if :{?notes}
\else
  \set notes 'static dump from PokeAPI/api-data'
\endif

BEGIN;

INSERT INTO etl.load_batch (notes) VALUES (:'notes')
RETURNING batch_id \gset

CREATE TEMP TABLE land (
    endpoint text, resource_id int, resource_name text,
    source_url text, payload jsonb, payload_sha256 text
) ON COMMIT DROP;

-- \copy does not expand :variables in its arguments, so build the command
-- as a variable and run that.
\set copy_cmd '\\copy land FROM ' :'csv' ' WITH (FORMAT csv)'
:copy_cmd

-- Rows that are new or whose content changed since the current version.
CREATE TEMP TABLE changed ON COMMIT DROP AS
SELECT l.*
FROM land l
WHERE NOT EXISTS (
    SELECT 1 FROM raw.api_response r
    WHERE r.endpoint = l.endpoint AND r.resource_id = l.resource_id
      AND r.is_current AND r.payload_sha256 = l.payload_sha256);

-- Retire the old version first, so the "one current row per resource"
-- index never sees two current rows.
UPDATE raw.api_response r
SET is_current = false
FROM changed c
WHERE r.endpoint = c.endpoint AND r.resource_id = c.resource_id AND r.is_current;

-- A payload can change back to an older version we already hold. That row
-- exists, so make it current again instead of inserting a duplicate.
INSERT INTO raw.api_response (endpoint, resource_id, resource_name, source_url, payload, payload_sha256, batch_id)
SELECT endpoint, resource_id, resource_name, source_url, payload, payload_sha256, :batch_id
FROM changed
ON CONFLICT (endpoint, resource_id, payload_sha256) DO UPDATE SET is_current = true;

UPDATE etl.load_batch
SET endpoints    = (SELECT array_agg(DISTINCT endpoint ORDER BY endpoint) FROM land),
    rows_fetched = (SELECT count(*) FROM land),
    rows_changed = (SELECT count(*) FROM changed)
WHERE batch_id = :batch_id;

COMMIT;

SELECT :batch_id AS batch_id;
