-- =====================================================================
-- Pokeplan :: Layer 1b — REFERENCE / SEED DATA (domain knowledge)
-- ---------------------------------------------------------------------
-- Pattern: "seed tables" (what dbt calls seeds). Some facts every Pokémon
-- player knows are not in the API at all: when abilities were introduced,
-- which games are remakes or DLC, which encounter methods are one-off
-- gifts. We write them down ONCE, as data, in the ref schema, and the
-- staging and load steps join to them. That keeps business rules out of
-- hard-coded CASE expressions scattered through the SQL, and makes every
-- rule reviewable in one place.
--
-- Sources: Bulbapedia (Generation, Type, Form, Methods of evolution, Item,
-- Wild Pokémon pages) and PokeAPI's own CSV source data, checked 2026-10-08.
-- See pokeapi/domain/pokemon_domain_notes.md for the reasoning.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS ref;

-- Grain: one row per generation. Release window and home platform.
CREATE TABLE IF NOT EXISTS ref.generation_info (
    generation_number   smallint PRIMARY KEY,
    roman               text     NOT NULL,
    first_release_year  smallint NOT NULL,
    last_release_year   smallint,
    platform            text     NOT NULL,
    new_species         smallint NOT NULL        -- check value: count of species introduced
);
TRUNCATE ref.generation_info;
INSERT INTO ref.generation_info VALUES
 (1, 'I',    1996, 1999, 'Game Boy',             151),
 (2, 'II',   1999, 2001, 'Game Boy Color',       100),
 (3, 'III',  2002, 2005, 'Game Boy Advance',     135),
 (4, 'IV',   2006, 2010, 'Nintendo DS',          107),
 (5, 'V',    2010, 2012, 'Nintendo DS',          156),
 (6, 'VI',   2013, 2014, 'Nintendo 3DS',          72),
 (7, 'VII',  2016, 2018, 'Nintendo 3DS / Switch', 88),
 (8, 'VIII', 2019, 2022, 'Nintendo Switch',       96),
 (9, 'IX',   2022, NULL, 'Nintendo Switch',      120);

-- Grain: one row per game mechanic that the data model depends on.
-- The load uses these to clamp history: e.g. nothing had an ability before
-- generation 3, so an ability row can never be valid from generation 1.
CREATE TABLE IF NOT EXISTS ref.mechanic (
    mechanic_code          text PRIMARY KEY,
    introduced_generation  smallint NOT NULL,
    retired_generation     smallint,             -- NULL = still in the games
    description            text NOT NULL
);
TRUNCATE ref.mechanic;
INSERT INTO ref.mechanic VALUES
 ('special-stat',          1, 1,    'One Special stat for both special attack and defence'),
 ('special-split',         2, NULL, 'Special split into Special Attack and Special Defense'),
 ('held-items',            2, NULL, 'Pokemon can hold an item'),
 ('breeding',              2, NULL, 'Eggs and egg moves'),
 ('dark-steel-types',      2, NULL, 'Dark and Steel types added'),
 ('abilities',             3, NULL, 'Every Pokemon has an ability'),
 ('natures',               3, NULL, 'Natures raise one stat and lower another'),
 ('physical-special-split',4, NULL, 'Each move is physical or special by itself; before this the move type decided'),
 ('hidden-abilities',      5, NULL, 'A third, hidden ability slot'),
 ('reusable-tms',          5, NULL, 'TMs are no longer used up'),
 ('fairy-type',            6, NULL, 'Fairy type added; Ghost and Dark no longer resisted by Steel'),
 ('mega-evolution',        6, 7,    'Temporary in-battle evolution with a Mega Stone (returns in Legends: Z-A)'),
 ('regional-forms',        7, NULL, 'Alolan, Galarian, Hisuian and Paldean variants'),
 ('z-moves',               7, 7,    'One-per-battle Z-Moves'),
 ('hms-removed',           7, NULL, 'Hidden Machines removed'),
 ('dynamax',               8, 8,    'Dynamax and Gigantamax'),
 ('technical-records',     8, 8,    'Single-use TRs alongside TMs'),
 ('terastal',              9, NULL, 'Terastallization changes a Pokemon''s type in battle');

