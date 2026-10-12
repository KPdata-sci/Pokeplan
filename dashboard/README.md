# Pokédex dashboard

A dashboard fed end to end by the local pipeline.

```
PGHOST=... PGDATABASE=pokeplan bash ../pipeline/run_pipeline.sh   # extract, land, transform, test, serve -> dashboard_data.json
python3 build_dashboard.py                                        # dashboard_template.html + data -> pokedex_dashboard.html
```

Pictures: `build_sprites.py <official-artwork folder>` packs the official artwork from
[PokeAPI/sprites](https://github.com/PokeAPI/sprites) (`sprites/pokemon/other/official-artwork`) into one sheet,
`sprites.webp`, plus its layout in `sprites.json`. Each picture is trimmed, scaled to the same square and centred,
so every Pokémon looks alike on the page. Publish `sprites.webp` next to `pokedex_dashboard.html`. Only needed again
when new species are added.

- `../pipeline/run_pipeline.sh`: clones the 21 endpoints from PokeAPI/api-data, lands them in `raw.api_response`,
  runs `CALL mart.load`, runs `06_tests.sql` (stops and marks the batch failed if any check fails),
  marks the batch succeeded, creates the serving views and exports JSON.
- `../schema/08_serve.sql`: the serving layer. `serve.pokemon_card` (one row per species, today's types and stats),
  `serve.type_chart`, `serve.generation`, `serve.pipeline_run`. The dashboard reads only these.
- `export_dashboard.sql`: turns the serving views into one JSON document, `dashboard_data.json`. That file is rebuilt on every run, so git ignores it; `pokedex_dashboard.html` keeps the last published snapshot.

Last run: 2026-10-08, api-data commit cdf597a5, 13,671 responses, 27/27 tests passed, about 80 s end to end.
Published page: https://claude.ai/artifact/5FcB4283LcwBfor8YHNzDV
