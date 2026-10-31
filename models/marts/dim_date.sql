select
    date_day,
    extract(year from date_day)                     as year,
    extract(quarter from date_day)                  as quarter,
    format_date('%Y-%m', date_day)                  as year_month,
    date_trunc(date_day, week(monday))              as week_start,
    format_date('%A', date_day)                     as day_name,
    extract(dayofweek from date_day) in (1, 7)      as is_weekend
from unnest(generate_date_array('2025-01-01', '2026-12-31')) as date_day
