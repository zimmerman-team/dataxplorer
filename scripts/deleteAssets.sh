#!/bin/bash
# Delete every chart, dataset and story in ENV's database.
# Run it through make: make script name=deleteAssets ENV=development
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

confirm "Delete ALL charts, datasets and stories in $ENV? This can't be undone." || { echo "Aborted."; exit 1; }

mongo_exec mongosh --quiet "$DX_DB" --eval '
db.Chart.deleteMany({});
db.Dataset.deleteMany({});
db.Story.deleteMany({});'

echo "Updating is done"
