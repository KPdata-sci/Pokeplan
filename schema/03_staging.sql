-- =====================================================================
-- Pokeplan :: Layer 2 — STAGING (a.k.a. silver)
-- ---------------------------------------------------------------------
-- Pattern: one view per *grain*, not one view per endpoint. Each view
-- flattens one nested JSON list into rows, renames fields to snake_case
-- columns, parses URL -> integer id, and picks the English name.
-- No surrogate keys: those belong to the mart layer.
--
-- Every view states its grain in a comment. If a view ever returns two
-- rows for the same grain columns, the grain is wrong (see 06_tests.sql).
--
-- v2 (domain refactor): the games change over time, and the API records
-- that history in four different "past_*" shapes. Staging turns each one
-- into ERAS: rows with a valid_from / valid_to range.
--   past_types              full replacement, keyed by generation
--   past_stats              partial (only the stats that changed), by generation
--   past_abilities          partial (only the slots that changed), by generation
--   move.past_values        partial (only the fields that changed), by VERSION GROUP,
--                           and listing the values from BEFORE that version group
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS stg;

-- Small helper: English display name from a list<Name>.
CREATE OR REPLACE FUNCTION stg.en_name(names jsonb)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
    SELECT n->>'name'
    FROM jsonb_array_elements(COALESCE(names, '[]'::jsonb)) n
    WHERE n->'language'->>'name' = 'en'
    LIMIT 1
$$;

-- ---------------------------------------------------------------- dims

-- Grain: one row per generation.
CREATE OR REPLACE VIEW stg.generation AS
SELECT resource_id                                AS generation_id,
       payload->>'name'                           AS generation_code,
       stg.en_name(payload->'names')              AS generation_name,
       raw.url_id(payload->'main_region'->>'url') AS main_region_id,
       payload->'main_region'->>'name'            AS main_region_code
FROM raw.current_response WHERE endpoint = 'generation';

-- Grain: one row per version group (e.g. red-blue, sun-moon).
-- sort_order is a global release order across ALL generations, so it is
-- the timeline that move history is measured on.
CREATE OR REPLACE VIEW stg.version_group AS
SELECT resource_id                               AS version_group_id,
       payload->>'name'                          AS version_group_code,
       (payload->>'order')::int                  AS sort_order,
       raw.url_id(payload->'generation'->>'url') AS generation_id
FROM raw.current_response WHERE endpoint = 'version-group';

-- Grain: version group x region. Usually one region per game, but
-- HeartGold/SoulSilver visit Johto AND Kanto, so this is many-to-many.
CREATE OR REPLACE VIEW stg.version_group_region AS
SELECT vg.resource_id                AS version_group_id,
       raw.url_id(r->>'url')         AS region_id,
       r->>'name'                    AS region_code
FROM raw.current_response vg
CROSS JOIN LATERAL jsonb_array_elements(vg.payload->'regions') r
WHERE vg.endpoint = 'version-group';

-- Grain: version group x pokedex (which regional dexes a game uses).
CREATE OR REPLACE VIEW stg.version_group_pokedex AS
SELECT vg.resource_id                AS version_group_id,
       raw.url_id(d->>'url')         AS pokedex_id
FROM raw.current_response vg
CROSS JOIN LATERAL jsonb_array_elements(vg.payload->'pokedexes') d
WHERE vg.endpoint = 'version-group';

-- Grain: one row per version (e.g. red, blue).
CREATE OR REPLACE VIEW stg.version AS
SELECT resource_id                                  AS version_id,
       payload->>'name'                             AS version_code,
       stg.en_name(payload->'names')                AS version_name,
       raw.url_id(payload->'version_group'->>'url') AS version_group_id
FROM raw.current_response WHERE endpoint = 'version';

-- Grain: one row per pokedex (national, kanto, paldea, ...).
CREATE OR REPLACE VIEW stg.pokedex AS
SELECT resource_id                             AS pokedex_id,
       payload->>'name'                        AS pokedex_code,
       stg.en_name(payload->'names')           AS pokedex_name,
       payload->'region'->>'name'              AS region_code,
       (payload->>'is_main_series')::boolean   AS is_main_series
FROM raw.current_response WHERE endpoint = 'pokedex';

