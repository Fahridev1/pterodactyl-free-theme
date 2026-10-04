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

# Install mariadb
export INSTALL_MARIADB=false

# Firewall
export CONFIGURE_FIREWALL=false

# SSL (Let's Encrypt)
export CONFIGURE_LETSENCRYPT=false
export FQDN=""
export EMAIL=""

# Database host
export CONFIGURE_DBHOST=false
export CONFIGURE_DB_FIREWALL=false
export MYSQL_DBHOST_HOST="127.0.0.1"
export MYSQL_DBHOST_USER="pterodactyluser"
export MYSQL_DBHOST_PASSWORD=""

# ------------ User input functions ------------ #

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    warning "Let's Encrypt butuh port 80/443 terbuka! Kamu menolak pengaturan firewall otomatis, jadi pastikan port itu terbuka sendiri (kalau tertutup, instalasi akan gagal)!"
  fi

  warning "Let's Encrypt tidak bisa dipakai dengan alamat IP! Harus berupa domain (FQDN), misalnya node.contoh.com."

  echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Pasang HTTPS (SSL gratis) otomatis pakai Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
  fi
}

ask_database_user() {
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Buatkan user otomatis untuk database host? (y/N): "
  read -r CONFIRM_DBHOST

  if [[ "$CONFIRM_DBHOST" =~ [Yy] ]]; then
    ask_database_external
    CONFIGURE_DBHOST=true
  fi
}

ask_database_external() {
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Izinkan MySQL diakses dari luar? (y/N): "
  read -r CONFIRM_DBEXTERNAL

  if [[ "$CONFIRM_DBEXTERNAL" =~ [Yy] ]]; then
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Alamat panel (kosongkan untuk semua alamat): "
    read -r CONFIRM_DBEXTERNAL_HOST
    if [ "$CONFIRM_DBEXTERNAL_HOST" == "" ]; then
      MYSQL_DBHOST_HOST="%"
    else
      MYSQL_DBHOST_HOST="$CONFIRM_DBEXTERNAL_HOST"
    fi
    [ "$CONFIGURE_FIREWALL" == true ] && ask_database_firewall
    return 0
  fi
}

ask_database_firewall() {
  warning "Membuka port 3306 (MySQL) bisa berisiko untuk keamanan, kecuali kamu paham yang kamu lakukan!"
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Buka akses masuk ke port 3306? (y/N): "
  read -r CONFIRM_DB_FIREWALL
  if [[ "$CONFIRM_DB_FIREWALL" =~ [Yy] ]]; then
    CONFIGURE_DB_FIREWALL=true
  fi
}

####################
## MAIN FUNCTIONS ##
####################

