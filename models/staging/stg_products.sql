select
    product_id,
    product_name,
    product_area
from {{ source('raw', 'products') }}
