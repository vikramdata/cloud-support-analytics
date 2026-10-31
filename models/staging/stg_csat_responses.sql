-- One row per CSAT survey, typed and flagged. Invalid rows are kept and flagged
-- so the data quality page can count them; marts use only valid rows.

with source as (

    select * from {{ source('raw', 'csat_responses') }}

),

cases as (

    select distinct case_id from {{ source('raw', 'support_cases') }}

)

select
    s.survey_id,
    s.case_id,
    safe.parse_timestamp('%Y-%m-%d %H:%M:%S', nullif(s.submitted_at, '')) as submitted_at,
    safe_cast(s.csat_score as int64)                                      as csat_score,
    coalesce(safe_cast(s.csat_score as int64) between 1 and 5, false)     as is_valid_score,
    c.case_id is not null                                                 as has_matching_case
from source as s
left join cases as c
    on s.case_id = c.case_id
