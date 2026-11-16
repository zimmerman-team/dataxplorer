#!/bin/bash
# Run the DX stack on this machine without Docker. Each app repo next to this
# one (make repos) runs its own `make dev`; output is labelled per service and
# Ctrl-C stops everything.
#
#   make native-setup   run `make setup` in every app repo (once)
#   make native         run the stack
#   make native only="server backend"   run some services (cms isn't in the default)
#
# Needs MongoDB and Redis. If they already run on 27017 and 6379 they're used
# as they are; otherwise this starts them, keeping their data in .native/.
# Each repo's Node version comes from its .nvmrc, through nvm if you have it.
set -uo pipefail
cd "$(dirname "$0")/.."
infra="$(pwd)"
root="$(cd .. && pwd)"
mode="${1:-run}"
services="${ONLY:-backend ai-api server client}"
NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# name port url
service_info() {
  case "$1" in
    backend) echo "4004 http://localhost:4004/health-check" ;;
    ai-api)  echo "5000 http://localhost:5000" ;;
    server)  echo "4200 http://localhost:4200/ping" ;;
    client)  echo "3000 http://localhost:3000" ;;
    cms)     echo "1337 http://localhost:1337/admin" ;;
    *)       return 1 ;;
  esac
}
folder_of() { awk -v n="$1" '$1 == n { print $3 }' repos.txt; }
port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }
label() { awk -v p="$(printf '%-8s|' "$1")" '{ print p " " $0; fflush() }'; }

# The command that runs `make <target>` in a repo, on the repo's Node version.
make_cmd() {
  local dir="$1" target="$2"
  if [ -f "$dir/.nvmrc" ] && [ -s "$NVM_DIR/nvm.sh" ]; then
    echo ". '$NVM_DIR/nvm.sh' >/dev/null && { nvm use --silent >/dev/null || { echo \"Node \$(cat .nvmrc) isn't installed: nvm install \$(cat .nvmrc)\"; exit 1; }; } && exec make $target"
  else
    echo "exec make $target"
  fi
}

problems=0
problem() { echo "  ✗ $*"; problems=$((problems + 1)); }

echo "Checking the app repos in $root:"
for s in $services; do
  service_info "$s" >/dev/null || { problem "$s: not a service (backend, ai-api, server, client, cms)"; continue; }
  dir="$root/$(folder_of "$s")"
  if [ ! -f "$dir/Makefile" ]; then
    problem "$s: no $dir with a Makefile. Run: make repos"
  elif [ "$mode" = run ] && [ ! -f "$dir/.env" ]; then
    problem "$s: not set up yet. Run: make native-setup"
  else
    echo "  ✓ $s: $dir"
  fi
done
[ "$problems" -eq 0 ] || exit 1

# ------------------------------------------------------------------- setup
if [ "$mode" = setup ]; then
  for s in $services; do
    dir="$root/$(folder_of "$s")"
    echo
    echo "== $s: make setup"
    (cd "$dir" && bash -c "$(make_cmd "$dir" setup)") || { echo "make setup failed in $dir" >&2; exit 1; }
  done
  echo
  echo "Set up. Fill in each repo's .env where you need real keys, then: make native"
  exit 0
fi

# --------------------------------------------------------------------- run
echo "Checking ports:"
for s in $services; do
  read -r port url <<< "$(service_info "$s")"
  if port_open "$port"; then problem "$s: port $port is already in use. Stop whatever runs there first."; fi
done
[ "$problems" -eq 0 ] && echo "  ✓ free"
[ "$problems" -eq 0 ] || exit 1

set -m   # every service gets its own process group, so stopping it stops its children too
stop() {
  trap - INT TERM EXIT
  echo
  echo "Stopping..."
  for pgid in $(jobs -p); do kill -TERM -- "-$pgid" 2>/dev/null; done
  wait 2>/dev/null
  exit 0
}
trap stop INT TERM EXIT

mkdir -p .native
if port_open 27017; then
  echo "MongoDB: using the one already running on 27017"
elif command -v mongod >/dev/null; then
  mkdir -p .native/mongo
  echo "MongoDB: starting it, data in .native/mongo, log in .native/mongo.log"
  mongod --dbpath .native/mongo --bind_ip 127.0.0.1 --port 27017 --logpath .native/mongo.log --logappend 2>&1 | label mongo &
else
  echo "MongoDB isn't running or installed." >&2
  echo "  macOS:  brew tap mongodb/brew && brew install mongodb-community@8.0" >&2
  echo "  Linux:  mongodb-org from MongoDB's repository, https://www.mongodb.com/docs/manual/administration/install-on-linux/" >&2
  exit 1
fi
if port_open 6379; then
  echo "Redis:   using the one already running on 6379"
elif command -v redis-server >/dev/null; then
  mkdir -p .native/redis
  echo "Redis:   starting it, data in .native/redis"
  redis-server --port 6379 --bind 127.0.0.1 --dir "$infra/.native/redis" --save "20 1" --loglevel warning 2>&1 | label redis &
else
  echo "Redis isn't running or installed." >&2
  echo "  macOS:  brew install redis" >&2
  echo "  Linux:  sudo apt install redis-server" >&2
  exit 1
fi

for s in $services; do
  dir="$root/$(folder_of "$s")"
  (cd "$dir" && bash -c "$(make_cmd "$dir" dev)") 2>&1 | label "$s" &
done

# Say when each service answers.
(
  pending="$services"
  for _ in $(seq 1 300); do
    left=""
    for s in $pending; do
      read -r port url <<< "$(service_info "$s")"
      if port_open "$port"; then echo "ready: $s  $url"; else left="$left $s"; fi
    done
    pending="$left"
    [ -z "$pending" ] && { echo "Everything is up. Ctrl-C stops it all."; exit 0; }
    sleep 2
  done
  echo "still not answering after 10 minutes:$pending"
) | label dx &

wait
