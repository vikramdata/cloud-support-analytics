select
    customer_id,
    company_name,
    industry,
    region,
    support_tier,
    safe.parse_date('%Y-%m-%d', customer_since) as customer_since
from {{ source('raw', 'customers') }}
