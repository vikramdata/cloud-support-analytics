select
    support_tier,
    priority,
    safe_cast(first_response_target_minutes as int64) as first_response_target_minutes
from {{ source('raw', 'sla_targets') }}
