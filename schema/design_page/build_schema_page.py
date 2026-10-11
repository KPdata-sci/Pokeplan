# Builds the "Pokeplan Star Schema" design page (artifact PG1jbLypmwWsE339gdRm3E)
# from the FACTS / DIMS lists below. Usage: python3 build_schema_page.py out.html
import html, math, sys

E = html.escape

FACTS = [
 dict(name="fact_pokemon_move", q="Which moves can a Pokémon learn, in which game, and how?",
      grain="one Pokémon learning one move, in one game, by one method, at one level",
      dims=[("dim_pokemon", ""), ("dim_move", "the move as it was in that game"), ("dim_version_group", "the game"), ("dim_learn_method", "level-up, TM, egg…")],
      cols=["pokemon", "move", "game", "method", "level"],
      rows=[["smeargle", "sketch", "scarlet-violet", "level-up", "1"], ["smeargle", "sketch", "scarlet-violet", "level-up", "11"], ["pikachu", "thunderbolt", "scarlet-violet", "machine", "0"]],
      why="Level is part of the grain: Smeargle learns Sketch at levels 1, 11, 21 … 91 in the same game. The first version of this table left level out, and the real data broke its key."),
 dict(name="fact_encounter", q="Where can I catch a Pokémon, and how likely is it?",
      grain="one wild encounter slot: one Pokémon, in one area, in one game",
      dims=[("dim_pokemon", ""), ("dim_location_area", "where"), ("dim_version", "the game"), ("dim_encounter_method", "walk, surf, gift, raid…"), ("dim_encounter_condition_set", "night, winter, rain…")],
      cols=["area", "pokemon", "game", "method", "levels", "chance"],
      rows=[["canalave-city-area", "tentacool", "diamond", "surf", "20–30", "60%"], ["canalave-city-area", "tentacool", "diamond", "surf", "20–30", "30%"]],
      why="An area can hold two slots for the same Pokémon, so each row keeps its slot number. 'Chance' is a percentage only for classic encounter tables; overworld spawns use weights and gifts are always 100. There is no data after Sword/Shield."),
 dict(name="fact_evolution", q="What does a Pokémon evolve into, and what does it need?",
      grain="one rule by which a species can evolve into the next",
      dims=[("dim_species", "from, to, trade or party partner"), ("dim_pokemon", "the exact variety, from and to"), ("dim_evolution_trigger", "level-up, trade…"), ("dim_item", "item used or held"), ("dim_version_group", "game the rule arrived"), ("dim_move", "move known or used"), ("dim_type", "move or party type")],
      cols=["from", "becomes", "trigger", "needs", "region"],
      rows=[["pikachu", "raichu", "use-item", "thunder-stone", ""], ["pikachu", "raichu-alola", "use-item", "thunder-stone", "alola"]],
      why="Evolution chains are per species, but the games evolve varieties: in Alola a Thunder Stone gives Alolan Raichu. Several dimensions are used twice in different roles (from/to species, used/held item)."),
 dict(name="fact_type_effectiveness", q="How much damage does one type do to another?",
      grain="one attacking type against one defending type, in one generation",
      dims=[("dim_type", "attacker, defender"), ("dim_generation", "")],
      cols=["attacking", "defending", "generation", "multiplier"],
      rows=[["ghost", "psychic", "1", "0×"], ["ghost", "psychic", "2", "2×"], ["ghost", "steel", "5", "0.5×"], ["ghost", "steel", "6", "1×"]],
      why="The chart changed in gen II and gen VI. The API lists only matchups that aren't 1×, so the load adds the 1× rows: 15 types in gen I, 17 in II–V, 18 from VI (2,677 rows). Stellar is left out because no Pokémon has it as its own type. Multipliers are multiplied, never added."),
 dict(name="fact_pokemon_type", q="What type was a Pokémon in a given generation?",
      grain="one of a Pokémon's types, for the generations it had that type",
      dims=[("dim_pokemon", ""), ("dim_type", "")],
      cols=["pokemon", "slot", "from gen", "to gen", "type"],
      rows=[["clefairy", "1", "1", "5", "normal"], ["clefairy", "1", "6", "current", "fairy"], ["raichu-alola", "2", "7", "current", "psychic"]],
      why="Clefairy became Fairy in generation 6, so it gets one row per period. No row starts before the variety existed: Alolan Raichu starts in gen 7."),
 dict(name="fact_pokemon_stat", q="What were a Pokémon's base stats in a given generation?",
      grain="one Pokémon and one stat, for the generations it had that value",
      dims=[("dim_pokemon", ""), ("dim_stat", "hp, attack… and gen I's Special")],
      cols=["pokemon", "stat", "from gen", "to gen", "value"],
      rows=[["pikachu", "special", "1", "1", "50"], ["pikachu", "defense", "1", "5", "30"], ["pikachu", "defense", "6", "current", "40"]],
      why="Gen I had a single Special stat, and gen VI raised many base stats. Adding up one era's six rows gives the base stat total for that era."),
 dict(name="fact_pokemon_ability", q="Which abilities could a Pokémon have, and since when?",
      grain="one ability slot of one Pokémon, for the generations it held that ability",
      dims=[("dim_pokemon", ""), ("dim_ability", "")],
      cols=["pokemon", "slot", "from gen", "to gen", "ability", "hidden?"],
      rows=[["gengar", "1", "3", "6", "levitate", "no"], ["gengar", "1", "7", "current", "cursed-body", "no"], ["pikachu", "3", "5", "current", "lightning-rod", "yes"]],
      why="Abilities start in gen III and hidden abilities in gen V, so no row starts earlier. There are no numbers to add up here: the row records that the link existed."),
 dict(name="fact_pokemon_held_item", q="What items do wild Pokémon carry?",
      grain="one Pokémon holding one item, in one game",
      dims=[("dim_pokemon", ""), ("dim_item", ""), ("dim_version", "the game")],
      cols=["pokemon", "item", "game", "chance %"],
      rows=[["chansey", "lucky-egg", "heartgold", "5"], ["chansey", "lucky-egg", "soulsilver", "5"]],
      why="The same Pokémon and item appear once per game, because the chance can differ between games."),
 dict(name="fact_pokedex_entry", q="Which Pokémon are in a game's Pokédex, and in what order?",
      grain="one species listed in one Pokédex",
      dims=[("dim_species", ""), ("dim_pokedex", "national, kanto, paldea…")],
      cols=["species", "pokédex", "number"],
      rows=[["pikachu", "national", "25"], ["pikachu", "paldea", "74"]],
      why="Each game uses one or more regional Pokédexes (a bridge table links games to dexes). Since Sword/Shield that is how a game decides which Pokémon are in it."),
 dict(name="fact_machine", q="Which move does a TM teach in a given game?",
      grain="one TM, HM or TR in one game",
      dims=[("dim_item", "tm26…"), ("dim_version_group", "the game"), ("dim_move", "the move taught")],
      cols=["machine", "game", "move"],
      rows=[["tm26", "red-blue", "earthquake"], ["tm26", "sword-shield", "scary-face"], ["tm26", "scarlet-violet", "poison-tail"]],
      why="The same item teaches different moves in different games. TM26 was Earthquake in 20 games, then four different moves."),
]

