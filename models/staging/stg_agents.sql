select
    agent_id,
    agent_name,
    team,
    region,
    level,
    safe.parse_date('%Y-%m-%d', hire_date) as hire_date
from {{ source('raw', 'agents') }}
