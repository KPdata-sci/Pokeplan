-- Land a CSV made by dump_to_csv.py into raw.api_response as a new load batch.
-- Run with psql against a database where 01_raw.sql has been applied.
INSERT INTO etl.load_batch (endpoints, notes) VALUES (NULL, 'static dump from PokeAPI/api-data');
CREATE TEMP TABLE land (endpoint text, resource_id int, resource_name text, source_url text, payload jsonb, payload_sha256 text);
\copy land FROM '/path/to/raw.csv' WITH (FORMAT csv)
INSERT INTO raw.api_response (endpoint, resource_id, resource_name, source_url, payload, payload_sha256, batch_id)
SELECT endpoint, resource_id, resource_name, source_url, payload, payload_sha256,
       (SELECT max(batch_id) FROM etl.load_batch) FROM land;