DIMS = [
 ("dim_pokemon", "One battle variety of a species (raichu and raichu-alola are two rows)", "form category, generation it appeared, species, legendary, current types"),
 ("dim_species", "One Pokédex entry", "generation, legendary/mythical/baby, capture rate, growth rate"),
 ("dim_move", "One move in one era (it changes when the games change it)", "type, effective physical/special, power, accuracy, PP, valid games"),
 ("dim_type", "One type (fire, water…)", "generation added, role (standard / Tera only / not in battle)"),
 ("dim_stat", "One stat (hp, attack…)", "generations it existed (Special: gen I only)"),
 ("dim_ability", "One ability", "short effect, generation"),
 ("dim_item", "One item", "category, cost, holdable, TM/HM/TR"),
 ("dim_version", "One game version (red, blue…)", "game pair, generation, category, year"),
 ("dim_version_group", "One game release (red-blue…)", "generation, year, core/remake/DLC/spin-off, regions, which data exists for it"),
 ("dim_generation", "One generation (I to IX)", "years, platform, new region, mechanics introduced"),
 ("dim_pokedex", "One Pokédex (national, paldea…)", "region"),
 ("dim_location_area", "One area of a location", "location, region"),
 ("dim_learn_method", "One way to learn a move", "level-up, machine, egg, tutor"),
 ("dim_encounter_method", "One way to find a wild Pokémon", "group (land, water, fishing, overworld, raid, gift), what 'chance' means"),
 ("dim_encounter_condition_set", "One combination of conditions", "time, season, weather, swarm, story progress"),
 ("dim_evolution_trigger", "One kind of evolution trigger", "level-up, trade, use item, spin…"),
]

