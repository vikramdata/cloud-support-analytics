#!/usr/bin/env bash
# Load the generated CSVs into BigQuery as the `raw` layer.
#
# Every column is loaded as STRING on purpose. The raw layer mirrors the
# source exactly (bad values included); typing, deduplication and data
# quality checks happen in the dbt staging models.
#
# Usage:  ./load_raw.sh <your-gcp-project-id>
set -euo pipefail

PROJECT="${1:?Usage: ./load_raw.sh <gcp-project-id>}"
DATASET="raw"
LOCATION="US"
DATA_DIR="data"

bq --location="$LOCATION" mk --force --dataset "$PROJECT:$DATASET"

for file in "$DATA_DIR"/*.csv; do
  table="$(basename "$file" .csv)"
  schema="$(head -1 "$file" | tr -d '\r' | sed 's/,/:STRING,/g'):STRING"
  echo "Loading $table ..."
  bq --location="$LOCATION" load \
    --replace \
    --source_format=CSV \
    --skip_leading_rows=1 \
    "$PROJECT:$DATASET.$table" "$file" "$schema"
done

echo "Done. Row counts:"
bq --location="$LOCATION" query --use_legacy_sql=false --format=pretty "
SELECT 'support_cases' AS table_name, COUNT(*) AS row_count FROM \`$PROJECT.$DATASET.support_cases\`
UNION ALL SELECT 'csat_responses', COUNT(*) FROM \`$PROJECT.$DATASET.csat_responses\`
UNION ALL SELECT 'customers', COUNT(*) FROM \`$PROJECT.$DATASET.customers\`
UNION ALL SELECT 'agents', COUNT(*) FROM \`$PROJECT.$DATASET.agents\`
UNION ALL SELECT 'products', COUNT(*) FROM \`$PROJECT.$DATASET.products\`
UNION ALL SELECT 'sla_targets', COUNT(*) FROM \`$PROJECT.$DATASET.sla_targets\`
ORDER BY row_count DESC"
