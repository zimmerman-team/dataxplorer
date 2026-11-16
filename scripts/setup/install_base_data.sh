#!/bin/bash
# Usage: bash scripts/setup/install_base_data.sh [ENV_DIR]  (default /opt/dx)
# Loads the public sample data (make seed) into the environments you choose.

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

print_status "We will ask you for each of [test | staging | production]
if you want to prepopulate data for that environment.
Each environment's env file in $env_dir must be filled in first."
for environment in test staging production; do
  if ask_for_confirmation "Do you want to prepopulate data for the $environment environment?"; then
    make seed ENV="$environment" ENV_DIR="$env_dir"
  fi
done
echo "Done."
