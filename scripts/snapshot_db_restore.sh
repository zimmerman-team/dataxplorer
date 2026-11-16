#!/bin/bash
# Restore a dump from snapshots/ into ENV's database, replacing the collections in it.
# Run it through make: make restore ENV=staging snapshot=production-20261113120000.archive.gz
# Folders from the old snapshot script (snapshots/<timestamp>/) work too.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

name="${1:-}"
dir="${BACKUP_DIR:-snapshots}"
if [ -z "$name" ] || [ ! -e "$dir/$name" ]; then
  echo "Usage: make restore ENV=<env> snapshot=<name>. Snapshots in $dir/:" >&2
  ls -1t "$dir" >&2 || true
  exit 1
fi

confirm "Replace the data in $ENV's database with $name?" || { echo "Aborted."; exit 1; }

if [ -f "$dir/$name" ]; then
  mongo_exec mongorestore --archive --gzip --drop --nsInclude "$DX_DB.*" < "$dir/$name"
elif [ -n "${NATIVE:-}" ]; then
  # Old format, without Docker: restore straight from the folder.
  mongo_exec mongorestore --drop --nsInclude "$DX_DB.*" --dir "$dir/$name"
else
  # Old format: a mongodump folder holding one folder per database.
  tmp="/tmp/restore-$name"
  dc cp "$dir/$name" "mongo:$tmp"
  mongo_exec mongorestore --drop --nsInclude "$DX_DB.*" --dir "$tmp"
  dc exec -T mongo rm -rf "$tmp"
fi

echo "Restored $name into $ENV."
