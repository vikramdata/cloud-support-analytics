-- A negative backlog would mean resolutions were counted without their cases.
select date_day, open_backlog_end_of_day
from {{ ref('mart_kpi_daily') }}
where open_backlog_end_of_day < 0
