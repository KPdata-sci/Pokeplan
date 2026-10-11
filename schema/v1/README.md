# Pokeplan star schema (Postgres 16)

Run in order against an empty database:

| File | Layer | What it does |
|---|---|---|
| `01_raw.sql` | raw / bronze | `raw.api_response` landing table (JSONB, append-only, hash change detection), `etl.load_batch` audit table, `raw.url_id()` helper |
| `02_staging.sql` | staging / silver | One view per grain that flattens the nested JSON (`stg.pokemon_move`, `stg.encounter`, recursive `stg.evolution`, ...) |
| `03_marts.sql` | mart / gold | 15 dimensions + 8 facts, the star schema itself, plus the `mart.pokemon_profile` aggregate view |
| `04_load.sql` | load | `CALL mart.load(batch_id)`: upserts dims on natural key (SCD1), full-refreshes facts, densifies the type chart |
| `05_tests.sql` | tests | Grain, referential and business-rule checks; every query should return zero rows |
| `06_example_queries.sql` | usage | Six questions the star answers, including semi-additive and non-additive measures |

Pipeline per run: insert a row into `etl.load_batch`, crawl the API into `raw.api_response`, then `CALL mart.load(<batch_id>)`, then run `05_tests.sql`.

Tested on 2026-10-08 against PostgreSQL 16.15 using the example responses from the PokeAPI docs (all files apply cleanly, the load is idempotent, the example queries run). The referential tests fail on that tiny sample by design, because the doc examples don't reference each other; they should pass after a full crawl.

Design notes, bus matrix and ER diagrams: https://claude.ai/artifact/PG1jbLypmwWsE339gdRm3E
