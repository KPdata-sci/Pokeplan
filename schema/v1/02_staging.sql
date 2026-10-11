-- =====================================================================
-- Pokeplan :: Layer 2 — STAGING (a.k.a. silver)
-- ---------------------------------------------------------------------
-- Pattern: one view per *grain*, not one view per endpoint. Each view
-- flattens one nested JSON list into rows, renames fields to snake_case
-- columns, parses URL -> integer id, and picks the English name.
-- No business logic, no surrogate keys: those belong to the mart layer.
--
-- Every view states its grain in a comment. If a view ever returns two
-- rows for the same grain columns, the grain is wrong (see 05_tests.sql).
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
CREATE OR REPLACE VIEW stg.version_group AS
SELECT resource_id                               AS version_group_id,
       payload->>'name'                          AS version_group_code,
       (payload->>'order')::int                  AS sort_order,
       raw.url_id(payload->'generation'->>'url') AS generation_id
FROM raw.current_response WHERE endpoint = 'version-group';

-- Grain: one row per version (e.g. red, blue).
CREATE OR REPLACE VIEW stg.version AS
SELECT resource_id                                  AS version_id,
       payload->>'name'                             AS version_code,
       stg.en_name(payload->'names')                AS version_name,
       raw.url_id(payload->'version_group'->>'url') AS version_group_id
FROM raw.current_response WHERE endpoint = 'version';

-- Grain: one row per type.
CREATE OR REPLACE VIEW stg.type AS
SELECT resource_id                                      AS type_id,
       payload->>'name'                                 AS type_code,
       stg.en_name(payload->'names')                    AS type_name,
       raw.url_id(payload->'generation'->>'url')        AS generation_id,
       payload->'move_damage_class'->>'name'            AS damage_class
FROM raw.current_response WHERE endpoint = 'type';

-- Grain: one row per stat (hp, attack, ... plus accuracy/evasion).
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

-- Grain: one row per move (current values; history lives in past_values).
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
       payload->'growth_rate'->>'name'                      AS growth_rate,
       payload->'color'->>'name'                            AS color,
       payload->'shape'->>'name'                            AS shape,
       payload->'habitat'->>'name'                          AS habitat
FROM raw.current_response WHERE endpoint = 'pokemon-species';

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

-- Small lookup dims (learn method, encounter method, evolution trigger)
-- share one shape, so one view serves them all.
-- Grain: one row per (endpoint, resource).
CREATE OR REPLACE VIEW stg.lookup AS
SELECT endpoint,
       resource_id                    AS lookup_id,
       payload->>'name'               AS lookup_code,
       stg.en_name(payload->'names')  AS lookup_name
FROM raw.current_response
WHERE endpoint IN ('move-learn-method', 'encounter-method', 'evolution-trigger');

-- --------------------------------------------------------------- facts

-- Grain: pokemon x move x version_group x learn_method.
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

-- Grain: pokemon x stat.
CREATE OR REPLACE VIEW stg.pokemon_stat AS
SELECT p.resource_id                   AS pokemon_id,
       raw.url_id(s->'stat'->>'url')   AS stat_id,
       (s->>'base_stat')::int          AS base_stat,
       (s->>'effort')::int             AS effort
FROM raw.current_response p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'stats') s
WHERE p.endpoint = 'pokemon';

-- Grain: pokemon x slot x type-era. Current types are valid from the
-- generation after the newest past_types entry; each past_types entry
-- is valid *up to and including* its generation.
CREATE OR REPLACE VIEW stg.pokemon_type AS
WITH eras AS (
    -- past eras
    SELECT p.resource_id AS pokemon_id,
           raw.url_id(pt->'generation'->>'url') AS valid_to_generation_id,
           pt->'types' AS types
    FROM raw.current_response p
    CROSS JOIN LATERAL jsonb_array_elements(COALESCE(p.payload->'past_types', '[]')) pt
    WHERE p.endpoint = 'pokemon'
    UNION ALL
    -- current era (open-ended)
    SELECT p.resource_id, NULL, p.payload->'types'
    FROM raw.current_response p
    WHERE p.endpoint = 'pokemon'
), ranged AS (
    SELECT pokemon_id, types, valid_to_generation_id,
           COALESCE(LAG(valid_to_generation_id) OVER (
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

-- Grain: pokemon x ability slot.
CREATE OR REPLACE VIEW stg.pokemon_ability AS
SELECT p.resource_id                      AS pokemon_id,
       (a->>'slot')::int                  AS slot,
       raw.url_id(a->'ability'->>'url')   AS ability_id,
       (a->>'is_hidden')::boolean         AS is_hidden
FROM raw.current_response p
CROSS JOIN LATERAL jsonb_array_elements(p.payload->'abilities') a
WHERE p.endpoint = 'pokemon';

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

-- Grain: attacking type x defending type x generation, current era only
-- (multiplier from the attacker's point of view). Missing pairs are
-- neutral (1x) and are densified in the mart load, not here.
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

-- Grain: one evolution step condition = evolution_chain x to_species x
-- position in evolution_details[]. The chain is a tree of unknown depth,
-- so it is walked with a recursive CTE.
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
       raw.url_id(d.e->'item'->>'url')                   AS item_id,
       raw.url_id(d.e->'held_item'->>'url')              AS held_item_id,
       raw.url_id(d.e->'known_move'->>'url')             AS known_move_id,
       raw.url_id(d.e->'known_move_type'->>'url')        AS known_move_type_id,
       raw.url_id(d.e->'location'->>'url')               AS location_id,
       raw.url_id(d.e->'trade_species'->>'url')          AS trade_species_id,
       (d.e->>'min_level')::int                          AS min_level,
       (d.e->>'min_happiness')::int                      AS min_happiness,
       (d.e->>'min_beauty')::int                         AS min_beauty,
       (d.e->>'min_affection')::int                      AS min_affection,
       NULLIF(d.e->>'time_of_day', '')                   AS time_of_day,
       (d.e->>'gender')::int                             AS gender_id,
       COALESCE((d.e->>'needs_overworld_rain')::boolean, false) AS needs_overworld_rain,
       COALESCE((d.e->>'turn_upside_down')::boolean, false)     AS turn_upside_down
FROM walk w
CROSS JOIN LATERAL jsonb_array_elements(w.node->'evolution_details') WITH ORDINALITY AS d(e, ord)
WHERE w.depth > 0;
