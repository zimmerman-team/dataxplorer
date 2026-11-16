#!/bin/bash
# Dump ENV's database to snapshots/<env>-<timestamp>.archive.gz with mongodump.
# Run it through make: make backup ENV=production
# Set BACKUP_DIR to write somewhere other than snapshots/.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

dir="${BACKUP_DIR:-snapshots}"
file="$dir/$ENV-$(date +%Y%m%d%H%M%S).archive.gz"
mkdir -p "$dir"
trap 'rm -f "$file.partial"' EXIT

# Stream the dump out of the container rather than writing it into the data volume.
mongo_exec mongodump --db "$DX_DB" --archive --gzip > "$file.partial"
mv "$file.partial" "$file"
echo "Wrote $file"
