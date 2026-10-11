#!/usr/bin/env bash
# Runs the whole local pipeline end to end and writes dashboard_data.json.
#   extract   sparse-clone PokeAPI/api-data (the 21 endpoints staging reads)
#   land      dump to CSV, then schema/tools/land.sql (only new or changed rows)
#   transform CALL mart.load(batch)
#   test      06_tests.sql; any failing check stops the run
#   serve     08_serve.sql views, then export JSON for the dashboard
# Needs: git, python3, psql pointed at a database via PG* env vars.
# Safe to rerun: an unchanged dump lands no new raw rows.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
schema="$here/../schema"
work=${WORK:-$(mktemp -d)}
export PGOPTIONS="${PGOPTIONS:-} -c client_min_messages=warning"  # hide 'already exists' notices on reruns
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
batch=$(psql_ -X -At -v csv="$work/raw.csv" -v notes="api-data $commit" -f "$schema/tools/land.sql" | tail -1)
# From here on, the batch must not be left 'running': if the script stops
# early (a failed step or failed tests), mark it failed on the way out.
mark_failed() { psql_ -c "UPDATE etl.load_batch SET status='failed', finished_at=now() WHERE batch_id=$batch AND status='running'"; }
trap mark_failed EXIT

echo "transform: mart.load($batch)"
psql_ -c "CALL mart.load($batch)"

echo "test: 06_tests.sql"
# Sections 1-4 must return no rows; the last two queries are warnings by design.
failures=$(psql -q -v ON_ERROR_STOP=1 -f "$schema/06_tests.sql" | grep -o '([0-9]* rows\?)' | head -n -2 | grep -vc '(0 rows)' || true)
if [ "$failures" != "0" ]; then
  echo "test: $failures checks failed; dashboard not refreshed" >&2; exit 1
fi
psql_ -c "UPDATE etl.load_batch SET status='succeeded', finished_at=now() WHERE batch_id=$batch"

echo "serve: exporting dashboard data"
psql_ -f "$here/08_serve.sql" >/dev/null
psql -Atq -f "$here/export_dashboard.sql" > "$here/dashboard_data.json"
echo "done: batch $batch, commit $commit"
