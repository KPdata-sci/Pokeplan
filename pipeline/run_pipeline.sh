#!/usr/bin/env bash
# Runs the whole local pipeline end to end and writes dashboard/dashboard_data.json.
#   extract   sparse-clone PokeAPI/api-data (the 21 endpoints staging reads)
#   land      dump to CSV, then schema/tools/land.sql (only new or changed rows)
#   transform dbt build: seeds, staging views, the moves snapshot, mart
#             tables, and every test; an error or failing test stops the run
#   serve     schema/08_serve.sql views, then export JSON for the dashboard
# Needs: git, python3, psql pointed at a database via PG* env vars, and dbt
# (pip install -r dbt/requirements.txt; set DBT=/path/to/dbt if it is not on PATH).
# dbt reads the same PG* variables (dbt/profiles.yml).
# Safe to rerun: an unchanged dump lands no new raw rows.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
schema="$root/schema"
dashboard="$root/dashboard"
dbt_dir="$root/dbt"
dbt=${DBT:-dbt}
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

# The raw layer (landing table, batch log) is plain SQL; everything after it
# is the dbt project. 01_raw.sql only creates what is missing.
psql_ -f "$schema/01_raw.sql" >/dev/null

echo "land: dumping JSON to CSV"
python3 -I "$schema/tools/dump_to_csv.py" "$work/api-data/data/api/v2" "$work/raw.csv"
batch=$(psql_ -X -At -v csv="$work/raw.csv" -v notes="api-data $commit" -f "$schema/tools/land.sql" | tail -1)
# From here on, the batch must not be left 'running': if the script stops
# early (a failed step or failed tests), mark it failed on the way out.
mark_failed() { psql_ -c "UPDATE etl.load_batch SET status='failed', finished_at=now() WHERE batch_id=$batch AND status='running'"; }
trap mark_failed EXIT

echo "transform + test: dbt build (batch $batch)"
# Builds in dependency order and tests each model right after it is built, so
# a failing test skips everything downstream of it. The two warning tests
# (known source-data quirks) never stop the run.
if ! "$dbt" build --project-dir "$dbt_dir" --profiles-dir "$dbt_dir" \
        --vars "{batch_id: $batch}"; then
  echo "transform + test: dbt build failed; dashboard not refreshed" >&2; exit 1
fi
psql_ -c "UPDATE etl.load_batch SET status='succeeded', finished_at=now() WHERE batch_id=$batch"

echo "serve: exporting dashboard data"
psql_ -f "$schema/08_serve.sql" >/dev/null
psql -Atq -f "$dashboard/export_dashboard.sql" > "$dashboard/dashboard_data.json"
echo "done: batch $batch, commit $commit"
