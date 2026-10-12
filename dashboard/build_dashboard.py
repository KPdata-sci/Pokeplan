"""Build the dashboard from dashboard_data.json.

  python3 build_dashboard.py [out.html]

Writes out.html (default pokedex_dashboard.html) and, next to it, a data/ folder
the page loads on demand, so the first load stays small:
  data/moves.json         every move, plus how moves changed between eras
  data/items.json         every item, what each TM teaches per game, wild held items
  data/games/<game>.json  one per game: its Pokédex, learnsets, TMs, where to catch
                          Pokémon and held items
  data/pokedex_text.json  every species' Pokédex text in every game
Publish the html with data/ and sprites.webp beside it.
"""
import json, pathlib, sys
from collections import defaultdict

here = pathlib.Path(__file__).parent
d = json.loads((here / "dashboard_data.json").read_text())
out = here / (sys.argv[1] if len(sys.argv) > 1 else "pokedex_dashboard.html")
data_dir = out.parent / "data"
(data_dir / "games").mkdir(parents=True, exist_ok=True)


def dump(obj):
    return json.dumps(obj, separators=(",", ":"), ensure_ascii=False)


def write(path, obj):
    path.write_text(dump(obj))
    return path.stat().st_size


# ---------- per-game files
games = d["games"]
METHODS = sorted({r[3] for r in d["learnset"]})
by_game = defaultdict(lambda: defaultdict(list))
for r in d["learnset"]:
    by_game[r[0]]["learn"].append([r[1], r[2], METHODS.index(r[3]), r[4]])
for r in d["machines"]:
    by_game[r[0]]["machines"].append([r[2], r[3], r[4], r[1]])
for r in d["game_pokedex"]:
    by_game[r[0]]["pokedex"].append(r[1:])
for r in d["encounters"]:
    by_game[r[0]]["enc"].append(r[1:])
for r in d["held_items"]:
    by_game[r[0]]["held"].append(r[1:])

sizes = {}
for g in games:
    code, b = g["game"], by_game[g["game"]]
    versions = g["versions"].split(",")
    names = [n.strip() for n in g["name"].split(" / ")]
    vnames = sorted({r[0] for k in ("enc", "held") for r in b[k]})
    places = sorted({r[1] for r in b["enc"]})
    methods = sorted({(r[5], r[6]) for r in b["enc"]})
    conds = sorted({r[7] or "" for r in b["enc"]})
    dexes = defaultdict(list)
    for name, dex_no, entry in b["pokedex"]:
        dexes[name].append([entry, dex_no])
    gf = {
        "game": code,
        "versions": vnames,
        "pokedex": [[name, rows] for name, rows in sorted(dexes.items())],
        # [dex_no, move_id, method index into D.learn_methods, level]
        "learn": b["learn"],
        # [kind, number, move_id, item_id]
        "machines": b["machines"],
        "places": places,
        "methods": [list(m) for m in methods],  # [name, chance unit]
        "conditions": conds,
        # [version index, place index, dex_no, form, method index, condition index, min level, max level, chance]
        "enc": [[vnames.index(r[0]), places.index(r[1]), r[3], r[4], methods.index((r[5], r[6])),
                 conds.index(r[7] or ""), r[8], r[9], r[10]] for r in b["enc"]],
        # [version index, dex_no, form, item_id, rarity %]
        "held": [[vnames.index(r[0])] + r[1:] for r in b["held"]],
    }
    sizes[code] = write(data_dir / "games" / f"{code}.json", gf)
    # small summary for the game list
    g["dex_count"] = len({r[1] for r in b["pokedex"]})
    g["move_count"] = len({r[1] for r in b["learn"]})
    g["machine_count"] = len(b["machines"])
    g["place_count"] = len(places)

wild = defaultdict(set)
for r in d["encounters"]:
    wild[r[4]].add(r[0])

# Pokédex text for every species across every game, with repeats folded:
# {dex_no: [[text, "Red, Blue"], ...]} in release order.
order = {g["game"]: g["sort_order"] for g in games}
texts = defaultdict(dict)
for game, version, dex_no, text in sorted(d["pokedex_text"], key=lambda r: (order.get(r[0], 0), r[1])):
    texts[dex_no].setdefault(text, []).append(version)
write(data_dir / "pokedex_text.json", {k: [[t, ", ".join(v)] for t, v in m.items()] for k, m in texts.items()})

write(data_dir / "moves.json", {"moves": d["moves"], "eras": d["move_eras"]})
write(data_dir / "items.json", {"items": d["items"], "machines": d["machines"], "held": d["held_items"]})

# ---------- the page
cols = ["dex_no", "name", "generation", "rarity", "type_1", "type_2", "hp", "attack", "defense",
        "special_attack", "special_defense", "speed", "base_stat_total",
        "genus", "height_m", "weight_kg", "evolution_chain_id", "capture_rate", "habitat"]
data = {
    "pokemon": [[p[c] for c in cols] for p in d["pokemon"]],
    "type_chart": d["type_chart"],
    "generations": d["generations"],
    "games": games,
    "run": d["run"],
    "mart_rows": d["mart_rows"],
    "abilities": d["abilities"],
    "evolutions": d["evolutions"],
    "learn_methods": METHODS,
    # {dex_no: [game codes where it can be caught in the wild]}, so "Where to find" only lists those
    "wild": {k: sorted(v, key=lambda c: order[c]) for k, v in wild.items()},
    # Sprite sheet layout written by build_sprites.py; the page shows no pictures without it.
    "sprites": json.loads((here / "sprites.json").read_text()) if (here / "sprites.json").exists() else None,
}
blob = dump(data).replace("</", "<\\/")
out.write_text((here / "dashboard_template.html").read_text().replace("{{DATA}}", blob))
print(out, len(blob), "bytes inline;", len(sizes), "game files, largest",
      max(sizes.items(), key=lambda kv: kv[1]))
