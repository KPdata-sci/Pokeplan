# Pokédex dashboard

A dashboard fed end to end by the local pipeline.

```
PGHOST=... PGDATABASE=pokeplan bash ../pipeline/run_pipeline.sh   # extract, land, transform, test, serve -> dashboard_data.json
python3 build_dashboard.py                                        # dashboard_template.html + data -> pokedex_dashboard.html
```

What the page answers: every Pokémon (stats, abilities, evolution chain, moves per game, Pokédex text per game,
where to catch it), every game (its Pokédex, new Pokémon, what each TM teaches, wild Pokémon per place, held items),
a team builder (six slots filled by drag and drop or a tap; level, moves the Pokémon can learn in the chosen game, ability, held item, nature, EVs and IVs; the team's shared weaknesses, move coverage with moves that would fill each gap, speed order, and Showdown text import and export), every move (how it changed between eras, who learns it, which TM teaches it) and every item (what it does, which
evolutions use it, which wild Pokémon hold it).

`build_dashboard.py` keeps the first load small. The page carries the Pokémon list, games, evolutions and type chart;
everything bigger goes to a `data/` folder beside it that the page fetches when needed:
`data/games/<game>.json` (one per game), `data/moves.json`, `data/items.json`, `data/pokedex_text.json`.
`data/` is about 13 MB and rebuilt every time, so git ignores it. Publish the html with `data/`, `sprites.webp`
and `items.png` beside it. Over `file://` the browser blocks those fetches; serve the folder
(`python3 -m http.server`) to try it locally.

Pictures: `build_sprites.py <sprites checkout>` packs two sheets from a clone of
[PokeAPI/sprites](https://github.com/PokeAPI/sprites), with their layout in `sprites.json`:
`sprites.webp` (official artwork, each trimmed, scaled to the same square and centred, so every Pokémon looks alike)
and `items.png` (the games' bag icons, centred on 32 px tiles, shown with crisp pixels). Only needed again when
new species or items are added.

- `../pipeline/run_pipeline.sh`: clones the 21 endpoints from PokeAPI/api-data, lands them in `raw.api_response`,
  runs `CALL mart.load`, runs `06_tests.sql` (stops and marks the batch failed if any check fails),
  marks the batch succeeded, creates the serving views and exports JSON.
- `../schema/08_serve.sql`: the serving layer. `serve.pokemon_card` (one row per species, today's types and stats),
  `serve.type_chart`, `serve.generation`, `serve.pipeline_run`, plus `serve.game`, `serve.game_pokedex`,
  `serve.pokemon_ability`, `serve.evolution` (with a plain-English `how`), `serve.move`, `serve.move_era`,
  `serve.learnset`, `serve.machine`, `serve.item`, `serve.held_item`, `serve.encounter` and `serve.pokedex_text`.
  The dashboard reads only these.
- `export_dashboard.sql`: turns the serving views into one JSON document, `dashboard_data.json`. That file is rebuilt on every run, so git ignores it; `pokedex_dashboard.html` keeps the last published snapshot.

Last run: 2026-10-08, api-data commit cdf597a5, 13,671 responses, 27/27 tests passed, about 80 s end to end.
Published page: https://claude.ai/artifact/5FcB4283LcwBfor8YHNzDV
