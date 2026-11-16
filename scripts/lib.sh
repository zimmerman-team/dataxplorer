# Shared by the scripts the Makefile runs. Source it, don't run it.
# The Makefile exports ENV and DC (the docker compose command for ENV).

if [ -z "${DC:-}" ] || [ -z "${ENV:-}" ]; then
  echo "Run this through make (see make help), e.g. make seed ENV=development" >&2
  exit 1
fi

DX_DB=the-data-explorer-db

# docker compose for ENV's project.
dc() {
  # DC is a whole command line, so it is split into words on purpose.
  # shellcheck disable=SC2086
  $DC "$@"
}

# Run a mongo tool (mongosh, mongodump, mongorestore, mongoimport, mongoexport).
# Reads stdin, writes stdout.
#   mongo_exec mongosh --quiet "$DX_DB" --eval 'db.stats()'
if [ -n "${NATIVE:-}" ]; then
  # Without Docker: the tool on this machine, against the local MongoDB.
  BACKEND_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/dx.backend"
  mongo_exec() {
    command -v "$1" >/dev/null || {
      echo "$1 isn't installed." >&2
      echo "  macOS:  brew install mongosh mongodb/brew/mongodb-database-tools" >&2
      echo "  Linux:  sudo apt install mongodb-mongosh mongodb-database-tools (from MongoDB's repository)" >&2
      return 1
    }
    local tool="$1"; shift
    "$tool" --host "${MONGO_HOST:-localhost}" "$@"
  }
else
  # Inside the mongo container, logged in with the container's own root user so
  # no password passes through this host's command line.
  mongo_exec() {
    dc exec -T mongo sh -c 'exec "$0" -u "$MONGO_INITDB_ROOT_USERNAME" -p "$MONGO_INITDB_ROOT_PASSWORD" --authenticationDatabase admin "$@"' "$@"
  }
fi

confirm() {
  local answer
  read -r -p "$1 [y/N] " answer
  [ "$answer" = y ] || [ "$answer" = Y ]
}
