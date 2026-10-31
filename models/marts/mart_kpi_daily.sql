-- Single source of truth for daily support KPIs (one row per day).
-- Metric definitions are documented in METRICS.md and _marts.yml.
-- Ratios are stored as numerator + denominator so they re-aggregate
-- correctly to week/month in Looker Studio.

with spine as (

    select date_day
    from {{ ref('dim_date') }}
    where date_day between (select min(created_date) from {{ ref('fct_cases') }})
                       and (select max(created_date) from {{ ref('fct_cases') }})

),

created as (

    select
        created_date                                                   as date_day,
        count(*)                                                       as cases_created,
        countif(priority = 'P1')                                       as p1_cases_created,
        countif(is_escalated)                                          as cases_escalated,
        countif(met_first_response_sla is not null)                    as first_responses_measured,
        countif(met_first_response_sla)                                as first_responses_within_sla,
        approx_quantiles(first_response_minutes, 100 ignore nulls)[offset(50)] as median_first_response_minutes,
        approx_quantiles(first_response_minutes, 100 ignore nulls)[offset(90)] as p90_first_response_minutes,
        countif(not is_excluded_from_durations)                        as cases_created_for_backlog
    from {{ ref('fct_cases') }}
    group by 1

),

resolved as (

    select
        resolved_date                                                  as date_day,
        count(*)                                                       as cases_resolved,
        countif(is_reopened)                                           as cases_reopened,
        approx_quantiles(resolution_hours, 100 ignore nulls)[offset(50)] as median_resolution_hours
    from {{ ref('fct_cases') }}
    where resolved_date is not null
    group by 1

),

csat as (

    select
        date(csat_submitted_at)                                        as date_day,
        count(*)                                                       as csat_responses,
        countif(is_satisfied)                                          as csat_satisfied_responses,
        sum(csat_score)                                                as csat_score_total
    from {{ ref('fct_cases') }}
    where csat_score is not null
    group by 1

),

daily as (

    select
        spine.date_day,
        coalesce(c.cases_created, 0)               as cases_created,
        coalesce(c.p1_cases_created, 0)            as p1_cases_created,
        coalesce(c.cases_escalated, 0)             as cases_escalated,
        coalesce(r.cases_resolved, 0)              as cases_resolved,
        coalesce(r.cases_reopened, 0)              as cases_reopened,
        coalesce(c.first_responses_measured, 0)    as first_responses_measured,
        coalesce(c.first_responses_within_sla, 0)  as first_responses_within_sla,
        c.median_first_response_minutes,
        c.p90_first_response_minutes,
        r.median_resolution_hours,
        coalesce(s.csat_responses, 0)              as csat_responses,
        coalesce(s.csat_satisfied_responses, 0)    as csat_satisfied_responses,
        coalesce(s.csat_score_total, 0)            as csat_score_total,
        coalesce(c.cases_created_for_backlog, 0)   as cases_created_for_backlog
    from spine
    left join created  as c on spine.date_day = c.date_day
    left join resolved as r on spine.date_day = r.date_day
    left join csat     as s on spine.date_day = s.date_day

)

select
    * except (cases_created_for_backlog),
    sum(cases_created_for_backlog) over (order by date_day)
      - sum(cases_resolved) over (order by date_day)            as open_backlog_end_of_day,
    safe_divide(first_responses_within_sla, first_responses_measured) as first_response_sla_rate,
    safe_divide(csat_satisfied_responses, csat_responses)       as csat_satisfaction_rate,
    safe_divide(cases_escalated, cases_created)                 as escalation_rate
from daily
