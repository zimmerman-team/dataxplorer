#!/bin/bash
# Set nameLower (the trimmed, lower-case name) on charts, datasets and reports.
# Run it through make: make script name=patchAssetsName ENV=staging
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

mongo_exec mongosh --quiet "$DX_DB" --eval '
for (const collection of ["Chart", "Dataset", "Report"]) {
  db[collection].updateMany(
     { name: { $exists: true } },
     [{ $set: { nameLower: { $toLower: { $trim: { input: "$name" } } } } }]
  );
}'

echo "Updating is done"
