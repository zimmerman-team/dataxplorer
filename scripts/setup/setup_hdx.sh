#!/bin/bash
# Usage: bash scripts/setup/setup_hdx.sh [SECRETS_DIR]  (default ./secrets)
# Writes backend/hdx_configuration.yaml, which compose mounts into the backend.

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

print_status "Setting up HDX...
You need to supply your API key.
It can be found here: https://data.humdata.org/user/<YOUR USER NAME>/api-tokens,
please hit 'CREATE API TOKEN' and then copy the key into the prompt below."

read -s -p "Please enter your HDX key (input is hidden): " hdx_key
echo

mkdir -p "$secrets_dir/backend"
(umask 077 && echo "hdx_key: $hdx_key" > "$secrets_dir/backend/hdx_configuration.yaml")
echo "Wrote $secrets_dir/backend/hdx_configuration.yaml"
