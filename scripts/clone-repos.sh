#!/bin/bash
# Clone the app repos in repos.txt next to this repo, each on the branch the
# versions file says its service follows. Repos already there are left alone.
# Run it through make: make repos [ENV=test]
# Set REPOS_DIR to clone somewhere other than this repo's parent folder.
set -euo pipefail
cd "$(dirname "$0")/.."

versions="${1:?Run this through make: make repos}"
repos_dir="${REPOS_DIR:-..}"

grep -vE '^\s*(#|$)' repos.txt | while read -r name repo folder default_branch; do
  var="$(echo "$name" | tr 'a-z-' 'A-Z_')_BRANCH"
  branch="$(grep -E "^$var=" "$versions" | cut -d= -f2- || true)"
  branch="${branch:-${default_branch:-}}"
  target="$repos_dir/$folder"

  if [ -e "$target" ]; then
    echo "$folder: already there, leaving it as it is"
  elif [ -z "$branch" ]; then
    echo "$folder: $versions doesn't say which branch $name follows; skipping"
  else
    echo "$folder: cloning $repo on $branch"
    git clone --quiet --branch "$branch" "https://github.com/$repo.git" "$target"
  fi
done
