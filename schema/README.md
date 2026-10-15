# Pokeplan star schema (Postgres 16), v2

The transformations live in the dbt project in `../dbt` (since October 2026; before that they were the SQL files `02_reference.sql` to `06_tests.sql`, which are in git history). This folder keeps the plain SQL around it and this design write-up.

| Where | Layer | What it does |
|---|---|---|
| `01_raw.sql` | raw / bronze | `raw.api_response` landing table (JSONB, append-only, hash change detection), `etl.load_batch` audit table, `raw.url_id()` helper |
| `tools/land.sql` | raw | Lands a dump of the API as a new batch; only new or changed resources get a row |
| `../dbt/seeds/` | reference | Domain knowledge the API does not carry: generation years, when mechanics arrived (abilities gen III, physical/special split gen IV...), which games are remakes/DLC/spin-offs, form and encounter-method rules |
| `../dbt/models/staging/` | staging / silver | One view per grain that flattens the nested JSON, and turns the API's four `past_*` history shapes into eras (`stg.move_era`, `stg.pokemon_stat`, ...) |
| `../dbt/snapshots/` | snapshot | `snapshots.move_era_snapshot`: every version of every move era the pipeline has seen (SCD type 2 on load time) |
| `../dbt/models/marts/` | mart / gold | 16 dimensions, 2 bridges, 11 facts, plus `mart.pokemon_profile` and the as-of helper `mart.move_in_version_group`. Facts rebuild in full each run; history is clamped to the domain timeline; the type chart is densified |
| `../dbt/tests/` and the `.yml` files | tests | Grain, referential, structural and domain checks, then two warnings that document source-data quirks |
| `07_example_queries.sql` | usage | Eleven questions the star answers, including point-in-time and SCD2 joins |
| `08_serve.sql` | serve | `serve.*` views the dashboard reads (one row per Pokémon card, the type chart, generations, the last pipeline run) |

Pipeline per run: land API responses in `raw.api_response` as a new `etl.load_batch`, then `dbt build --vars "{batch_id: N}"`, then the serve views. `../pipeline/run_pipeline.sh` does all of this in one command.

## Loading without the live API

`pokeapi.co` is blocked from the cloud environment, but PokeAPI publishes every API response as static JSON in the git repo `github.com/PokeAPI/api-data` (`data/api/v2/<endpoint>/<id>/index.json`), which can be cloned. `tools/dump_to_csv.py` turns a checkout into one CSV shaped like `raw.api_response`, and `tools/land.sql` lands it with a single `\copy`. Landing is safe to rerun: only new or changed resources get a row, the old version stays as history with `is_current = false`, and the whole load is one transaction. That is a bulk backfill; the live API is then only needed for incremental refreshes.

```
git clone --depth 1 --filter=blob:none --sparse https://github.com/PokeAPI/api-data.git
cd api-data && git sparse-checkout set data/api/v2/<endpoint> ...   # the 21 endpoints staging reads
psql -d pokeplan -f 01_raw.sql
python3 tools/dump_to_csv.py api-data/data/api/v2 raw.csv
psql -d pokeplan -At -v csv="$PWD/raw.csv" -f tools/land.sql   # prints the new batch_id
cd ../dbt && dbt build --profiles-dir . --vars "{batch_id: <batch_id>}"
```

Endpoints staging reads: generation, version-group, version, region, pokedex, type, stat, ability, move, machine, item, location, location-area, pokemon-species, pokemon, pokemon-form, evolution-chain, move-learn-method, encounter-method, encounter-condition-value, evolution-trigger.

## Tested

2026-10-08, PostgreSQL 16.15, full dataset from `PokeAPI/api-data` (commit of 2026-10-07): 13,671 resources, load takes about 42 s and is idempotent (second run: same row counts).

2026-10-15, after the move to dbt (dbt-core 1.12, dbt-postgres 1.11), same dataset: every staging view and every mart table holds exactly the same rows and column types as the SQL version (keys aside, see `../dbt/README.md`), and the dashboard export is byte-identical. `dbt build` takes about 40 s including the tests.

| Table | Rows |
|---|---|
| fact_pokemon_move | 638,321 |
| fact_encounter | 117,127 |
| fact_species_flavor_text | 14,496 |
| fact_pokedex_entry | 8,010 |
| fact_pokemon_stat | 8,341 |
| fact_pokemon_held_item | 5,448 |
| fact_pokemon_ability | 2,972 |
| fact_type_effectiveness | 2,677 |
| fact_machine | 2,372 |
| fact_pokemon_type | 2,152 |
| fact_evolution | 676 |
| dim_move (eras) | 1,488 for 937 moves |
| dim_pokemon | 1,351 for 1,025 species |

All 27 checks that were in `06_tests.sql` (now in `../dbt/tests/` and the model `.yml` files, with about 200 more column and grain tests added) pass. The two warnings return 19 rows (encounter tables whose percentages add up to more than 100 in the source: X/Y and ORAS hordes, Sun/Moon grass, some Crystal/HGSS fishing) and 10 rows (games with no learnset or no encounter data: PokeAPI has no wild-encounter data after Sword/Shield, and DLC learnsets are folded into the base game).

## What changed from v1, and why

v1 (removed from the tree; see the first commit in git history) modelled the API correctly but treated every game as the same game. Domain research (`../domain/pokemon_domain_notes.md`) and a load of the real data showed where that breaks:

1. **Learnset grain was wrong.** Smeargle learns Sketch at levels 1, 11, ... 91 in the same game, so `level_learned_at` joins the key of `fact_pokemon_move`. v1's primary key rejected the real data.
2. **Moves change between games.** `dim_move` is now SCD type 2 (one row per move per era) and facts point at the era live in their game. Bite is Normal and physical in Red/Blue, Dark and special in Gold/Silver to Emerald, Dark and physical from Diamond/Pearl. The API's own docs describe `past_values` the wrong way round; Bite proves which way it goes.
3. **Stats, abilities and types are generation-dated**, not just types: gen I had one Special stat, gen VI raised many base stats, abilities start in gen III and hidden abilities in gen V. Eras are clamped so nothing is valid before the mechanic or the Pokémon existed (Alolan Raichu starts in gen VII).
4. **Forms are classified** (`form_category`: default, regional, mega, primal, gigantamax, totem, battle-only, alternate) so "all Pokémon" questions can choose what to count.
5. **New stars:** `fact_pokedex_entry` (species x regional dex) with `bridge_version_group_pokedex`, `fact_machine` (TM26 is Earthquake in 20 version groups, then four different moves after that), `bridge_version_group_region` (HeartGold/SoulSilver span two regions).
6. **Encounter chances mean different things** per method: percentages for classic tables, weights for overworld spawns and raids, meaningless for gifts. `dim_encounter_method.chance_unit` says which.
7. **Type chart** excludes Stellar (Tera only) from the dense matrix, giving 15/17/18 types per generation.
8. **Domain tests** check things a player could verify by hand: the gen I type chart bugs, Clefairy becoming Fairy, TM26, species counts per generation.

Design notes and diagrams: https://claude.ai/artifact/PG1jbLypmwWsE339gdRm3E