CHANGES = [
 ("Moves keep their history", "A move's type, power and accuracy changed between games, and before generation IV a move's type decided whether it was physical or special. Each move now has one row per era, and a learnset row points at the move as it was in that game. Bite is Normal and physical in Red/Blue, Dark and special in Gold/Silver, Dark and physical from Diamond/Pearl."),
 ("Stats, abilities and types are dated by generation", "Before, only types were. No row starts before the rule existed (no abilities before gen III) or before the Pokémon did."),
 ("Pokémon are sorted by kind", "Each variety is tagged default, regional, mega, Gigantamax, battle-only, and so on, so a count can say what it counts."),
 ("Learnsets include the level", "A Pokémon can learn one move at several levels in the same game."),
 ("Two new fact tables", "Pokédex entries, and which move each TM teaches in each game."),
 ("Games are described", "Release year; core, remake, DLC or spin-off; the regions each game covers; and whether PokeAPI has learnset and encounter data for it."),
 ("Domain tests", "The tests now check things a player could confirm: the gen I type chart, Clefairy becoming Fairy, TM26, 151 species in gen I. All pass on the full real dataset."),
]


def star_svg(fact, dims):
    W = 820
    boxw, boxh = 236, 50
    fw = max(190, 13 * len(fact) + 40)
    n = len(dims)
    if n <= 2:
        H, cx, cy = 110, W / 2, 55
        pos = [(W - 4 - boxw / 2, cy), (4 + boxw / 2, cy)][:n]
    else:
        rx, ry = 285, 150 if n <= 5 else 175
        H = int(2 * ry + 110)
        cx, cy = W / 2, H / 2
        pos = []
        for i in range(n):
            a = -math.pi / 2 + 2 * math.pi * i / n
            x = cx + rx * math.cos(a)
            y = cy + ry * math.sin(a)
            x = min(max(x, 4 + boxw / 2), W - 4 - boxw / 2)
            pos.append((x, y))
    out = [f'<svg viewBox="0 0 {W} {H}" role="img" aria-label="{E(fact)} joins to {E(", ".join(d for d, _ in dims))}">']
    for x, y in pos:
        out.append(f'<line x1="{cx:.0f}" y1="{cy:.0f}" x2="{x:.0f}" y2="{y:.0f}" class="ln"/>')
    for (d, sub), (x, y) in zip(dims, pos):
        out.append(f'<rect x="{x - boxw / 2:.0f}" y="{y - boxh / 2:.0f}" width="{boxw}" height="{boxh}" rx="6" class="db"/>')
        if sub:
            out.append(f'<text x="{x:.0f}" y="{y - 3:.0f}" class="dt">{E(d)}</text>')
            out.append(f'<text x="{x:.0f}" y="{y + 16:.0f}" class="dr">{E(sub)}</text>')
        else:
            out.append(f'<text x="{x:.0f}" y="{y + 5:.0f}" class="dt">{E(d)}</text>')
    out.append(f'<rect x="{cx - fw / 2:.0f}" y="{cy - 30:.0f}" width="{fw}" height="60" rx="6" class="fb"/>')
    out.append(f'<text x="{cx:.0f}" y="{cy + 6:.0f}" class="ft">{E(fact)}</text>')
    out.append("</svg>")
    return "\n".join(out)


def table(cols, rows):
    h = "".join(f"<th>{E(c)}</th>" for c in cols)
    b = "".join("<tr>" + "".join(f"<td>{E(c)}</td>" for c in r) + "</tr>" for r in rows)
    return f'<div class="scroll"><table><thead><tr>{h}</tr></thead><tbody>{b}</tbody></table></div>'


def build(tpl):
    glance = "".join(f'<tr><td><a href="#{f["name"]}" class="fn">{f["name"]}</a></td><td>{E(f["grain"])}</td></tr>' for f in FACTS)
    cards = []
    for f in FACTS:
        cards.append(f'''
<article class="fact" id="{f["name"]}">
  <div class="fhead"><h3>{f["name"]}</h3><p class="q">{E(f["q"])}</p></div>
  <p class="grain"><span class="tag">Grain</span>One row = {E(f["grain"])}.</p>
  <div class="diagram">{star_svg(f["name"], f["dims"])}</div>
  <div class="example"><p class="cap">Example rows</p>{table(f["cols"], f["rows"])}
    <p class="why">{E(f["why"])}</p></div>
</article>''')
    dims = "".join(f'<tr><td class="dn">{d}</td><td>{E(a)}</td><td>{E(b)}</td></tr>' for d, a, b in DIMS)
    changes = "".join(f"<li><b>{E(t)}.</b> {E(d)}</li>" for t, d in CHANGES)
    return (tpl.replace("__NFACT__", str(len(FACTS))).replace("__NDIM__", str(len(DIMS)))
               .replace("__GLANCE__", glance).replace("__CARDS__", "".join(cards))
               .replace("__DIMS__", dims).replace("__CHANGES__", changes))


if __name__ == "__main__":
    import os
    here = os.path.dirname(os.path.abspath(__file__))
    tpl = open(os.path.join(here, "schema_page_template.html")).read()
    open(sys.argv[1], "w").write(build(tpl))
