# Pokeplan in dbt

This folder turns the raw PokeAPI JSON into the star schema. It used to be five SQL files and a stored procedure (`schema/02_reference.sql` to `06_tests.sql`, still in git history); it is now a dbt project that builds exactly the same tables.

dbt starts where the raw layer stops. `schema/01_raw.sql` and `schema/tools/land.sql` still land the JSON into `raw.api_response`, and `schema/08_serve.sql` still creates the views the dashboard reads.

## Run it

```bash
pip install -r dbt/requirements.txt          # dbt-core 1.12 + dbt-postgres 1.11
bash pipeline/run_pipeline.sh                 # the whole pipeline, dbt included
```

Or just the dbt part, against a database that already has raw data:

```bash
cd dbt
dbt build --profiles-dir . --vars "{batch_id: 1}"   # seeds, models, snapshot, tests
dbt build --profiles-dir . -s +fact_pokemon_move    # one model and everything it needs
dbt docs generate --profiles-dir . && dbt docs serve --profiles-dir .   # browse the lineage graph
```

The connection comes from the usual `PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD` and `PGDATABASE` variables (`profiles.yml`). `batch_id` is the `etl.load_batch` row the build belongs to; it is stamped on every mart row as `_batch_id`.

## What is where

| Folder | Becomes | What it is |
|---|---|---|
| `seeds/` | tables in `ref` | Domain facts the API does not carry, as CSV: generation years, when mechanics arrived, which games are remakes or DLC, form and encounter-method rules |
| `models/staging/` | views in `stg` | One view per grain. Each flattens one nested JSON list and turns the API's `past_*` history into eras. Named `stg_<grain>` in dbt and created as `stg.<grain>` |
| `models/intermediate/` | view in `int` | `int_move_era`: every era of every move with all the attributes `dim_move` shows. The snapshot reads it |
| `snapshots/` | table in `snapshots` | `move_era_snapshot`: every version of every move era (see below) |
| `models/marts/` | tables in `mart` | 16 dimensions, 2 bridges, 11 facts and two helper views |
| `tests/` | | Structure, domain and warning tests, plus two generic tests |
| `macros/` | | JSON helpers (English name, clean game text), the primary key post-hook, and the schema naming |

The schema names are the same as before (`ref`, `stg`, `mart`), so the serve views, the dashboard export and `schema/07_example_queries.sql` work unchanged.

## The moves snapshot

A move has two timelines, and they are kept apart:

- **Game time.** Bite was Normal in Red/Blue and Dark from Gold/Silver on. These eras come from the data itself (the API's `past_values`), so `stg_move_era` works them out. They are the `valid_from_order` and `valid_to_order` columns.
- **Load time.** If PokeAPI corrects a move (a wrong power, a reworded effect), the next run should not just overwrite it. The snapshot compares every era with the newest copy it holds. When something changed it closes the old version (`dbt_valid_to`) and opens a new one. An era that disappears from the source is closed too.

`dim_move` is the open version of every era. Its `move_key` is built from the era (`move_id * 10000 + valid_from_order`), so it stays the same from run to run and facts always point at the era that was live in their game.

To see what the warehouse believed about a move on a given day:

```sql
SELECT move_code, valid_from_order, valid_to_order, type_code, power, dbt_valid_from, dbt_valid_to
FROM snapshots.move_era_snapshot
WHERE move_code = 'bite'
  AND '2026-10-15' >= dbt_valid_from
  AND ('2026-10-15' < dbt_valid_to OR dbt_valid_to IS NULL);
```

Tested by raising Tackle's power to 99 in raw and building again: the snapshot closed the old row and opened one with power 99, and `dim_move` showed 99. Setting it back opened a third version. A rerun on unchanged data adds no version; CI checks this.

## Keys

Every dimension's surrogate key comes from its natural key (`pokemon_key = pokemon_id`, and so on), so a full rebuild gives every member the same key as last time. Key 0 is still the Unknown member. Each mart table gets its primary key back through a post-hook (`macros/primary_key.sql`), which also checks the grain whenever a table is written.

Two keys are worked out instead of copied: `dim_move.move_key` (above) and `dim_encounter_condition_set.condition_set_key`, which is the combination's position in alphabetical order. That one can shift when a new combination appears, which is fine because the facts are rebuilt in the same run. Do not store it outside the warehouse.

Before dbt the keys came from identity columns, so their values are different now. Nothing outside the warehouse used them.

## Tests

`dbt build` tests each model right after building it, and a failing test skips everything that depends on that model.

- **Grain**: every staging view and mart table has its grain tested (`unique`, `unique_combination_of_columns`), and the mart primary keys enforce it again.
- **Referential**: every foreign key has a `relationships` test. `not_unknown_member` counts fact rows that fell back to the Unknown member because a dimension row was missing.
- **Structure** (`tests/structure_*.sql`): move eras tile the timeline, generation eras do not overlap, the type chart is square, and the snapshot's open versions match today's source.
- **Domain** (`tests/domain_*.sql`): things a player can check by hand. Gen I had 151 species, Clefairy became Fairy in gen VI, TM26 is Earthquake in Red/Blue, Bite was special in Gold/Silver.
- **Warnings** (`tests/warning_*.sql`): known quirks in the source. They return rows by design (19 and 10 on the 2026-10-07 data) and only warn when that count changes.

## Upgrading a database built by the old SQL

Just run the pipeline: dbt replaces the old views and tables in place. Two old objects are left behind and can be dropped:

```sql
DROP PROCEDURE IF EXISTS mart.load(bigint);
DROP FUNCTION IF EXISTS stg.en_name(jsonb), stg.clean_text(text), stg.en_flavor(jsonb, text);
```