-- Grain: one row per type. damage_class is the class that ALL damaging
-- moves of this type had before the physical/special split (gens I-III).
CREATE OR REPLACE VIEW stg.type AS
SELECT resource_id                                      AS type_id,
       payload->>'name'                                 AS type_code,
       stg.en_name(payload->'names')                    AS type_name,
       raw.url_id(payload->'generation'->>'url')        AS generation_id,
       payload->'move_damage_class'->>'name'            AS damage_class
FROM raw.current_response WHERE endpoint = 'type';

-- Grain: one row per stat (hp, attack, ... plus accuracy/evasion and the
-- generation-I-only 'special').
CREATE OR REPLACE VIEW stg.stat AS
SELECT resource_id                           AS stat_id,
       payload->>'name'                      AS stat_code,
       stg.en_name(payload->'names')         AS stat_name,
       (payload->>'is_battle_only')::boolean AS is_battle_only,
       (payload->>'game_index')::int         AS game_index
FROM raw.current_response WHERE endpoint = 'stat';

-- Grain: one row per ability.
CREATE OR REPLACE VIEW stg.ability AS
SELECT resource_id                                AS ability_id,
       payload->>'name'                           AS ability_code,
       stg.en_name(payload->'names')              AS ability_name,
       (payload->>'is_main_series')::boolean      AS is_main_series,
       raw.url_id(payload->'generation'->>'url')  AS generation_id,
       (SELECT e->>'short_effect'
          FROM jsonb_array_elements(payload->'effect_entries') e
         WHERE e->'language'->>'name' = 'en' LIMIT 1) AS short_effect
FROM raw.current_response WHERE endpoint = 'ability';

-- Grain: one row per move, CURRENT values.
CREATE OR REPLACE VIEW stg.move AS
SELECT resource_id                                AS move_id,
       payload->>'name'                           AS move_code,
       stg.en_name(payload->'names')              AS move_name,
       raw.url_id(payload->'type'->>'url')        AS type_id,
       payload->'damage_class'->>'name'           AS damage_class,
       (payload->>'power')::int                   AS power,
       (payload->>'accuracy')::int                AS accuracy,
       (payload->>'pp')::int                      AS pp,
       (payload->>'priority')::int                AS priority,
       (payload->>'effect_chance')::int           AS effect_chance,
       payload->'target'->>'name'                 AS target,
       payload->'meta'->'ailment'->>'name'        AS ailment,
       payload->'meta'->'category'->>'name'       AS move_category,
       raw.url_id(payload->'generation'->>'url')  AS generation_id
FROM raw.current_response WHERE endpoint = 'move';

-- Grain: move x version group in which some of its values CHANGED.
-- Domain check: Bite lists {type: normal, version_group: gold-silver}.
-- Bite was Normal in Red/Blue and became Dark in Gold/Silver, so the
-- values are the OLD ones, valid up to (not including) that version group.
-- The API docs describe this field the other way round; the games settle it.
CREATE OR REPLACE VIEW stg.move_change AS
SELECT m.resource_id                               AS move_id,
       raw.url_id(pv->'version_group'->>'url')     AS changed_in_version_group_id,
       raw.url_id(pv->'type'->>'url')              AS old_type_id,
       (pv->>'power')::int                         AS old_power,
       (pv->>'accuracy')::int                      AS old_accuracy,
       (pv->>'pp')::int                            AS old_pp,
       (pv->>'effect_chance')::int                 AS old_effect_chance
FROM raw.current_response m
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(m.payload->'past_values', '[]')) pv
WHERE m.endpoint = 'move';

