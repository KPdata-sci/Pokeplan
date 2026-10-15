-- Post-hook that gives a mart table its primary key, as the SQL version's
-- CREATE TABLE did. It enforces the grain at write time, and Postgres uses
-- it to know the other columns depend on the key (serve.game groups by
-- version_group_key alone). The name carries the run id because the
-- previous copy of the table, with its own key, still exists while the new
-- one is swapped in.
{% macro primary_key(columns) -%}
ALTER TABLE {{ this }}
  ADD CONSTRAINT {{ this.identifier }}_pk_{{ invocation_id.replace('-', '')[:12] }}
  PRIMARY KEY ({{ columns | join(', ') }})
{%- endmacro %}