-- Grain: one row per version group. PokeAPI knows the generation; it does
-- not know which games are remakes, DLC, spin-offs or Japan-only.
CREATE TABLE IF NOT EXISTS ref.version_group_info (
    version_group_code       text PRIMARY KEY,
    release_year             smallint NOT NULL,
    game_category            text NOT NULL CHECK (game_category IN
                             ('core', 'enhanced', 'remake', 'dlc', 'spin-off', 'japan-only')),
    base_version_group_code  text,               -- DLC and enhanced games point at their base game
    remake_of_generation     smallint            -- remakes: the generation of the original
);
TRUNCATE ref.version_group_info;
INSERT INTO ref.version_group_info VALUES
 ('red-green-japan',                 1996, 'japan-only', NULL,           NULL),
 ('blue-japan',                      1996, 'japan-only', NULL,           NULL),
 ('red-blue',                        1998, 'core',       NULL,           NULL),
 ('yellow',                          1998, 'enhanced',   'red-blue',     NULL),
 ('gold-silver',                     1999, 'core',       NULL,           NULL),
 ('crystal',                         2000, 'enhanced',   'gold-silver',  NULL),
 ('ruby-sapphire',                   2002, 'core',       NULL,           NULL),
 ('emerald',                         2004, 'enhanced',   'ruby-sapphire',NULL),
 ('colosseum',                       2003, 'spin-off',   NULL,           NULL),
 ('xd',                              2005, 'spin-off',   NULL,           NULL),
 ('firered-leafgreen',               2004, 'remake',     NULL,           1),
 ('diamond-pearl',                   2006, 'core',       NULL,           NULL),
 ('platinum',                        2008, 'enhanced',   'diamond-pearl',NULL),
 ('heartgold-soulsilver',            2009, 'remake',     NULL,           2),
 ('black-white',                     2010, 'core',       NULL,           NULL),
 ('black-2-white-2',                 2012, 'core',       NULL,           NULL),
 ('x-y',                             2013, 'core',       NULL,           NULL),
 ('omega-ruby-alpha-sapphire',       2014, 'remake',     NULL,           3),
 ('sun-moon',                        2016, 'core',       NULL,           NULL),
 ('ultra-sun-ultra-moon',            2017, 'enhanced',   'sun-moon',     NULL),
 ('lets-go-pikachu-lets-go-eevee',   2018, 'remake',     NULL,           1),
 ('sword-shield',                    2019, 'core',       NULL,           NULL),
 ('the-isle-of-armor',               2020, 'dlc',        'sword-shield', NULL),
 ('the-crown-tundra',                2020, 'dlc',        'sword-shield', NULL),
 ('brilliant-diamond-shining-pearl', 2021, 'remake',     NULL,           4),
 ('legends-arceus',                  2022, 'core',       NULL,           NULL),
 ('scarlet-violet',                  2022, 'core',       NULL,           NULL),
 ('the-teal-mask',                   2023, 'dlc',        'scarlet-violet', NULL),
 ('the-indigo-disk',                 2023, 'dlc',        'scarlet-violet', NULL),
 ('legends-za',                      2025, 'core',       NULL,           NULL),
 ('mega-dimension',                  2025, 'dlc',        'legends-za',   NULL),
 ('champions',                       2026, 'spin-off',   NULL,           NULL);

-- Grain: one row per type. The API mixes the 18 battle types with three
-- that never appear on a Pokémon's own typing in the main games.
CREATE TABLE IF NOT EXISTS ref.type_role (
    type_code  text PRIMARY KEY,
    type_role  text NOT NULL CHECK (type_role IN ('standard', 'tera-only', 'non-battle'))
);
TRUNCATE ref.type_role;
INSERT INTO ref.type_role VALUES
 ('stellar', 'tera-only'),     -- only reachable by Terastallizing (gen IX)
 ('unknown', 'non-battle'),    -- the ??? type (Curse, gens II-IV)
 ('shadow',  'non-battle');    -- Colosseum / XD Shadow moves
