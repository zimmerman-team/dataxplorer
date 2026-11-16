#!/bin/bash
# Rename the Report collection to Story.
# Run it through make: make script name=renameCollection ENV=staging
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

mongo_exec mongosh --quiet "$DX_DB" --eval 'db.Report.renameCollection("Story")'

echo "Updating is done"
