-- Use a model's +schema exactly (stg, mart, ref), instead of dbt's default
-- of prefixing it with the target schema (public_stg, public_mart, ...).
{% macro generate_schema_name(custom_schema_name, node) -%}
    {{ (custom_schema_name or target.schema) | trim }}
{%- endmacro %}