-- every other type is 'standard' (applied with COALESCE in the load)

-- Grain: one rule per form pattern, applied in priority order to a
-- Pokémon's code (first match wins). Regional variants get their region.
CREATE TABLE IF NOT EXISTS ref.form_rule (
    priority        smallint PRIMARY KEY,
    code_pattern    text NOT NULL,               -- POSIX regex on pokemon_code
    form_category   text NOT NULL,
    region_code     text
);
TRUNCATE ref.form_rule;
INSERT INTO ref.form_rule VALUES
 (10, '-mega(-[xyz])?$',  'mega',        NULL),
 (20, '-primal$',         'primal',      NULL),
 (30, '-gmax$',           'gigantamax',  NULL),
 (40, '-totem(-|$)',      'totem',       NULL),
 (50, '-alola(-|$)',      'regional',    'alola'),
 (51, '-galar(-|$)',      'regional',    'galar'),
 (52, '-hisui(-|$)',      'regional',    'hisui'),
 (53, '-paldea(-|$)',     'regional',    'paldea');
-- no match: 'default' when it is the species' default variety, else
-- 'battle-only' when the API flags the form so, else 'alternate'.

-- Grain: one rule per encounter-method pattern. Groups the 66 methods into
-- what they mean for analysis, and says what the encounter's 'chance'
-- number is, because it is not the same thing everywhere:
--   percent  classic encounter tables (grass, surfing, fishing): slot odds
--            that add up to 100 per area, game, method and conditions
--   weight   overworld spawns (Let's Go, Sword/Shield wanderers) and raids:
--            relative weights that can add up to far more than 100
--   n/a      gifts, static legendaries, trades, roamers: always "100"
CREATE TABLE IF NOT EXISTS ref.encounter_method_rule (
    priority          smallint PRIMARY KEY,
    code_pattern      text NOT NULL,             -- POSIX regex on method code
    method_group      text NOT NULL,
    chance_unit       text NOT NULL CHECK (chance_unit IN ('percent', 'weight', 'n/a'))
);
TRUNCATE ref.encounter_method_rule;
INSERT INTO ref.encounter_method_rule VALUES
 (10, '^(gift|gift-egg|static|npc-trade|snag|snag-rematch|pokeflute|devon-scope|squirt-bottle|wailmer-pail|island-scan|new-york-pokecenter-wish-eggs)$', 'one-off', 'n/a'),
 (11, '^(colosseum-|pokemon-channel|pokemon-ranger|pokemon-battle-revolution)', 'one-off', 'n/a'),
 (20, '^roaming-',                       'roaming',   'n/a'),
 (30, '(rod|fishing)',                   'fishing',   'percent'),
 (40, '^(surf|surf-spots|seaweed|bubbling-spots|sos-from-bubbling-spot)$', 'water', 'percent'),
 (50, '^(overworld|wanderer|chase-water)', 'overworld', 'weight'),
 (60, '^(max-raid|dynamax-adventure)$',  'raid',      'weight'),
 (99, '.*',                              'land',      'percent');

-- Grain: one row per stat that only existed for part of the timeline.
-- Generation I had a single Special stat; generation II split it in two.
-- Stats not listed here (hp, attack, defense, speed) exist in every generation.
CREATE TABLE IF NOT EXISTS ref.stat_validity (
    stat_code              text PRIMARY KEY,
    valid_from_generation  smallint NOT NULL,
    valid_to_generation    smallint NOT NULL       -- 99 = still current
);
TRUNCATE ref.stat_validity;
INSERT INTO ref.stat_validity VALUES
 ('special',         1, 1),
 ('special-attack',  2, 99),
 ('special-defense', 2, 99);
