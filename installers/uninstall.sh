#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pterodactyl-installer'                                                    #
#                                                                                    #
# Copyright (C) 2018 - 2026, Vilhelm Prytz, <vilhelm@prytznet.se>                    #
#                                                                                    #
#   This program is free software: you can redistribute it and/or modify             #
#   it under the terms of the GNU General Public License as published by             #
#   the Free Software Foundation, either version 3 of the License, or                #
#   (at your option) any later version.                                              #
#                                                                                    #
#   This program is distributed in the hope that it will be useful,                  #
#   but WITHOUT ANY WARRANTY; without even the implied warranty of                   #
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the                    #
#   GNU General Public License for more details.                                     #
#                                                                                    #
#   You should have received a copy of the GNU General Public License                #
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.           #
#                                                                                    #
# https://github.com/pterodactyl-installer/pterodactyl-installer/blob/master/LICENSE #
#                                                                                    #
# This script is not associated with the official Pterodactyl Project.               #
# https://github.com/pterodactyl-installer/pterodactyl-installer                     #
#                                                                                    #
######################################################################################

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* GAGAL: tidak bisa memuat lib script" && exit 1
fi

# ------------------ Variables ----------------- #

RM_PANEL="${RM_PANEL:-true}"
RM_WINGS="${RM_WINGS:-true}"

# ---------- Uninstallation functions ---------- #

rm_panel_files() {
  step "Menghapus file panel..."
  rm -rf /var/www/pterodactyl /usr/local/bin/composer
  [ "$OS" != "centos" ] && [ -L /etc/nginx/sites-enabled/pterodactyl.conf ] && unlink /etc/nginx/sites-enabled/pterodactyl.conf
  [ "$OS" != "centos" ] && [ -f /etc/nginx/sites-available/pterodactyl.conf ] && rm -f /etc/nginx/sites-available/pterodactyl.conf
  [ "$OS" != "centos" ] && [ ! -L /etc/nginx/sites-enabled/default ] && [ -f /etc/nginx/sites-available/default ] && ln -s /etc/nginx/sites-available/default /etc/nginx/sites-enabled/default
  [ "$OS" == "centos" ] && [ -f /etc/nginx/conf.d/pterodactyl.conf ] && rm -f /etc/nginx/conf.d/pterodactyl.conf
  systemctl restart nginx
  success "File panel dihapus."
}

rm_docker_containers() {
  step "Menghapus container dan image Docker..."

  docker system prune -a -f

  success "Container dan image Docker dihapus."
}

rm_wings_files() {
  step "Menghapus file Wings..."

  systemctl disable --now wings
  [ -f /etc/systemd/system/wings.service ] && rm -rf /etc/systemd/system/wings.service

  [ -d /etc/pterodactyl ] && rm -rf /etc/pterodactyl
  [ -f /usr/local/bin/wings ] && rm -rf /usr/local/bin/wings
  [ -d /var/lib/pterodactyl ] && rm -rf /var/lib/pterodactyl
  success "File Wings dihapus."
}

rm_services() {
  step "Menghapus service..."
  systemctl disable --now pteroq
  rm -rf /etc/systemd/system/pteroq.service
  case "$OS" in
  debian | ubuntu)
    systemctl disable --now redis-server
    ;;
  centos)
    systemctl disable --now redis
    systemctl disable --now php-fpm
    rm -rf /etc/php-fpm.d/www-pterodactyl.conf
    ;;
  esac
  success "Service dihapus."
}

rm_cron() {
  step "Menghapus cron job..."
  crontab -l | grep -vF "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1" | crontab -
  success "Cron job dihapus."
}

rm_database() {
  step "Menghapus database..."
  valid_db=$(mariadb -u root -e "SELECT schema_name FROM information_schema.schemata;" 2>/dev/null | grep -v -E -- 'schema_name|information_schema|performance_schema|mysql')
  if [[ -z "$valid_db" ]]; then
    warning "Tidak ada database yang valid."
    return
  fi

  warning "Hati-hati! Database ini akan DIHAPUS!"
  if [[ "$valid_db" == *"panel"* ]]; then
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Database bernama panel terdeteksi. Apakah ini database pterodactyl? (y/N): "
    read -r is_panel
    if [[ "$is_panel" =~ [Yy] ]]; then
      DATABASE=panel
    else
      print_list "$valid_db"
    fi
  else
    print_list "$valid_db"
  fi

  while [ -z "$DATABASE" ] || [[ "$valid_db" != *"$DATABASE"* ]]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih database panel (kosongkan untuk lewati): "
    read -r database_input
    if [[ -n "$database_input" ]]; then
      if [[ "$valid_db" == *"$database_input"* ]]; then
        DATABASE="$database_input"
      else
        warning "Nama database tidak valid. Coba lagi."
      fi
    else
      break
    fi
  done

  if [[ -n "$DATABASE" ]]; then
    mariadb -u root -e "DROP DATABASE $DATABASE;" 2>/dev/null || warning "Gagal menghapus database $DATABASE."
  else
    step "Tidak ada database dipilih, dilewati."
  fi

  # Exclude usernames User and root (Hope no one uses username User)
  step "Menghapus user database..."
  valid_users=$(mariadb -u root -e "SELECT user FROM mysql.user;" 2>/dev/null | grep -v -E -- 'user|root')
  if [[ -z "$valid_users" ]]; then
    warning "Tidak ada user database yang valid."
    return
  fi

  warning "Hati-hati! User ini akan DIHAPUS!"
  if [[ "$valid_users" == *"pterodactyl"* ]]; then
    echo -en "${COLOR_YELLOW}›${COLOR_NC} User bernama pterodactyl terdeteksi. Apakah ini user pterodactyl? (y/N): "
    read -r is_user
    if [[ "$is_user" =~ [Yy] ]]; then
      DB_USER=pterodactyl
    else
      print_list "$valid_users"
    fi
  else
    print_list "$valid_users"
  fi

  while [ -z "$DB_USER" ] || [[ "$valid_users" != *"$DB_USER"* ]]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih user panel (kosongkan untuk lewati): "
    read -r user_input
    if [[ -n "$user_input" ]]; then
      if [[ "$valid_users" == *"$user_input"* ]]; then
        DB_USER=$user_input
      else
        warning "Username tidak valid. Coba lagi."
      fi
    else
      break
    fi
  done

  if [[ -n "$DB_USER" ]]; then
    mariadb -u root -e "DROP USER '$DB_USER'@'127.0.0.1';" 2>/dev/null || warning "Gagal menghapus user $DB_USER."
  else
    step "Tidak ada user dipilih, dilewati."
  fi

  mariadb -u root -e "FLUSH PRIVILEGES;" 2>/dev/null
  success "Database dan user database dihapus (jika dipilih)."
}


# --------------- Main functions --------------- #

perform_uninstall() {
  [ "$RM_PANEL" == true ] && rm_panel_files
  [ "$RM_PANEL" == true ] && rm_cron
  [ "$RM_PANEL" == true ] && rm_database
  [ "$RM_PANEL" == true ] && rm_services
  [ "$RM_WINGS" == true ] && rm_docker_containers
  [ "$RM_WINGS" == true ] && rm_wings_files

  return 0
}

# ------------------ Uninstall ----------------- #

perform_uninstall
