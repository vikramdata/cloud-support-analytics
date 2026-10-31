{#
  Use the folder's schema name as-is (e.g. `staging`, `marts`) instead of
  dbt's default `<target_dataset>_<schema>` naming, so the BigQuery datasets
  read cleanly in the console and in Looker Studio.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}
