-- Helpers for reading PokeAPI JSON. They expand to plain SQL subqueries, so
-- the warehouse needs no extra functions beyond raw.url_id() (01_raw.sql).

-- English display name from a list<Name>.
{% macro en_name(names) -%}
(SELECT n->>'name' FROM jsonb_array_elements(COALESCE({{ names }}, '[]'::jsonb)) n
  WHERE n->'language'->>'name' = 'en' LIMIT 1)
{%- endmacro %}

-- Game text comes with the cartridge's line and page breaks in it (old games
-- also break words with a soft hyphen). Flatten it to one line.
{% macro clean_text(t) -%}
NULLIF(btrim(regexp_replace(replace({{ t }}, E'­\n', ''), '[\s]+', ' ', 'g')), '')
{%- endmacro %}

-- Query for the English short_effect in an effect_entries list (use it in a
-- LATERAL join or wrap it in brackets).
{% macro en_short_effect(entries) -%}
SELECT e->>'short_effect' FROM jsonb_array_elements({{ entries }}) e
  WHERE e->'language'->>'name' = 'en' LIMIT 1
{%- endmacro %}

-- The English text from a flavor_text_entries list, newest game first.
-- Entries carry either version_group (moves, items) or version (species);
-- both ids rise with release order closely enough to pick the newest.
{% macro en_flavor(entries, text_key) -%}
(SELECT {{ clean_text("e->>'" ~ text_key ~ "'") }}
   FROM jsonb_array_elements(COALESCE({{ entries }}, '[]'::jsonb)) e
  WHERE e->'language'->>'name' = 'en'
  ORDER BY raw.url_id(COALESCE(e->'version_group', e->'version')->>'url') DESC NULLS LAST
  LIMIT 1)
{%- endmacro %}


-- Audit columns on every mart row.
{% macro audit_columns() -%}
{{ var('batch_id') if var('batch_id') is not none else 'NULL' }}::bigint AS _batch_id,
now() AS _loaded_at
{%- endmacro %}
