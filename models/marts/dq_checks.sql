-- Data quality scorecard for the dashboard: one row per check, with how many
-- rows failed and how the pipeline handled them.

with raw_cases as (

    select count(*) as total_rows, count(distinct case_id) as distinct_cases
    from {{ source('raw', 'support_cases') }}

),

cases as (

    select
        count(*)                          as total_cases,
        countif(has_invalid_resolved_at)  as invalid_resolved_at,
        countif(is_unassigned)            as unassigned
    from {{ ref('stg_support_cases') }}

),

surveys as (

    select
        count(*)                          as total_surveys,
        countif(not is_valid_score)       as invalid_scores,
        countif(not has_matching_case)    as orphan_surveys
    from {{ ref('stg_csat_responses') }}

)

select 'Duplicate case rows' as check_name, 'support_cases' as source_table,
       total_rows - distinct_cases as failed_rows, total_rows as rows_checked,
       'Removed in staging (cleanest copy kept per case)' as handling
from raw_cases

union all
select 'Resolved before created', 'support_cases', invalid_resolved_at, total_cases,
       'Kept; excluded from resolution time and backlog'
from cases

union all
select 'Missing assigned agent', 'support_cases', unassigned, total_cases,
       'Kept; reported as Unassigned'
from cases

union all
select 'CSAT score outside 1-5', 'csat_responses', invalid_scores, total_surveys,
       'Excluded from CSAT metrics'
from surveys

union all
select 'Survey with no matching case', 'csat_responses', orphan_surveys, total_surveys,
       'Excluded from CSAT metrics'
from surveys