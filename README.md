# Pokeplan

A learning project for data engineering. It takes the [PokeAPI v2](https://pokeapi.co/docs/v2) and builds a full pipeline around it: land the raw JSON, model it as a star schema in Postgres, test it, and serve it to a dashboard. There is also a design for running the same thing on AWS, written in Terraform.

## What is in here

| Folder | What it is |
|---|---|
| `pipeline/` | `run_pipeline.sh`: the one command that runs every step below |
| `dbt/` | The transformations as a dbt project: reference seeds, staging views, the star schema's dimensions and facts, the moves snapshot and the tests. Start with `dbt/README.md` |
| `schema/` | Plain SQL around the dbt project: the raw landing layer, the serve views the dashboard reads, and example queries. `schema/tools/` lands the raw data. `schema/README.md` explains the model's design |
| `dashboard/` | The Pokédex dashboard: its template, the export query and the build script |
| `reference/` | Machine-readable reference for the API (52 endpoints, 125 object types), the docs it was built from, and the scripts that build it |
| `domain/` | Notes on the Pokémon world that the API does not explain (generations, remakes, forms, how mechanics changed) |
| `architecture/` | The AWS design (event-driven, with dlt, Iceberg/Athena, dbt, Dagster, Soda and Metabase) and its Terraform |

## Run the pipeline

You need Postgres 16, Python 3, git and dbt (`pip install -r dbt/requirements.txt`). The pipeline reads the static copy of the API from [PokeAPI/api-data](https://github.com/PokeAPI/api-data), so it does not call pokeapi.co.

```bash
createdb pokeplan
PGDATABASE=pokeplan bash pipeline/run_pipeline.sh   # extract, land, transform, test, serve (about a minute)
python3 dashboard/build_dashboard.py                # writes dashboard/pokedex_dashboard.html
```

Open `dashboard/pokedex_dashboard.html` in a browser to see the result.

What the script does, in order:

1. Clones the 21 endpoints it needs from `PokeAPI/api-data`.
2. Lands every response in `raw.api_response`.
3. Runs `dbt build` (the project in `dbt/`): seeds, staging views, the moves snapshot, the dimension and fact tables, and about 220 tests. It stops if any test fails.
4. Marks the batch succeeded.
5. Creates the serving views and exports them to `dashboard/dashboard_data.json`.

The script is safe to rerun: only new or changed API responses are landed, and every run is recorded in `etl.load_batch` as succeeded or failed.

GitHub Actions runs the whole pipeline twice on every pull request (`.github/workflows/pipeline.yml`). The second run must land zero changed rows and must not add any new version to the moves snapshot, which proves the pipeline is idempotent.

## The model in one paragraph

Raw JSON goes into one landing table. Reference seeds add domain facts the API lacks, such as when each mechanic arrived. Staging views flatten the JSON. The mart has 10 fact tables and 16 dimensions. Stats, types and abilities are dated by generation, and moves are a type 2 slowly changing dimension, because a move like Bite changed type and category between games; a dbt snapshot also keeps every earlier version of each move era, so a correction in the source never overwrites history. `schema/README.md` explains every choice.

## AWS and Terraform

`architecture/terraform/` holds modules for network, storage, IAM, compute, events and governance, with two layouts: `learning.tfvars` (about $70 a month) and `prod.tfvars`. Values marked `REPLACE` are placeholders. Nothing here has been applied to a real account. See `architecture/terraform/README.md`.
