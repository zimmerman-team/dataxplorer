#!/bin/bash

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

print_status() {
    echo "

======================================================
                     Status Update
------------------------------------------------------
$1
======================================================
"
}

print_status "Installing NGINX..."
sudo apt update
sudo apt install nginx -y

print_status "Installing certbot..."
sudo apt install software-properties-common -y
sudo add-apt-repository universe -y
sudo apt-get update -y
sudo apt-get install certbot python3-certbot-nginx -y

# Configure nginx: the host's nginx proxies to the containers' ports, which
# match CLIENT_PORT and SERVER_PORT in that environment's env file.
print_status "We will ask you for each of [test | staging | production]
if you want to create an NGINX configuration for that environment."
# Function to configure NGINX for a given environment
configure_nginx() {
  local config_name="$1"
  local client_port="$2"
  local server_port="$3"
  local url_var

  if ask_for_confirmation "Do you want to create an NGINX configuration for the $config_name environment?"; then
    sudo cp ./scripts/setup/nginx_host_machine/base_app "/etc/nginx/sites-available/$config_name-app"
    sudo cp ./scripts/setup/nginx_host_machine/base_server "/etc/nginx/sites-available/$config_name-server"

    read -rp "What is the base URL for the $config_name environment (without app. or server.)?: " url_var
    sudo sed -i "s/REPL_URL/$url_var/g" "/etc/nginx/sites-available/$config_name-app"
    sudo sed -i "s/REPL_PORT/$client_port/g" "/etc/nginx/sites-available/$config_name-app"
    sudo sed -i "s/REPL_URL/$url_var/g" "/etc/nginx/sites-available/$config_name-server"
    sudo sed -i "s/REPL_PORT/$server_port/g" "/etc/nginx/sites-available/$config_name-server"

    sudo ln -s "/etc/nginx/sites-available/$config_name-app" /etc/nginx/sites-enabled/
    sudo ln -s "/etc/nginx/sites-available/$config_name-server" /etc/nginx/sites-enabled/
  fi
}
# Default ports from .env.example: client, then server. Each environment has
# its own ports, so test and staging can share a server.
configure_nginx "test" "8202" "4202"
configure_nginx "staging" "8201" "4201"
configure_nginx "production" "8200" "4200"

# Restart nginx
print_status "Restarting NGINX..."
sudo service nginx restart

print_status "Setting up SSL certificates..."
if ask_for_confirmation "Do you want to set up SSL certificates for your domains?"; then
  # Set up the ssl certificate, this will require some user input.
  echo "Setting up SSL certificates..."
  sudo certbot --nginx

  echo "Setting up cron job to renew SSL certificates..."
  # update crontab with `0 5 1 * * sudo certbot renew --preferred-challenges http-01`
  cron_command="0 5 1 * * sudo certbot renew --preferred-challenges http-01"
  temp_cron_file=$(mktemp)
  echo "$cron_command" > "$temp_cron_file"
  crontab "$temp_cron_file"
  rm "$temp_cron_file"
fi

print_status "Done installing NGINX."
