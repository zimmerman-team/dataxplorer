#!/bin/bash
# Load the public sample data in prepopulate-data/ into ENV's database and data
# volumes. Run it through make: make seed [ENV=development]
# Set AUTH_ID to skip the prompt for the user that owns the public data.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

auth_id="${AUTH_ID:-}"
if [ -z "$auth_id" ]; then
  read -r -s -p "authId of the user that owns the public data: " auth_id
  echo
fi
# Escape the characters sed treats specially in a replacement.
auth_id_sed="$(printf '%s' "$auth_id" | sed 's/[&/\]/\\&/g')"

if [ -n "${NATIVE:-}" ]; then
  echo "Copying the dataset files into $BACKEND_DIR..."
  mkdir -p "$BACKEND_DIR/parsed-data-files" "$BACKEND_DIR/sample-data-files"
  cp -R prepopulate-data/parsed-data-files/. "$BACKEND_DIR/parsed-data-files/"
  cp -R prepopulate-data/sample-data-files/. "$BACKEND_DIR/sample-data-files/"
else
  echo "Starting mongo and backend..."
  dc up -d --wait mongo backend
  echo "Copying the dataset files into the data volumes..."
  dc cp prepopulate-data/parsed-data-files/. backend:/app/parsed-data-files/
  dc cp prepopulate-data/sample-data-files/. backend:/app/sample-data-files/
fi

# Work on copies, so the committed files keep their REPL placeholders.
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for collection in Chart Story Dataset; do
  sed "s/REPL/$auth_id_sed/g" "prepopulate-data/$collection" > "$work/$collection"
done
tar -xJf prepopulate-data/FederatedSearchIndex.tar.xz -C "$work"

for collection in Chart Story Dataset FederatedSearchIndex; do
  echo "Importing $collection..."
  mongo_exec mongoimport --db "$DX_DB" --collection "$collection" --mode upsert < "$work/$collection"
done

echo "Sample data loaded into $ENV."
