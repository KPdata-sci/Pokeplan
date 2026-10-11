#!/usr/bin/env bash
# Runs the whole local pipeline end to end and writes dashboard_data.json.
#   extract   sparse-clone PokeAPI/api-data (the 21 endpoints staging reads)
#   land      dump to CSV and COPY into raw.api_response as a new batch
#   transform CALL mart.load(batch)
#   test      06_tests.sql; any failing check stops the run
#   serve     08_serve.sql views, then export JSON for the dashboard
# Needs: git, python3, psql pointed at an empty database via PG* env vars.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
schema="$here/../schema"
work=${WORK:-$(mktemp -d)}
psql_() { psql -v ON_ERROR_STOP=1 -q "$@"; }

endpoints="generation version-group version region pokedex type stat ability move machine item
location location-area pokemon-species pokemon pokemon-form evolution-chain move-learn-method
encounter-method encounter-condition-value evolution-trigger"

echo "extract: cloning api-data"
if [ ! -d "$work/api-data" ]; then
  git clone -q --depth 1 --filter=blob:none --sparse https://github.com/PokeAPI/api-data.git "$work/api-data"
  git -C "$work/api-data" sparse-checkout set $(for e in $endpoints; do printf 'data/api/v2/%s ' "$e"; done)
fi
commit=$(git -C "$work/api-data" rev-parse --short HEAD)

if ! psql -Atqc "select 1 from pg_namespace where nspname='mart'" | grep -q 1; then
  echo "setup: creating schema"
  for f in 01_raw 02_reference 03_staging 04_marts 05_load; do psql_ -f "$schema/$f.sql" >/dev/null; done
fi

echo "land: dumping JSON to CSV"
python3 -I "$schema/tools/dump_to_csv.py" "$work/api-data/data/api/v2" "$work/raw.csv"
batch=$(psql -Atq -v ON_ERROR_STOP=1 \
  -c "INSERT INTO etl.load_batch (notes) VALUES ('api-data $commit') RETURNING batch_id" | tail -1)
psql_ -c "CREATE TEMP TABLE land (endpoint text, resource_id int, resource_name text, source_url text, payload jsonb, payload_sha256 text)" \
      -c "\copy land FROM '$work/raw.csv' WITH (FORMAT csv)" \
      -c "INSERT INTO raw.api_response (endpoint, resource_id, resource_name, source_url, payload, payload_sha256, batch_id)
          SELECT endpoint, resource_id, resource_name, source_url, payload, payload_sha256, $batch FROM land"

echo "transform: mart.load($batch)"
psql_ -c "CALL mart.load($batch)"

echo "test: 06_tests.sql"
# Sections 1-4 must return no rows; the last two queries are warnings by design.
failures=$(psql -q -v ON_ERROR_STOP=1 -f "$schema/06_tests.sql" | grep -o '([0-9]* rows\?)' | head -n -2 | grep -vc '(0 rows)' || true)
if [ "$failures" != "0" ]; then
  psql_ -c "UPDATE etl.load_batch SET status='failed', finished_at=now() WHERE batch_id=$batch"
  echo "test: $failures checks failed; dashboard not refreshed" >&2; exit 1
fi
psql_ -c "UPDATE etl.load_batch SET status='succeeded', finished_at=now(), rows_fetched=(SELECT count(*) FROM raw.api_response WHERE batch_id=$batch) WHERE batch_id=$batch"

echo "serve: exporting dashboard data"
psql_ -f "$here/08_serve.sql" >/dev/null
psql -Atq -f "$here/export_dashboard.sql" > "$here/dashboard_data.json"
echo "done: batch $batch, commit $commit"
