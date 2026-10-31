-- Includes an UNASSIGNED member so every case joins to an agent row.

select agent_id, agent_name, team, region, level, hire_date
from {{ ref('stg_agents') }}

union all

select 'UNASSIGNED', 'Unassigned', 'Unassigned', 'Unassigned', 'Unassigned', cast(null as date)
