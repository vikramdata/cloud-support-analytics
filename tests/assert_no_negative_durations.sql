-- Clean marts must never contain negative response or resolution times.
select case_id, first_response_minutes, resolution_hours
from {{ ref('fct_cases') }}
where first_response_minutes < 0
   or resolution_hours < 0
