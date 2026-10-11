# API reference

A machine-readable description of PokeAPI v2, built from the API's own docs.

- `pokeapi_v2_reference.json`: every endpoint with its fields, types and example response (52 endpoints, 125 object types).
- `pokeapi_v2_endpoints.json`: just the endpoints and which other endpoints each one links to (a slimmer cut of the same data).
- `docs-source/`: the docs JSON from github.com/PokeAPI/pokeapi.co (`src/docs/*.json`) that the reference is built from.

Rebuild:

```bash
python3 build_reference.py docs-source pokeapi_v2_reference.json
python3 build_page.py pokeapi_v2_reference.json page_template.html reference_page.html   # the readable web page
```
