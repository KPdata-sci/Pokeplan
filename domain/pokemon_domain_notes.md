# Pokémon domain notes for the PokeAPI pipeline

Why this exists: PokeAPI describes its fields, not the games. To model the data well you need to know how the games work, because the same thing (a move, a Pokémon's stats, the type chart) means different things in different games. These notes collect what matters for the data model, with counts measured on the real data (PokeAPI CSV source and the `PokeAPI/api-data` JSON dump, both as of 2026-10-07).

Sources: Bulbapedia pages *Generation*, *Type*, *Type chart*, *Form*, *Methods of evolution*, *Wild Pokémon*, *Item*, *Pokémon world*; PokeAPI's CSV source (`github.com/PokeAPI/pokeapi`, `data/v2/csv`) and static JSON (`github.com/PokeAPI/api-data`). Counts below were computed from those files, not copied from a page.

## 1. The timeline: generations, games, versions

The series is organised in **generations**. Each brings new species, usually a new region, and new mechanics.

| Gen | Years | Main games (PokeAPI version groups) | New region | New species | Mechanics that matter for data |
|---|---|---|---|---|---|
| I | 1996–99 | Red/Green (JP), Blue (JP), Red/Blue, Yellow | Kanto | 151 | One "Special" stat; type chart bugs (Ghost can't hit Psychic) |
| II | 1999–2001 | Gold/Silver, Crystal | Johto | 100 | Dark and Steel types; held items; breeding; Special split in two; time of day |
| III | 2002–05 | Ruby/Sapphire, Emerald, FireRed/LeafGreen, Colosseum, XD | Hoenn | 135 | Abilities; natures |
| IV | 2006–10 | Diamond/Pearl, Platinum, HeartGold/SoulSilver | Sinnoh | 107 | **Physical/special split** |
| V | 2010–12 | Black/White, Black 2/White 2 | Unova | 156 | Hidden abilities; reusable TMs; seasons |
| VI | 2013–14 | X/Y, Omega Ruby/Alpha Sapphire | Kalos | 72 | Fairy type; Mega Evolution; big base-stat update |
| VII | 2016–18 | Sun/Moon, Ultra Sun/Ultra Moon, Let's Go | Alola | 88 | Regional forms; Z-Moves; HMs removed |
| VIII | 2019–22 | Sword/Shield (+ Isle of Armor, Crown Tundra), Brilliant Diamond/Shining Pearl, Legends: Arceus | Galar, Hisui | 96 | Dynamax/Gigantamax; TRs; overworld encounters |
| IX | 2022– | Scarlet/Violet (+ Teal Mask, Indigo Disk), Legends: Z-A (+ Mega Dimension), Champions | Paldea | 120 | Terastallization; Stellar type |

1,025 species in total. The per-generation counts above match `pokemon_species.generation` exactly, so they are now a test (`dbt/tests/domain_species_per_generation.sql`).

**Version vs version group.** Games come in pairs ("versions": Red and Blue) that share almost all data, so PokeAPI groups them into a **version group** (`red-blue`). Learnsets, machines and evolution rules hang off the version group; encounters and held items differ by version and hang off the version. There are 53 versions in 32 version groups.

**A version group's generation is when it was released, not where it is set.** HeartGold/SoulSilver are a gen IV remake of gen II and take place in Johto and Kanto. FireRed/LeafGreen (gen III), Let's Go (gen VII) and Brilliant Diamond/Shining Pearl (gen VIII) are also remakes. So "region" and "generation" are different dimensions, and one game can have two regions.

**Game categories the API doesn't record.** Core pairs, enhanced third versions (Yellow, Crystal, Emerald, Platinum, Ultra Sun/Moon), remakes, DLC (Isle of Armor, Crown Tundra, Teal Mask, Indigo Disk, Mega Dimension), spin-offs (Colosseum, XD, Champions) and Japan-only releases (Red/Green, Blue). These now live in `ref.version_group_info`.

**Version group `order` is a global timeline.** It runs 1 (Red/Green JP) to 32 (Champions) and never goes back a generation, so it is the right axis for "as of this game" history.

## 2. Species, Pokémon and forms

PokeAPI has three levels, and the games treat them differently:

| Level | Rows | What it is | Example |
|---|---|---|---|
| species | 1,025 | The Pokédex entry | Raichu |
| pokemon | 1,351 | A battle-relevant variety with its own stats, types, abilities, moves | raichu, raichu-alola |
| pokemon-form | 1,579 | Every visual form, including purely cosmetic ones | unown-a … unown-question |

The 326 non-default Pokémon, by kind (from the names and form flags):

| Kind | Count | Notes |
|---|---|---|
| Mega Evolution | 97 | Temporary, in battle only, needs a Mega Stone; gens VI–VII and Legends: Z-A |
| Regional form | 59 | Alolan 19, Galarian 20, Hisuian 16, Paldean 4 (Wooper and three Tauros breeds); a separate Pokémon with its own types and stats, introduced later than its species |
| Gigantamax | 34 | Sword/Shield only, met in Max Raids |
| Totem | 12 | Sun/Moon boss versions |
| Primal | 2 | Kyogre and Groudon |
| Other battle-only | 20 | Aegislash Blade, Darmanitan Zen, Wishiwashi School… |
| Other alternates | 102 | Rotom appliances, Therian formes, Deoxys formes, Koraidon builds, cap Pikachu… |

Cosmetic forms (Unown's 28 letters, Vivillon's 20 patterns, seasonal Deerling) are only `pokemon-form` rows: they share everything that matters in battle. 102 species also have visual gender differences, and a few (Meowstic, Indeedee, Basculegion, Oinkologne) have separate male/female Pokémon with different stats or abilities.

**Data consequence:** "how many Pokémon are there" has three answers (1,025 / 1,351 / 1,579). Any count needs a stated grain, and most analysis wants `form_category = 'default'`. A regional form must not inherit its species' generation: Alolan Raichu exists from gen VII.

Species flags: 71 legendary, 23 mythical, 19 baby. Ultra Beasts and Paradox Pokémon are lore categories with no flag in the API.

## 3. Types

18 battle types today. Dark and Steel arrived in gen II, Fairy in gen VI. The API also has three types no Pokémon has as its own typing: **Stellar** (gen IX, only reachable by Terastallizing), **???/unknown** (the move Curse in gens II–IV) and **Shadow** (Colosseum/XD). They must be excluded from the type chart.

So the type chart has 15 types in gen I, 17 in gens II–V and 18 from gen VI.

**Dual types multiply.** A defender with two types takes the product of both multipliers: 4×, 2×, 1×, ½×, ¼× or 0×. Never add them. (Legends: Arceus used 2.5× and 0.4× for the doubled cases; the API doesn't carry that.)

**The type chart changed twice** (Bulbapedia, *Type chart*), and PokeAPI records it in `past_damage_relations`:

| Attacker → defender | Gen I | From gen II |
|---|---|---|
| Bug → Poison | 2× | ½× |
| Poison → Bug | 2× | 1× |
| Ghost → Psychic | 0× (a bug) | 2× |
| Ice → Fire | 1× | ½× |

| Attacker → defender | Gens II–V | From gen VI |
|---|---|---|
| Ghost → Steel | ½× | 1× |
| Dark → Steel | ½× | 1× |

**The physical/special split (gen IV).** Before Diamond/Pearl, whether a damaging move was physical or special depended only on its *type*: Normal, Fighting, Flying, Poison, Ground, Rock, Bug, Ghost and Steel were physical; Fire, Water, Grass, Electric, Psychic, Ice, Dragon and Dark were special. So Fire Punch was special and every Dark move (including Bite and Crunch) was special in gens II–III. From gen IV each move has its own class. The API only stores today's class per move, plus each type's old class in `type.move_damage_class`, so the gen I–III answer has to be derived.

## 4. Pokémon attributes that change over time

PokeAPI records history in four different shapes, and each needs its own treatment:

| Field | What it lists | Keyed by | Rows |
|---|---|---|---|
| `pokemon.past_types` | the whole old typing | generation, valid up to and including it | 36 (29 Pokémon, mostly the gen VI Fairy retypes and gen V Rotom forms) |
| `pokemon.past_stats` | only the stats that changed | generation, up to and including | 235 across 200 Pokémon |
| `pokemon.past_abilities` | only the slots that changed; `ability: null` means the slot didn't exist | generation, up to and including | 569 |
| `move.past_values` | only the fields that changed | version group, valid **before** it | 198 changes |

**Stats.** Gen I had five stats with a single *Special*; gen II split it into Special Attack and Special Defense. The gen I Special appears only in `past_stats` (151 rows, one per gen I Pokémon). Gen VI raised the base stats of many older Pokémon (Pikachu: Defense 30→40, Sp. Def 40→50). Base Stat Total is the sum of the six stats *of one era*.

**Abilities** start in gen III; the third, hidden slot in gen V. Some Pokémon swapped abilities later (Gengar: Levitate until gen VI, Cursed Body from gen VII). The API's past entries don't stop an ability row from claiming to be valid in gen I, so the model clamps it.

**Moves.** 937 moves. Power, accuracy, PP, type and effect chance changed across games: 198 recorded changes, 83 of them in X/Y. Important: the API docs say `past_values.version_group` is "the version group in which these values were in effect", but the data shows the opposite. Bite lists `{type: normal, version_group: gold-silver}`; Bite was Normal in Red/Blue and became Dark in Gold/Silver. So the listed values are the old ones, valid until that version group. A domain fact settled a documentation ambiguity.

## 5. Learnsets and machines

638,321 learnset rows: one per Pokémon × move × version group × learn method × level. Methods: level-up (162k), machine (372k), tutor (50k), egg (35k), and game-specific ones (Colosseum/XD purification and shadow moves, Pokémon Champions' "train", form-change, Zygarde Cube…).

- **A Pokémon can learn one move at several levels** in the same game. Smeargle learns Sketch at levels 1, 11, 21 … 91. So level is part of the grain (the v1 key was wrong).
- **Level 0** on a level-up row means "learned on evolving" from Sun/Moon onwards (1,092 rows).
- **DLC learnsets are folded into the base game:** there are no rows for Isle of Armor, Crown Tundra, Teal Mask or Indigo Disk, and none for Legends: Z-A yet.
- **Machines:** TMs, HMs and TRs are items, and which move an item teaches depends on the game. TM26 is Earthquake in 20 version groups, then Poison Jab (Let's Go), Scary Face (Sword/Shield), Poison Tail (Scarlet/Violet) and Energy Ball (Legends: Z-A). 2,372 machine rows: 2,142 TM, 130 HM, 100 TR. TMs were single-use until gen V, HMs were removed in gen VII, TRs existed only in gen VIII, and gen IX crafts TMs from materials.

## 6. Items

2,223 items. By pocket: misc 1,204, key items 391, machines 338, medicine 106, berries 74, Poké Balls 38, battle items 36, mail 36. Held items started in gen II. Items matter to the model in four places: wild held items (rarity per version), evolution (use-item and held-item triggers), Mega Stones (form triggers), and machines.

## 7. Evolution

540 evolution chains, 676 evolution conditions, 18 triggers (level-up, trade, use-item, shed, spin, three-critical-hits, agile/strong-style move, recoil damage, gimmighoul coins…).

- **Chains are trees.** Eevee has eight branches; Tyrogue picks a branch by comparing Attack and Defense.
- **Conditions combine:** level + time of day, level + held item at night (Sneasel), level while knowing a move, trade while holding an item, trade for a specific species (Karrablast ↔ Shelmet), party member (Pancham needs a Dark type), rain (Sliggoo), turning the console upside down (Inkay), 1,000 steps (Let's Go! evolutions), using a move 20 times (Legends: Arceus styles).
- **Rules change by game.** Gen IV introduced location evolutions (Magnezone at Mt. Coronet, Leafeon at a Moss Rock); Sword/Shield replaced several with stones. The API has one row per rule with the version group it was introduced in.
- **Regional evolutions depend on region and form.** Pikachu becomes Alolan Raichu with a Thunder Stone only in Alola; Exeggcute becomes Alolan Exeggutor there. The API's evolution chain is species-level, so `region`, `required_pokemon_form` and `evolved_pokemon_form` are what tell the variants apart.

## 8. Wild encounters

117,127 encounter rows across 66 methods and 30 condition types (~360 condition values).

- **Classic encounter tables** (gens I–VII): each area has fixed slots with fixed odds, for example 12 grass slots at 20/20/10/10/10/10/5/5/4/4/1/1 %. One Pokémon can fill several slots, so two identical rows are both real.
- **Conditions** pick which table applies: time of day (gen II+), seasons (gen V), swarms, Poké Radar, GBA cartridge in slot 2 (gen IV), radio, weather (Sword/Shield), story progress.
- **The "chance" field means different things.** In classic tables it is a percentage that adds up to 100. For overworld spawns (Let's Go, Sword/Shield wanderers) and raids it behaves like a relative weight: sums reach 1,100 and more. For gifts, static legendaries and trades it is always 100 and per Pokémon.
- **Hordes and SOS** (gens VI–VII) and some Sun/Moon, X/Y, HGSS tables add up to more than 100 even as percentages, because day/night tables or horde members aren't tagged separately.
- **Coverage stops at Sword/Shield.** PokeAPI has no encounter data for Brilliant Diamond/Shining Pearl, Legends: Arceus, Scarlet/Violet or later. Gigantamax Pokémon do appear, but only in Max Raids.

## 9. Pokédexes

35 Pokédexes: the National Dex plus regional ones, often several per game (Kalos Central/Coastal/Mountain; Alola's island dexes; Sword/Shield's Galar, Isle of Armor and Crown Tundra). A species has a different number in each (Pikachu: #25 national, #74 Paldea). The regional dex is how a game decides which Pokémon are "in" it. That has mattered more since Sword/Shield, when games stopped including every Pokémon.

## 10. Lore (for context)

- **Regions are modelled on real places:** Kanto, Johto, Hoenn and Sinnoh on parts of Japan; Unova on New York; Kalos on northern France; Alola on Hawaii; Galar on the UK; Paldea on the Iberian Peninsula. Kanto and Johto are the only regions known to border each other. Hisui is Sinnoh in an earlier era (Legends: Arceus), and Orre is the Colosseum/XD region based on Arizona.
- **Creation myth:** Arceus created the creation trio (Dialga: time, Palkia: space, Giratina: banished to the Distortion World) and the lake guardians (Uxie, Mesprit, Azelf). Mew is said to carry the DNA of every Pokémon.
- **Professors and the Pokédex:** each region has a professor who catalogues its Pokémon; Professor Oak made the first Pokédex of 151 Kanto Pokémon. The National Dex now lists 1,025.
- **Legendary and Mythical Pokémon** are one-of-a-kind story Pokémon (usually caught once, from a static encounter); Mythicals are normally event-only. They generally cannot breed.
- **The Pokémon League:** players collect eight gym badges, then face the Elite Four and the Champion. Gym leaders specialise in one type, which is why type matchups dominate play.

## 11. What this changes in the data model

| Domain fact | Model change (schema v2) |
|---|---|
| Moves changed between games, and the physical/special split | `dim_move` is SCD type 2 on version-group order, with `effective_damage_class`; facts point at the era live in their game |
| Stats, abilities and types have generation history in partial shapes | `fact_pokemon_stat`, `fact_pokemon_ability`, `fact_pokemon_type` are all generation-dated; eras are clamped to when the mechanic and the Pokémon existed |
| A Pokémon can learn one move at several levels | `level_learned_at` is part of `fact_pokemon_move`'s key |
| Three meanings of "a Pokémon" | `dim_pokemon.form_category`, `introduced_generation`, `cosmetic_form_count` |
| Games are remakes, DLC, spin-offs; can span two regions | `ref.version_group_info`; `bridge_version_group_region` |
| Regional dexes scope a game | `dim_pokedex`, `fact_pokedex_entry`, `bridge_version_group_pokedex` |
| TM numbers mean different moves per game | `fact_machine` |
| Encounter "chance" has three meanings | `dim_encounter_method.method_group` and `chance_unit` |
| Stellar, ??? and Shadow aren't battle types | `dim_type.type_role`; type chart is 15/17/18 types |
| Regional and form-specific evolutions | `fact_evolution.from_pokemon_key`, `to_pokemon_key`, `region_code` |
| Coverage stops at Sword/Shield | `dim_version_group.has_encounter_data`, `has_learnset_data` |
| Everything above can be checked by a player | domain tests in `dbt/tests/domain_*.sql` |
