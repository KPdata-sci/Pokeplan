-- Staging models are named stg_<grain> in dbt (so ref('stg_pokemon') reads
-- clearly) but are created as stg.<grain>, the names the SQL version used.
{% macro generate_alias_name(custom_alias_name=none, node=none) -%}
    {%- if custom_alias_name -%}
        {{ custom_alias_name | trim }}
    {%- elif node.resource_type == 'model' and node.name.startswith('stg_') -%}
        {{ node.name[4:] }}
    {%- else -%}
        {{ node.name }}
    {%- endif -%}
{%- endmacro %}
