{{ config(post_hook="{{ primary_key(['evolution_chain_id', 'to_species_key', 'detail_seq']) }}") }}
-- Grain: one row per evolution condition = chain x to_species x detail_seq.
-- One species-to-species step can have several alternative conditions
-- (per game, per region, per form), hence detail_seq. Uses ROLE-PLAYING
-- dimensions: dim_species (from / to / trade partner / party member),
-- dim_item (used / held), dim_move (known / used), dim_type (known move
-- type / party type). from_pokemon_key / to_pokemon_key resolve the step
-- to concrete varieties: no required form = the species' default variety
-- evolves; no evolved form = it becomes the target species' default
-- variety. So Pikachu -> Raichu (Thunder Stone) and Pikachu -> Alolan
-- Raichu (Thunder Stone, in Alola) are separate rows.
SELECT s.evolution_chain_id::integer                AS evolution_chain_id,   -- degenerate dimension
       COALESCE(ts.species_key, 0)                  AS to_species_key,
       s.detail_seq::smallint                       AS detail_seq,           -- degenerate dimension
       COALESCE(fs.species_key, 0)                  AS from_species_key,
       COALESCE(fp.pokemon_key, 0)                  AS from_pokemon_key,
       COALESCE(tp.pokemon_key, 0)                  AS to_pokemon_key,
       COALESCE(et.evolution_trigger_key, 0)::smallint AS evolution_trigger_key,
       COALESCE(vg.version_group_key, 0)::smallint  AS version_group_key,   -- game the rule was introduced in
       COALESCE(ui.item_key, 0)                     AS used_item_key,
       COALESCE(hi.item_key, 0)                     AS held_item_key,
       COALESCE(km.move_key, 0)                     AS known_move_key,
       COALESCE(um.move_key, 0)                     AS used_move_key,
       COALESCE(kt.type_key, 0)::smallint           AS known_move_type_key,
       COALESCE(pty.type_key, 0)::smallint          AS party_type_key,
       COALESCE(tr.species_key, 0)                  AS trade_species_key,
       COALESCE(ps.species_key, 0)                  AS party_species_key,
       s.location_id::integer                       AS location_id,          -- no dim_location yet; natural key
       s.region_code,                                                        -- only in this region
       s.stage::smallint                            AS stage,                -- 1 = first evolution, 2 = second
       s.is_default_path,
       s.min_level::smallint                        AS min_level,
       s.min_happiness::smallint                    AS min_happiness,
       s.min_beauty::smallint                       AS min_beauty,
       s.min_affection::smallint                    AS min_affection,
       s.min_move_count::smallint                   AS min_move_count,       -- use Barb Barrage 20 times
       s.min_steps::smallint                        AS min_steps,            -- Let's Go! walking evolutions
       s.min_damage_taken::smallint                 AS min_damage_taken,
       s.relative_physical_stats::smallint          AS relative_physical_stats, -- Tyrogue: 1 atk>def, 0 equal, -1 atk<def
       s.time_of_day,
       s.gender_id::smallint                        AS gender_id,
       s.needs_overworld_rain,
       s.turn_upside_down,
       s.near_special_rock,
       s.needs_multiplayer,
       {{ audit_columns() }}
FROM {{ ref('stg_evolution') }} s
LEFT JOIN {{ ref('dim_species') }} ts ON ts.species_id = s.to_species_id
LEFT JOIN {{ ref('dim_species') }} fs ON fs.species_id = s.from_species_id
LEFT JOIN {{ ref('dim_species') }} tr ON tr.species_id = s.trade_species_id
LEFT JOIN {{ ref('dim_species') }} ps ON ps.species_id = s.party_species_id
LEFT JOIN {{ ref('stg_pokemon_form') }} rf ON rf.form_id = s.required_form_id
LEFT JOIN {{ ref('stg_pokemon_form') }} ef ON ef.form_id = s.evolved_form_id
LEFT JOIN {{ ref('dim_pokemon') }} fd ON fd.species_id = s.from_species_id AND fd.is_default_form
LEFT JOIN {{ ref('dim_pokemon') }} td ON td.species_id = s.to_species_id AND td.is_default_form
LEFT JOIN {{ ref('dim_pokemon') }} fp ON fp.pokemon_id = COALESCE(rf.pokemon_id, fd.pokemon_id)
LEFT JOIN {{ ref('dim_pokemon') }} tp ON tp.pokemon_id = COALESCE(ef.pokemon_id, td.pokemon_id)
LEFT JOIN {{ ref('dim_evolution_trigger') }} et ON et.evolution_trigger_id = s.evolution_trigger_id
LEFT JOIN {{ ref('dim_version_group') }} vg ON vg.version_group_id = s.version_group_id
LEFT JOIN {{ ref('dim_item') }} ui ON ui.item_id = s.item_id
LEFT JOIN {{ ref('dim_item') }} hi ON hi.item_id = s.held_item_id
LEFT JOIN {{ ref('dim_move') }} km ON km.move_id = s.known_move_id AND km.is_current
LEFT JOIN {{ ref('dim_move') }} um ON um.move_id = s.used_move_id AND um.is_current
LEFT JOIN {{ ref('dim_type') }} kt ON kt.type_id = s.known_move_type_id
LEFT JOIN {{ ref('dim_type') }} pty ON pty.type_id = s.party_type_id
