{{ config(cluster_by=['product_id', 'priority']) }}

-- One row per support case with SLA, duration and CSAT measures.
-- Production note: partition by DATE(created_at). Not done here because the
-- BigQuery sandbox expires partitions 60 days after their partition date.

with cases as (

    select * from {{ ref('stg_support_cases') }}

),

customers as (

    select * from {{ ref('stg_customers') }}

),

sla as (

    select * from {{ ref('stg_sla_targets') }}

),

products as (

    select * from {{ ref('stg_products') }}

),

agents as (

    select * from {{ ref('dim_agents') }}

),

csat as (

    select case_id, submitted_at, csat_score
    from {{ ref('stg_csat_responses') }}
    where is_valid_score and has_matching_case
    qualify row_number() over (partition by case_id order by submitted_at desc) = 1

),

joined as (

    select
        c.case_id,
        c.customer_id,
        c.product_id,
        p.product_name,
        p.product_area,
        coalesce(c.assigned_agent_id, 'UNASSIGNED')                  as agent_id,
        a.team                                                       as agent_team,
        c.priority,
        c.channel,
        c.status,
        cu.support_tier,
        cu.region                                                    as customer_region,
        cu.industry,

        c.created_at,
        date(c.created_at)                                           as created_date,
        c.first_response_at,
        if(c.has_invalid_resolved_at, null, c.resolved_at)           as resolved_at,
        date(if(c.has_invalid_resolved_at, null, c.resolved_at))     as resolved_date,

        s.first_response_target_minutes,
        timestamp_diff(c.first_response_at, c.created_at, minute)    as first_response_minutes,
        if(c.has_invalid_resolved_at, null,
           timestamp_diff(c.resolved_at, c.created_at, minute) / 60) as resolution_hours,

        c.status in ('Open', 'Pending Customer')                     as is_open,
        c.is_escalated,
        c.is_reopened,
        c.is_unassigned,
        c.has_invalid_resolved_at                                    as is_excluded_from_durations,

        cs.csat_score,
        cs.submitted_at                                              as csat_submitted_at
    from cases as c
    left join customers as cu on c.customer_id = cu.customer_id
    left join sla as s on cu.support_tier = s.support_tier and c.priority = s.priority
    left join products as p on c.product_id = p.product_id
    left join agents as a on coalesce(c.assigned_agent_id, 'UNASSIGNED') = a.agent_id
    left join csat as cs on c.case_id = cs.case_id

)

select
    *,
    case
        when first_response_minutes is null then null
        else first_response_minutes <= first_response_target_minutes
    end                                         as met_first_response_sla,
    if(csat_score is null, null, csat_score >= 4) as is_satisfied
from joined