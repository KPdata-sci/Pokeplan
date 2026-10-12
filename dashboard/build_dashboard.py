"""Inject dashboard_data.json into dashboard_template.html -> pokedex_dashboard.html."""
import json, pathlib, sys
here = pathlib.Path(__file__).parent
d = json.loads((here / "dashboard_data.json").read_text())
cols = ["dex_no", "name", "generation", "rarity", "type_1", "type_2", "hp", "attack", "defense",
        "special_attack", "special_defense", "speed", "base_stat_total"]
data = {
    "pokemon": [[p[c] for c in cols] for p in d["pokemon"]],
    "type_chart": d["type_chart"],
    "generations": d["generations"],
    "run": d["run"],
    "mart_rows": d["mart_rows"],
    # Sprite sheet layout written by build_sprites.py; the page shows no pictures without it.
    "sprites": json.loads((here / "sprites.json").read_text()) if (here / "sprites.json").exists() else None,
}
blob = json.dumps(data, separators=(",", ":"), ensure_ascii=False).replace("</", "<\\/")
out = here / (sys.argv[1] if len(sys.argv) > 1 else "pokedex_dashboard.html")
out.write_text((here / "dashboard_template.html").read_text().replace("{{DATA}}", blob))
print(out, len(blob))
