#!/bin/bash
# Usage: bash scripts/setup/setup_db_snapshots.sh [ENV_DIR]  (default /opt/dx)
# Adds a nightly `make backup` cron job for the environments you choose.

print_status() {
    echo "

======================================================
                     Status Update
------------------------------------------------------
$1
======================================================
"
}

# Function to prompt user for Y/n choice
ask_for_confirmation() {
  read -rp "$1 (Y/n): " choice
  case "$choice" in
    ""|y|Y )
      return 0  # Default to Y if user presses Enter without typing anything
      ;;
    n|N )
      return 1
      ;;
    * )
      ask_for_confirmation "$1"  # Ask again if input is not recognized
      ;;
  esac
}

env_dir="${1:-/opt/dx}"
repo_dir="$(pwd)"

print_status "Setting up MongoDB snapshots...
We will ask you if you want to set up a nightly snapshot for each environment."

add_crontab() {
  local environment="$1"
  (crontab -l 2>/dev/null; echo "0 0 * * * cd $repo_dir && make backup ENV=$environment ENV_DIR=$env_dir >> /var/log/dx-backup-$environment.log 2>&1") | crontab -
}

for environment in test staging production; do
  if ask_for_confirmation "Do you want to enable snapshots for $environment?"; then
    echo "Enabling $environment snapshots..."
    add_crontab "$environment"
  else
    echo "Skipping $environment."
  fi
done

print_status "Cron job added successfully. Snapshots are written to $repo_dir/snapshots."
