#!/bin/bash
# Set isMappingValid on charts that don't have it yet.
# Run it through make: make script name=patchCharts ENV=staging
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

mongo_exec mongosh --quiet "$DX_DB" --eval '
db.Chart.updateMany(
   { isMappingValid: { $exists: false } },
   { $set: { isMappingValid: true } }
)'

echo "Updating is done"
