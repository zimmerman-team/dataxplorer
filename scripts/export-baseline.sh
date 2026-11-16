#!/bin/bash
# Development only: export the public (baseline) charts, stories and datasets from
# your local DX into prepopulate-data/, for make seed to load elsewhere.
# Run it through make: make script name=export-baseline
# Needs jq.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

[ "$ENV" = development ] || { echo "export-baseline only runs against ENV=development." >&2; exit 1; }
command -v jq >/dev/null || { echo "export-baseline needs jq." >&2; exit 1; }

echo "Backing up datasets..."
# The backend copies the public parsed datasets to staging/prepopulate-data.
if [ -n "${NATIVE:-}" ]; then
  (cd "$BACKEND_DIR" && .venv/bin/python scripts/backup-baseline-datasets.py)
  cp -R "$BACKEND_DIR/staging/prepopulate-data/parsed-data-files/." prepopulate-data/parsed-data-files/
  cp -R "$BACKEND_DIR/staging/prepopulate-data/sample-data-files/." prepopulate-data/sample-data-files/
  rm -rf "$BACKEND_DIR/staging/prepopulate-data"
else
  dc up -d --wait mongo backend
  dc exec -T backend python scripts/backup-baseline-datasets.py
  dc cp backend:/app/staging/prepopulate-data/parsed-data-files/. prepopulate-data/parsed-data-files/
  dc cp backend:/app/staging/prepopulate-data/sample-data-files/. prepopulate-data/sample-data-files/
  dc exec -T backend rm -rf /app/staging/prepopulate-data
fi

# Export the baseline documents, with the owner replaced by the REPL placeholder.
for collection in Chart Story Dataset; do
  echo "Exporting $collection..."
  mongo_exec mongoexport --quiet --db "$DX_DB" --collection "$collection" --query '{"baseline": true}' \
    | jq . \
    | sed -e 's/"authId": "[^"]*"/"authId": "REPL"/g' -e 's/"owner": "[^"]*"/"owner": "REPL"/g' \
    > "prepopulate-data/$collection"
done

echo "Baseline data exported to prepopulate-data/."
