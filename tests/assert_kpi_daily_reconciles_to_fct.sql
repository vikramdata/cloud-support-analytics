-- Single source of truth check: total cases in the daily KPI mart must equal
-- the case-level fact table, so dashboards built on either agree.
with mart as (select sum(cases_created) as n from {{ ref('mart_kpi_daily') }}),
     fct  as (select count(*) as n from {{ ref('fct_cases') }})
select mart.n as mart_cases, fct.n as fct_cases
from mart, fct
where mart.n != fct.n
