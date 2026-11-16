#!/bin/bash
# Usage: bash scripts/setup/setup_kaggle.sh [SECRETS_DIR]  (default ./secrets)
# Writes backend/kaggle.json, which compose mounts into the backend.

print_status() {
    echo "

======================================================
                     Status Update
------------------------------------------------------
$1
======================================================
"
}

secrets_dir="${1:-./secrets}"

print_status "Setting up Kaggle...
You need to supply your username and key.
They can be found here: https://www.kaggle.com/settings/account,
please hit 'create new token' under API,
and then copy the username and key into the prompts below."

read -p "Please enter your Kaggle username: " kaggle_username
read -s -p "Please enter your Kaggle key: " kaggle_key
echo

mkdir -p "$secrets_dir/backend"
(umask 077 && echo "{\"username\":\"$kaggle_username\",\"key\":\"$kaggle_key\"}" > "$secrets_dir/backend/kaggle.json")
echo "Wrote $secrets_dir/backend/kaggle.json"