main() {
  # check if we can detect an already existing installation
  if [ -d "/etc/pterodactyl" ]; then
    warning "Wings Pterodactyl sudah terpasang di sistem ini! Script tidak boleh dijalankan berkali-kali, akan gagal!"
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Yakin mau lanjut? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Instalasi dibatalkan!"
      exit 1
    fi
  fi

  welcome "wings"

  check_virt

  echo ""
  output "Installer ini akan memasang Docker, dependensi Wings, dan Wings itu sendiri."
  output "Setelah selesai, kamu masih harus membuat node di panel lalu menaruh"
  output "file konfigurasinya di node ini secara manual. Panduan resmi:"
  output "$(hyperlink 'https://pterodactyl.io/wings/1.0/installing.html#configure')"
  echo ""
  echo -e "${COLOR_YELLOW}▲${COLOR_NC} ${COLOR_RED}Catatan${COLOR_NC}: Wings tidak dijalankan otomatis (hanya dipasang sebagai service systemd)."
  echo -e "${COLOR_YELLOW}▲${COLOR_NC} ${COLOR_RED}Catatan${COLOR_NC}: swap (untuk Docker) tidak diaktifkan otomatis."
  print_brake 42

  ask_firewall CONFIGURE_FIREWALL

  ask_database_user

  if [ "$CONFIGURE_DBHOST" == true ]; then
    type mysql >/dev/null 2>&1 && HAS_MYSQL=true || HAS_MYSQL=false

    if [ "$HAS_MYSQL" == false ]; then
      INSTALL_MARIADB=true
    fi

    MYSQL_DBHOST_USER="-"
    while [[ "$MYSQL_DBHOST_USER" == *"-"* ]]; do
      required_input MYSQL_DBHOST_USER "Username database host (pterodactyluser): " "" "pterodactyluser"
      [[ "$MYSQL_DBHOST_USER" == *"-"* ]] && error "Username database tidak boleh mengandung tanda hubung (-)"
    done

    password_input MYSQL_DBHOST_PASSWORD "Password database host: " "Password tidak boleh kosong"
  fi

  ask_letsencrypt

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    while [ -z "$FQDN" ]; do
      echo -en "${COLOR_YELLOW}›${COLOR_NC} Domain (FQDN) untuk Let's Encrypt (node.contoh.com): "
      read -r FQDN

      ASK=false

      [ -z "$FQDN" ] && error "Domain (FQDN) tidak boleh kosong"                                                            # check if FQDN is empty
      bash <(curl -s "$GITHUB_URL"/lib/verify-fqdn.sh) "$FQDN" || ASK=true                                      # check if FQDN is valid
      [ -d "/etc/letsencrypt/live/$FQDN/" ] && error "Sertifikat untuk domain ini sudah ada!" && ASK=true # check if cert exists

      [ "$ASK" == true ] && FQDN=""
      [ "$ASK" == true ] && echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Tetap pasang HTTPS otomatis pakai Let's Encrypt? (y/N): "
      [ "$ASK" == true ] && read -r CONFIRM_SSL

      if [[ ! "$CONFIRM_SSL" =~ [Yy] ]] && [ "$ASK" == true ]; then
        CONFIGURE_LETSENCRYPT=false
        FQDN=""
      fi
    done
  fi

  if [ "$CONFIGURE_LETSENCRYPT" == true ]; then
    # set EMAIL
    while ! valid_email "$EMAIL"; do
      echo -en "${COLOR_YELLOW}›${COLOR_NC} Email untuk Let's Encrypt: "
      read -r EMAIL

      valid_email "$EMAIL" || error "Email tidak boleh kosong atau tidak valid"
    done
  fi

  echo -en "${COLOR_YELLOW}›${COLOR_NC} Lanjut memulai instalasi? (y/N): "

  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "wings"
  else
    error "Instalasi dibatalkan."
    exit 1
  fi
}

function goodbye {
  echo ""
  draw_box "Instalasi Wings selesai!" "" "Terima kasih sudah memakai ${BRAND_NAME}."
  echo ""
  output "Langkah selanjutnya: hubungkan Wings ke panel kamu."
  output "Panduan resmi: $(hyperlink 'https://pterodactyl.io/wings/1.0/installing.html#configure')"
  output ""
  output "Caranya, pilih salah satu:"
  output "  1. Salin file konfigurasi dari panel ke /etc/pterodactyl/config.yml"
  output "  2. Atau klik tombol \"auto deploy\" di panel lalu paste perintahnya di terminal ini"
  output ""
  output "Setelah itu, jalankan Wings manual untuk memastikan semuanya jalan:"
  output ""
  output "    ${COLOR_MOON}sudo wings${COLOR_NC}"
  output ""
  output "Kalau sudah jalan, tekan CTRL+C lalu jalankan sebagai service:"
  output ""
  output "    ${COLOR_MOON}systemctl start wings${COLOR_NC}"
  output ""
  echo -e "${COLOR_YELLOW}▲${COLOR_NC} ${COLOR_RED}Catatan${COLOR_NC}: sebaiknya aktifkan swap (untuk Docker, baca dokumentasi resminya)."
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "${COLOR_YELLOW}▲${COLOR_NC} ${COLOR_RED}Catatan${COLOR_NC}: kamu belum mengatur firewall, port 8080 dan 2022 harus terbuka."
  echo ""
}

# run script
main
goodbye
