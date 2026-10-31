-- One row per support case: typed, deduplicated, with data quality flags.

with source as (

    select * from {{ source('raw', 'support_cases') }}

),

typed as (

    select
        case_id,
        customer_id,
        product_id,
        priority,
        channel,
        safe.parse_timestamp('%Y-%m-%d %H:%M:%S', nullif(created_at, ''))        as created_at,
        safe.parse_timestamp('%Y-%m-%d %H:%M:%S', nullif(first_response_at, '')) as first_response_at,
        safe.parse_timestamp('%Y-%m-%d %H:%M:%S', nullif(resolved_at, ''))       as resolved_at,
        status,
        nullif(assigned_agent_id, '')                                           as assigned_agent_id,
        is_escalated = 'true'                                                   as is_escalated,
        is_reopened = 'true'                                                    as is_reopened
    from source

),

deduplicated as (

    -- Duplicate copies of a case can differ (one may be missing its agent or
    -- carry a bad resolved_at). Keep the cleanest copy, and break any remaining
    -- tie on the full row so the result is identical on every run.
    select t.*
    from typed as t
    where true
    qualify row_number() over (
        partition by case_id
        order by
            assigned_agent_id is null,
            coalesce(resolved_at < created_at, false),
            to_json_string(t)
    ) = 1

)

select
    *,
    resolved_at is not null and resolved_at < created_at as has_invalid_resolved_at,
    assigned_agent_id is null                             as is_unassigned
from deduplicated