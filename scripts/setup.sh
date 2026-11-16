#!/bin/bash
# Prepare a server to run DX. Run it from the repo root: bash scripts/setup.sh
# For local development you don't need this: run make dev.

# Help
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
  echo "Prepares a server to run DX. Each step is optional:"
  echo "- Installs Docker"
  echo "- Creates the env files and key folder in the env folder (default /opt/dx)"
  echo "- Sets up the Kaggle and HDX keys"
  echo "- Installs NGINX with SSL"
  echo "- Sets up nightly database snapshots and the federated sources index"
  echo "Monitoring isn't set up here: it runs on its own server."
  echo "- Loads the public sample data"
  echo ""
  echo "Usage: bash $0"
  exit 0
fi

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

cd "$(dirname "$0")/.." || exit 1

echo ""
if ask_for_confirmation "Do you want to install Docker?"; then
  . ./scripts/setup/install_docker.sh
else
  echo "Skipping Docker installation."
fi

echo ""
read -rp "Where should the env files live? [/opt/dx]: " env_dir
env_dir="${env_dir:-/opt/dx}"
sudo mkdir -p "$env_dir/secrets/backend" "$env_dir/secrets/server"
sudo chown -R "$(id -un)" "$env_dir"
chmod 700 "$env_dir/secrets"
# The backend needs both key files to exist. kaggle.json may be empty; the HDX
# file may not (the backend won't start), so its placeholder has an empty key.
touch "$env_dir/secrets/backend/kaggle.json"
[ -s "$env_dir/secrets/backend/hdx_configuration.yaml" ] || echo 'hdx_key: ""' > "$env_dir/secrets/backend/hdx_configuration.yaml"

for environment in test staging production; do
  if [ -f "$env_dir/.env.$environment" ]; then
    echo "$env_dir/.env.$environment already exists."
  elif ask_for_confirmation "Do you want to create $env_dir/.env.$environment from .env.example?"; then
    (umask 077 && cp .env.example "$env_dir/.env.$environment")
    echo "Created $env_dir/.env.$environment. Fill in its values before the first deploy."
  fi
done

echo ""
if ask_for_confirmation "Do you want to set up a connection to Kaggle?"; then
  bash ./scripts/setup/setup_kaggle.sh "$env_dir/secrets"
else
  echo "Skipping Kaggle Setup."
fi

echo ""
if ask_for_confirmation "Do you want to set up a connection to HDX?"; then
  bash ./scripts/setup/setup_hdx.sh "$env_dir/secrets"
else
  echo "Skipping HDX Setup."
fi

echo ""
if ask_for_confirmation "Do you want to install NGINX with SSL enabled?"; then
  . ./scripts/setup/install_nginx.sh
else
  echo "Skipping NGINX."
fi

echo ""
if ask_for_confirmation "Do you want to set up nightly database snapshots?"; then
  bash ./scripts/setup/setup_db_snapshots.sh "$env_dir"
else
  echo "Skipping DB Snapshot setup."
fi

echo ""
if ask_for_confirmation "Do you want to set up the nightly federated sources index?"; then
  bash ./scripts/setup/setup_cron.sh
else
  echo "Skipping the federated sources index."
fi

echo ""
if ask_for_confirmation "Do you want to prepopulate DX with our base data? (The env files must be filled in.)"; then
  bash ./scripts/setup/install_base_data.sh "$env_dir"
else
  echo "Skipping prepopulating."
fi

echo ""
echo "Setup script is done. Fill in the env files in $env_dir, then deploy with: make up ENV=<env> ENV_DIR=$env_dir"