-- Grain: move x era. An era is a range of version groups (by sort_order)
-- in which the move behaved the same. Eras break wherever the move's values
-- changed, and also at the first generation-IV game for moves older than
-- that, because the physical/special split changed every damaging move's
-- class there without the API recording it as a change.
-- past_values only lists the fields that changed, so each field is
-- rebuilt as "the first recorded old value at or after this era, else the
-- current value".
CREATE OR REPLACE VIEW stg.move_era AS
WITH vg AS (
    SELECT version_group_id, sort_order, generation_id FROM stg.version_group
), chg AS (
    SELECT c.*, vg.sort_order AS change_order
    FROM stg.move_change c JOIN vg ON vg.version_group_id = c.changed_in_version_group_id
), split AS (
    SELECT min(vg.sort_order) AS split_order
    FROM vg JOIN ref.mechanic mc ON mc.mechanic_code = 'physical-special-split'
    WHERE vg.generation_id = mc.introduced_generation
), breaks AS (
    SELECT move_id, change_order AS brk FROM chg
    UNION
    SELECT m.move_id, s.split_order FROM stg.move m CROSS JOIN split s
    WHERE m.generation_id < (SELECT introduced_generation FROM ref.mechanic
                              WHERE mechanic_code = 'physical-special-split')
), eras AS (
    SELECT move_id,
           COALESCE(lag(brk) OVER (PARTITION BY move_id ORDER BY brk), 0) AS valid_from_order,
           brk - 1                                                          AS valid_to_order
    FROM breaks
    UNION ALL
    SELECT m.move_id, COALESCE(max(b.brk), 0), 9999
    FROM stg.move m LEFT JOIN breaks b USING (move_id)
    GROUP BY m.move_id
)
SELECT e.move_id, e.valid_from_order, e.valid_to_order,
       (e.valid_to_order = 9999) AS is_current,
       COALESCE((SELECT vg.generation_id FROM vg WHERE vg.sort_order >= e.valid_from_order
                  ORDER BY vg.sort_order LIMIT 1), 1)                   AS era_generation_id,
       COALESCE((SELECT c.old_type_id FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_type_id IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.type_id)          AS type_id,
       COALESCE((SELECT c.old_power FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_power IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.power)            AS power,
       COALESCE((SELECT c.old_accuracy FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_accuracy IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.accuracy)         AS accuracy,
       COALESCE((SELECT c.old_pp FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_pp IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.pp)               AS pp,
       COALESCE((SELECT c.old_effect_chance FROM chg c WHERE c.move_id = e.move_id
                    AND c.change_order > e.valid_to_order AND c.old_effect_chance IS NOT NULL
                  ORDER BY c.change_order LIMIT 1), m.effect_chance)    AS effect_chance
FROM eras e
JOIN stg.move m USING (move_id);

-- Grain: one row per machine = one TM/HM/TR item in one version group.
-- The same item teaches different moves in different games
-- (TM26 is Earthquake in Red/Blue, Scary Face in Sword/Shield).
CREATE OR REPLACE VIEW stg.machine AS
SELECT resource_id                                  AS machine_id,
       raw.url_id(payload->'item'->>'url')          AS item_id,
       payload->'item'->>'name'                     AS item_code,
       raw.url_id(payload->'move'->>'url')          AS move_id,
       raw.url_id(payload->'version_group'->>'url') AS version_group_id
FROM raw.current_response WHERE endpoint = 'machine';

-- Grain: one row per item.
CREATE OR REPLACE VIEW stg.item AS
SELECT resource_id                         AS item_id,
       payload->>'name'                    AS item_code,
       stg.en_name(payload->'names')       AS item_name,
       payload->'category'->>'name'        AS category,
       (payload->>'cost')::int             AS cost,
       (payload->>'fling_power')::int      AS fling_power,
       payload->'fling_effect'->>'name'    AS fling_effect,
       EXISTS (SELECT 1 FROM jsonb_array_elements(payload->'attributes') a
                WHERE a->>'name' = 'holdable')  AS is_holdable
FROM raw.current_response WHERE endpoint = 'item';

-- Grain: one row per location area (an area belongs to one location,
-- a location to one region: we flatten that hierarchy into the dim).
CREATE OR REPLACE VIEW stg.location_area AS
SELECT la.resource_id                                 AS location_area_id,
       la.payload->>'name'                            AS location_area_code,
       stg.en_name(la.payload->'names')               AS location_area_name,
       raw.url_id(la.payload->'location'->>'url')     AS location_id,
       la.payload->'location'->>'name'                AS location_code,
       stg.en_name(l.payload->'names')                AS location_name,
       raw.url_id(l.payload->'region'->>'url')        AS region_id,
       l.payload->'region'->>'name'                   AS region_code
FROM raw.current_response la
LEFT JOIN raw.current_response l
       ON l.endpoint = 'location'
      AND l.resource_id = raw.url_id(la.payload->'location'->>'url')
WHERE la.endpoint = 'location-area';

-- Grain: one row per species.
CREATE OR REPLACE VIEW stg.species AS
SELECT resource_id                                          AS species_id,
       payload->>'name'                                     AS species_code,
       stg.en_name(payload->'names')                        AS species_name,
       (SELECT g->>'genus' FROM jsonb_array_elements(payload->'genera') g
         WHERE g->'language'->>'name' = 'en' LIMIT 1)       AS genus,
       raw.url_id(payload->'generation'->>'url')            AS generation_id,
       raw.url_id(payload->'evolution_chain'->>'url')       AS evolution_chain_id,
       raw.url_id(payload->'evolves_from_species'->>'url')  AS evolves_from_species_id,
       (payload->>'is_baby')::boolean                       AS is_baby,
       (payload->>'is_legendary')::boolean                  AS is_legendary,
       (payload->>'is_mythical')::boolean                   AS is_mythical,
       (payload->>'capture_rate')::int                      AS capture_rate,
       (payload->>'base_happiness')::int                    AS base_happiness,
       (payload->>'gender_rate')::int                       AS gender_rate,
       (payload->>'hatch_counter')::int                     AS hatch_counter,
       (payload->>'has_gender_differences')::boolean        AS has_gender_differences,
       payload->'growth_rate'->>'name'                      AS growth_rate,
       payload->'color'->>'name'                            AS color,
       payload->'shape'->>'name'                            AS shape,
       payload->'habitat'->>'name'                          AS habitat
FROM raw.current_response WHERE endpoint = 'pokemon-species';

-- Grain: species x pokedex. The same species has a different number in
-- every regional dex (Pikachu: #25 national, #74 Paldea).
CREATE OR REPLACE VIEW stg.pokedex_entry AS
SELECT s.resource_id                         AS species_id,
       raw.url_id(d->'pokedex'->>'url')      AS pokedex_id,
       (d->>'entry_number')::int             AS entry_number
FROM raw.current_response s
CROSS JOIN LATERAL jsonb_array_elements(s.payload->'pokedex_numbers') d
WHERE s.endpoint = 'pokemon-species';

-- Grain: one row per pokemon (a "variety" of a species: e.g. raticate
-- and raticate-alola are two pokemon of one species).
CREATE OR REPLACE VIEW stg.pokemon AS
SELECT resource_id                             AS pokemon_id,
       payload->>'name'                        AS pokemon_code,
       raw.url_id(payload->'species'->>'url')  AS species_id,
       (payload->>'is_default')::boolean       AS is_default,
       (payload->>'height')::int               AS height_dm,
       (payload->>'weight')::int               AS weight_hg,
       (payload->>'base_experience')::int      AS base_experience,
       (payload->>'order')::int                AS sort_order
FROM raw.current_response WHERE endpoint = 'pokemon';

-- Grain: one row per pokemon form. Most pokemon have exactly one form;
-- cosmetic variants (Unown's 28 letters, Vivillon's patterns) are extra
-- FORMS of one pokemon, while battle-relevant variants (megas, regional
-- forms) are separate POKEMON, each with its own default form.
CREATE OR REPLACE VIEW stg.pokemon_form AS
SELECT resource_id                                   AS form_id,
       payload->>'name'                              AS form_code,
       NULLIF(payload->>'form_name', '')             AS form_name,
       raw.url_id(payload->'pokemon'->>'url')        AS pokemon_id,
       (payload->>'is_default')::boolean             AS is_default,
       (payload->>'is_battle_only')::boolean         AS is_battle_only,
       (payload->>'is_mega')::boolean                AS is_mega,
       raw.url_id(payload->'version_group'->>'url')  AS introduced_version_group_id
FROM raw.current_response WHERE endpoint = 'pokemon-form';

-- Small lookup dims share one shape, so one view serves them all.
-- Grain: one row per (endpoint, resource).
CREATE OR REPLACE VIEW stg.lookup AS
SELECT endpoint,
       resource_id                    AS lookup_id,
       payload->>'name'               AS lookup_code,
       stg.en_name(payload->'names')  AS lookup_name
FROM raw.current_response
WHERE endpoint IN ('move-learn-method', 'encounter-method', 'evolution-trigger');

-- Grain: one row per encounter condition value (time-night, season-winter,
-- weather-raining, story-progress-..., ~360 of them in 30 condition types).
CREATE OR REPLACE VIEW stg.encounter_condition_value AS
SELECT resource_id                         AS condition_value_id,
       payload->>'name'                    AS condition_value_code,
       payload->'condition'->>'name'       AS condition_code
FROM raw.current_response WHERE endpoint = 'encounter-condition-value';

-- --------------------------------------------------------------- facts

-- Grain: pokemon x move x version_group x learn_method x level.
-- Level IS part of the grain: Smeargle learns Sketch at levels 1, 11, 21,
-- ... 91 in the same game, and some Pokémon relearn a move at a later level.
-- Source: pokemon.moves[].version_group_details[] (two levels of nesting).
CREATE OR REPLACE VIEW stg.pokemon_move AS
SELECT p.resource_id                                         AS pokemon_id,
       raw.url_id(m->'move'->>'url')                         AS move_id,
       raw.url_id(d->'version_group'->>'url')                AS version_group_id,
       raw.url_id(d->'move_learn_method'->>'url')            AS learn_method_id,
       (d->>'level_learned_at')::int                         AS level_learned_at,
       (d->>'order')::int                                    AS learn_order
FROM raw.current_response p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'moves') m
CROSS JOIN LATERAL jsonb_array_elements(m->'version_group_details') d
WHERE p.endpoint = 'pokemon';

-- Grain: pokemon x stat x stat-era. past_stats only lists the stats that
-- changed, so eras are built per (pokemon, stat). Each past entry is
-- valid up to and including its generation; the current value runs on.
-- Generation I's 'special' stat only appears in past_stats.
CREATE OR REPLACE VIEW stg.pokemon_stat AS
WITH eras AS (
    SELECT p.resource_id                         AS pokemon_id,
           raw.url_id(s->'stat'->>'url')         AS stat_id,
           (s->>'base_stat')::int                AS base_stat,
           (s->>'effort')::int                   AS effort,
           raw.url_id(ps->'generation'->>'url')  AS valid_to_generation_id
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_stats', '[]')) ps
    CROSS JOIN LATERAL jsonb_array_elements(ps->'stats') s
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, raw.url_id(s->'stat'->>'url'),
           (s->>'base_stat')::int, (s->>'effort')::int, NULL
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(p.payload->'stats') s
    WHERE p.endpoint = 'pokemon'
)
SELECT pokemon_id, stat_id, base_stat, effort,
       COALESCE(lag(valid_to_generation_id) OVER (
           PARTITION BY pokemon_id, stat_id
           ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id,
       valid_to_generation_id                                 -- NULL = still current
FROM eras;

-- Grain: pokemon x slot x type-era. past_types replaces the WHOLE typing,
-- so eras are built per pokemon. Each past entry is valid up to and
-- including its generation (Clefairy: normal to gen V, fairy from gen VI).
CREATE OR REPLACE VIEW stg.pokemon_type AS
WITH eras AS (
    SELECT p.resource_id AS pokemon_id,
           raw.url_id(pt->'generation'->>'url') AS valid_to_generation_id,
           pt->'types' AS types
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_types', '[]')) pt
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, NULL, p.payload->'types'
    FROM raw.current_response p
    WHERE p.endpoint = 'pokemon'
), ranged AS (
    SELECT pokemon_id, types, valid_to_generation_id,
           COALESCE(lag(valid_to_generation_id) OVER (
               PARTITION BY pokemon_id
               ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id
    FROM eras
)
SELECT r.pokemon_id,
       (t->>'slot')::int                AS slot,
       raw.url_id(t->'type'->>'url')    AS type_id,
       r.valid_from_generation_id,
       r.valid_to_generation_id         -- NULL = still current
FROM ranged r
CROSS JOIN LATERAL jsonb_array_elements(r.types) t;

-- Grain: pokemon x ability slot x era. past_abilities lists only the slots
-- that changed; an entry with ability = null means the slot did not exist
-- yet (Pikachu has no hidden-ability slot up to gen IV). Those rows are
-- kept here with ability_id NULL and dropped in the load.
CREATE OR REPLACE VIEW stg.pokemon_ability AS
WITH eras AS (
    SELECT p.resource_id                         AS pokemon_id,
           (a->>'slot')::int                     AS slot,
           raw.url_id(a->'ability'->>'url')      AS ability_id,
           (a->>'is_hidden')::boolean            AS is_hidden,
           raw.url_id(pa->'generation'->>'url')  AS valid_to_generation_id
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_abilities', '[]')) pa
    CROSS JOIN LATERAL jsonb_array_elements(pa->'abilities') a
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    SELECT p.resource_id, (a->>'slot')::int, raw.url_id(a->'ability'->>'url'),
           (a->>'is_hidden')::boolean, NULL
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(p.payload->'abilities') a
    WHERE p.endpoint = 'pokemon'
)
SELECT pokemon_id, slot, ability_id, is_hidden,
       COALESCE(lag(valid_to_generation_id) OVER (
           PARTITION BY pokemon_id, slot
           ORDER BY valid_to_generation_id NULLS LAST) + 1, 1) AS valid_from_generation_id,
       valid_to_generation_id
FROM eras;

-- Grain: pokemon x item x version.
CREATE OR REPLACE VIEW stg.pokemon_held_item AS
SELECT p.resource_id                    AS pokemon_id,
       raw.url_id(h->'item'->>'url')    AS item_id,
       raw.url_id(v->'version'->>'url') AS version_id,
       (v->>'rarity')::int              AS rarity_pct
FROM raw.current_response p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'held_items') h
CROSS JOIN LATERAL jsonb_array_elements(h->'version_details') v
WHERE p.endpoint = 'pokemon';

-- Grain: one encounter slot = location_area x pokemon x version x
-- position in encounter_details[]. The source can list two identical
-- slots (same method, levels and chance), so the array ordinal is part
-- of the grain: without it you would silently de-duplicate real slots.
-- (In the games, a grass area has 12 slots with fixed odds
-- 20/20/10/10/10/10/5/5/4/4/1/1; one Pokémon can fill several of them.)
CREATE OR REPLACE VIEW stg.encounter AS
SELECT la.resource_id                                AS location_area_id,
       raw.url_id(pe->'pokemon'->>'url')             AS pokemon_id,
       raw.url_id(vd->'version'->>'url')             AS version_id,
       ed.ord::int                                   AS slot_seq,
       raw.url_id(ed.e->'method'->>'url')            AS encounter_method_id,
       (ed.e->>'min_level')::int                     AS min_level,
       (ed.e->>'max_level')::int                     AS max_level,
       (ed.e->>'chance')::int                        AS chance_pct,
       COALESCE((SELECT string_agg(cv->>'name', ',' ORDER BY cv->>'name')
                   FROM jsonb_array_elements(ed.e->'condition_values') cv), '') AS condition_set_code
FROM raw.current_response la
CROSS JOIN LATERAL jsonb_array_elements(la.payload->'pokemon_encounters') pe
CROSS JOIN LATERAL jsonb_array_elements(pe->'version_details') vd
CROSS JOIN LATERAL jsonb_array_elements(vd->'encounter_details') WITH ORDINALITY AS ed(e, ord)
WHERE la.endpoint = 'location-area';

-- Grain: attacking type x defending type x era (multiplier from the
-- attacker's point of view). Missing pairs are neutral (1x) and are
-- densified in the mart load, not here.
CREATE OR REPLACE VIEW stg.type_damage AS
WITH rel AS (
    SELECT t.resource_id AS attacking_type_id,
           NULL::int     AS valid_to_generation_id,
           t.payload->'damage_relations' AS dr
    FROM raw.current_response t WHERE t.endpoint = 'type'
    UNION ALL
    SELECT t.resource_id,
           raw.url_id(pd->'generation'->>'url'),
           pd->'damage_relations'
    FROM raw.current_response t
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(t.payload->'past_damage_relations', '[]')) pd
    WHERE t.endpoint = 'type'
)
SELECT r.attacking_type_id,
       raw.url_id(x->>'url') AS defending_type_id,
       k.multiplier,
       r.valid_to_generation_id
FROM rel r
CROSS JOIN LATERAL (VALUES ('no_damage_to', 0.0), ('half_damage_to', 0.5),
                           ('double_damage_to', 2.0)) AS k(rel_key, multiplier)
CROSS JOIN LATERAL jsonb_array_elements(COALESCE(r.dr->k.rel_key, '[]')) x;

-- Grain: one evolution condition = evolution_chain x to_species x
-- position in evolution_details[]. The chain is a tree of unknown depth,
-- so it is walked with a recursive CTE. One step can have several
-- alternative conditions: per game (Magnezone: level up at Mt. Coronet in
-- gen IV, Thunder Stone from Sword/Shield) and per form (Pikachu evolves
-- into Alolan Raichu only in Alola: region + evolved_form).
CREATE OR REPLACE VIEW stg.evolution AS
WITH RECURSIVE walk AS (
    SELECT c.resource_id                AS evolution_chain_id,
           NULL::int                    AS from_species_id,
           c.payload->'chain'           AS node,
           0                            AS depth
    FROM raw.current_response c WHERE c.endpoint = 'evolution-chain'
    UNION ALL
    SELECT w.evolution_chain_id,
           raw.url_id(w.node->'species'->>'url'),
           child,
           w.depth + 1
    FROM walk w
    CROSS JOIN LATERAL jsonb_array_elements(w.node->'evolves_to') child
)
SELECT w.evolution_chain_id,
       w.from_species_id,
       raw.url_id(w.node->'species'->>'url')             AS to_species_id,
       w.depth                                           AS stage,
       d.ord::int                                        AS detail_seq,
       raw.url_id(d.e->'trigger'->>'url')                AS evolution_trigger_id,
       raw.url_id(d.e->'version_group'->>'url')          AS version_group_id,
       COALESCE((d.e->>'is_default')::boolean, true)     AS is_default_path,
       raw.url_id(d.e->'item'->>'url')                   AS item_id,
       raw.url_id(d.e->'held_item'->>'url')              AS held_item_id,
       raw.url_id(d.e->'known_move'->>'url')             AS known_move_id,
       raw.url_id(d.e->'known_move_type'->>'url')        AS known_move_type_id,
       raw.url_id(d.e->'used_move'->>'url')              AS used_move_id,
       raw.url_id(d.e->'location'->>'url')               AS location_id,
       d.e->'region'->>'name'                            AS region_code,
       raw.url_id(d.e->'trade_species'->>'url')          AS trade_species_id,
       raw.url_id(d.e->'party_species'->>'url')          AS party_species_id,
       raw.url_id(d.e->'party_type'->>'url')             AS party_type_id,
       raw.url_id(d.e->'required_pokemon_form'->>'url')  AS required_form_id,
       raw.url_id(d.e->'evolved_pokemon_form'->>'url')   AS evolved_form_id,
       (d.e->>'min_level')::int                          AS min_level,
       (d.e->>'min_happiness')::int                      AS min_happiness,
       (d.e->>'min_beauty')::int                         AS min_beauty,
       (d.e->>'min_affection')::int                      AS min_affection,
       (d.e->>'min_move_count')::int                     AS min_move_count,
       (d.e->>'min_steps')::int                          AS min_steps,
       (d.e->>'min_damage_taken')::int                   AS min_damage_taken,
       (d.e->>'relative_physical_stats')::int            AS relative_physical_stats,
       NULLIF(d.e->>'time_of_day', '')                   AS time_of_day,
       (d.e->>'gender')::int                             AS gender_id,
       COALESCE((d.e->>'needs_overworld_rain')::boolean, false) AS needs_overworld_rain,
       COALESCE((d.e->>'turn_upside_down')::boolean, false)     AS turn_upside_down,
       COALESCE((d.e->>'near_special_rock')::boolean, false)    AS near_special_rock,
       COALESCE((d.e->>'needs_multiplayer')::boolean, false)    AS needs_multiplayer
FROM walk w
CROSS JOIN LATERAL jsonb_array_elements(w.node->'evolution_details') WITH ORDINALITY AS d(e, ord)
WHERE w.depth > 0;
