#!/bin/bash
# One-off, per server and environment: copy the data of the old submodule setup
# into the volumes of this ENV's compose project (dx-<env>). The old volumes and
# folders are left untouched, so they stay as a fallback.
#
#   make import-legacy ENV=production OLD_DIR=/root/DX [OLD_PROJECT=dx]
#
# OLD_DIR      the old checkout, which holds dx.backend/parsed-data-files and friends
# OLD_PROJECT  the old compose project name, which prefixes the old volumes
#              (dx_dx_mongo_data). It defaults to OLD_DIR's folder name in lower case;
#              check with `docker volume ls`.
#
# Run it after the images in versions.<env>.env exist, with the old stack stopped,
# as a user that can read OLD_DIR. docs/MIGRATION.md has the full cutover.
set -euo pipefail
cd "$(dirname "$0")/.."
. scripts/lib.sh

old_dir="${1:-}"
old_project="${2:-}"
if [ -z "$old_dir" ] || [ ! -d "$old_dir/dx.backend" ]; then
  echo "Usage: make import-legacy ENV=<env> OLD_DIR=<old checkout> [OLD_PROJECT=<old project name>]" >&2
  exit 1
fi
old_dir="$(cd "$old_dir" && pwd)"
old_project="${old_project:-$(basename "$old_dir" | tr '[:upper:]' '[:lower:]')}"
new_project="dx-$ENV"

# The old setup named things after the mode: dx-mongo (prod), dx-mongo-staging,
# dx_dx_mongo_data_staging, and so on.
case "$ENV" in
  production)  old_mode="" ;;
  development) old_mode="dev" ;;
  *)           old_mode="$ENV" ;;
esac

running="$(docker ps --format '{{.Names}}' | grep -E "^dx-(mongo|redis|server|backend|ai-api|frontend)${old_mode:+-$old_mode}\$" || true)"
if [ -n "$running" ]; then
  echo "Stop the old $ENV containers first, so the copy is consistent:" >&2
  echo "$running" >&2
  exit 1
fi

volume_exists() { docker volume inspect "$1" >/dev/null 2>&1; }
volume_empty() { docker run --rm -v "$1":/v:ro alpine:3.20 sh -c '[ -z "$(ls -A /v)" ]'; }

# copy <old volume or folder> <new volume key>
copy() {
  local from="$1" to="${new_project}_$2"
  if [ "${from#/}" != "$from" ]; then
    [ -d "$from" ] || { echo "  skip $from: no such folder"; return 0; }
  else
    volume_exists "$from" || { echo "  skip $from: no such volume"; return 0; }
  fi
  volume_exists "$to" || { echo "  skip $from: $to doesn't exist (profile not enabled?)"; return 0; }
  echo "  $from -> $to"
  docker run --rm -v "$from":/from:ro -v "$to":/to alpine:3.20 sh -c 'cp -a /from/. /to/'
}

echo "Creating $new_project's containers and volumes (nothing is started)..."
dc up --no-start

# Never merge two databases' files: the new database volumes must be empty.
for key in mongo_data redis_data; do
  if ! volume_empty "${new_project}_$key"; then
    echo "${new_project}_$key already holds data; not copying over it." >&2
    exit 1
  fi
done

echo "Copying data:"
copy "${old_project}_dx_mongo_data${old_mode:+_$old_mode}" mongo_data
copy "${old_project}_dx_redis_data${old_mode:+_$old_mode}" redis_data
copy "$old_dir/dx.backend/parsed-data-files" parsed_data_files
copy "$old_dir/dx.backend/sample-data-files" sample_data_files
copy "$old_dir/dx.backend/staging" staging_files
copy "$old_dir/dx.backend/logging" backend_logs
copy "$old_dir/dx.server/logging" server_logs

echo "Done. Start the environment with: make up ENV=$ENV ENV_DIR=<env dir>"
