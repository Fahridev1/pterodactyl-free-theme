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

# Domain name / IP
export FQDN=""

# Default MySQL credentials
export MYSQL_DB=""
export MYSQL_USER=""
export MYSQL_PASSWORD=""

# Environment
export timezone=""
export email=""
export telemetry=""

# Initial admin account
export user_email=""
export user_username=""
export user_firstname=""
export user_lastname=""
export user_password=""

# Assume SSL, will fetch different config if true
export ASSUME_SSL=false
export CONFIGURE_LETSENCRYPT=false

# Firewall
export CONFIGURE_FIREWALL=false

# ------------ User input functions ------------ #

ask_letsencrypt() {
  if [ "$CONFIGURE_UFW" == false ] && [ "$CONFIGURE_FIREWALL_CMD" == false ]; then
    warning "Let's Encrypt butuh port 80/443 terbuka! Kamu menolak pengaturan firewall otomatis, jadi pastikan port itu terbuka sendiri (kalau tertutup, instalasi akan gagal)!"
  fi

  echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Pasang HTTPS (SSL gratis) otomatis pakai Let's Encrypt? (y/N): "
  read -r CONFIRM_SSL

  if [[ "$CONFIRM_SSL" =~ [Yy] ]]; then
    CONFIGURE_LETSENCRYPT=true
    ASSUME_SSL=false
  fi
}

ask_assume_ssl() {
  output "Let's Encrypt tidak akan dipasang otomatis (kamu memilih tidak)."
  output "Kamu bisa memilih 'assume SSL': script memakai konfigurasi nginx yang sudah siap SSL Let's Encrypt, tapi sertifikatnya tidak diurus script."
  output "Kalau kamu assume SSL tapi tidak membuat sertifikatnya, panel tidak akan bisa dibuka."
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Assume SSL? (y/N): "
  read -r ASSUME_SSL_INPUT

  [[ "$ASSUME_SSL_INPUT" =~ [Yy] ]] && ASSUME_SSL=true
  true
}

ask_telemetry() {
  output "Pterodactyl Panel mengumpulkan data telemetri anonim untuk membantu pengembangan."
  output "Info lengkap: https://pterodactyl.io/panel/1.0/additional_configuration.html#telemetry"
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Aktifkan pengiriman telemetri anonim? (yes/no) [yes]: "
  read -r telemetry_input

  if [[ -z "$telemetry_input" ]] || [[ "$telemetry_input" =~ ^([Yy]|[Yy]es)$ ]]; then
    telemetry="true"
  else
    telemetry="false"
  fi
}

check_FQDN_SSL() {
  if [[ $(invalid_ip "$FQDN") == 1 && $FQDN != 'localhost' ]]; then
    SSL_AVAILABLE=true
  else
    warning "Let's Encrypt tidak bisa dipakai untuk alamat IP."
    output "Untuk memakai Let's Encrypt, kamu harus pakai nama domain yang valid."
  fi
}

main() {
  # check if we can detect an already existing installation
  if [ -d "/var/www/pterodactyl" ]; then
    warning "Panel Pterodactyl sudah terpasang di sistem ini! Script tidak boleh dijalankan berkali-kali, akan gagal!"
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Yakin mau lanjut? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Instalasi dibatalkan!"
      exit 1
    fi
  fi

  welcome "panel"

  check_os_x86_64

  # set database credentials
  section "Konfigurasi Database"
  output ""
  output "Ini adalah kredensial yang dipakai panel untuk terhubung ke database MySQL."
  output "Kamu tidak perlu membuat database sendiri,"
  output "script ini yang akan membuatkannya."
  output ""

  MYSQL_DB="-"
  while [[ "$MYSQL_DB" == *"-"* ]]; do
    required_input MYSQL_DB "Nama database (panel): " "" "panel"
    [[ "$MYSQL_DB" == *"-"* ]] && error "Nama database tidak boleh mengandung tanda hubung (-)"
  done

  MYSQL_USER="-"
  while [[ "$MYSQL_USER" == *"-"* ]]; do
    required_input MYSQL_USER "Username database (pterodactyl): " "" "pterodactyl"
    [[ "$MYSQL_USER" == *"-"* ]] && error "Username database tidak boleh mengandung tanda hubung (-)"
  done

  # MySQL password input
  rand_pw=$(gen_passwd 64)
  password_input MYSQL_PASSWORD "Password (tekan Enter untuk password acak yang aman): " "Password MySQL tidak boleh kosong" "$rand_pw"

  readarray -t valid_timezones <<<"$(curl -s "$GITHUB_URL"/configs/valid_timezones.txt)"
  output "Daftar zona waktu yang valid: $(hyperlink "https://www.php.net/manual/en/timezones.php")  (untuk WIB ketik Asia/Jakarta)"

  while [ -z "$timezone" ]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih zona waktu [Europe/Stockholm]: "
    read -r timezone_input

    array_contains_element "$timezone_input" "${valid_timezones[@]}" && timezone="$timezone_input"
    [ -z "$timezone_input" ] && timezone="Europe/Stockholm" # because köttbullar!
  done

  email_input email "Email untuk konfigurasi Let's Encrypt dan Pterodactyl: " "Email tidak boleh kosong atau tidak valid"

  # Initial admin account
  email_input user_email "Email untuk akun admin pertama: " "Email tidak boleh kosong atau tidak valid"
  required_input user_username "Username untuk akun admin pertama: " "Username tidak boleh kosong"
  required_input user_firstname "Nama depan untuk akun admin pertama: " "Nama tidak boleh kosong"
  required_input user_lastname "Nama belakang untuk akun admin pertama: " "Nama tidak boleh kosong"
  password_input user_password "Password untuk akun admin pertama: " "Password tidak boleh kosong"

  print_brake 72

  # set FQDN
  while [ -z "$FQDN" ]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Domain (FQDN) untuk panel ini (panel.contoh.com): "
    read -r FQDN
    [ -z "$FQDN" ] && error "Domain (FQDN) tidak boleh kosong"
  done

  # Check if SSL is available
  check_FQDN_SSL

  # Ask if firewall is needed
  ask_firewall CONFIGURE_FIREWALL

  # Only ask about SSL if it is available
  if [ "$SSL_AVAILABLE" == true ]; then
    # Ask if letsencrypt is needed
    ask_letsencrypt
    # If it's already true, this should be a no-brainer
    [ "$CONFIGURE_LETSENCRYPT" == false ] && ask_assume_ssl
  fi

  # verify FQDN if user has selected to assume SSL or configure Let's Encrypt
  [ "$CONFIGURE_LETSENCRYPT" == true ] || [ "$ASSUME_SSL" == true ] && bash <(curl -s "$GITHUB_URL"/lib/verify-fqdn.sh) "$FQDN"

  # ask telemetry preference
  ask_telemetry

  # summary
  summary

  # confirm installation
  echo -e -n "\n${COLOR_YELLOW}›${COLOR_NC} Konfigurasi awal selesai. Lanjut memulai instalasi? (y/N): "
  read -r CONFIRM
  if [[ "$CONFIRM" =~ [Yy] ]]; then
    run_installer "panel"
  else
    error "Instalasi dibatalkan."
    exit 1
  fi
}

summary() {
  section "Ringkasan Konfigurasi"
  kv "Panel" "Pterodactyl $PTERODACTYL_PANEL_VERSION + nginx ($OS)"
  kv "Nama database" "$MYSQL_DB"
  kv "User database" "$MYSQL_USER"
  kv "Password database" "(disembunyikan)"
  kv "Zona waktu" "$timezone"
  kv "Email" "$email"
  kv "Email admin" "$user_email"
  kv "Username admin" "$user_username"
  kv "Nama depan" "$user_firstname"
  kv "Nama belakang" "$user_lastname"
  kv "Password admin" "(disembunyikan)"
  kv "Domain / FQDN" "$FQDN"
  kv "Atur firewall" "$CONFIGURE_FIREWALL"
  kv "Let's Encrypt" "$CONFIGURE_LETSENCRYPT"
  kv "Assume SSL" "$ASSUME_SSL"
  kv "Telemetri" "$telemetry"
  echo ""
}

goodbye() {
  echo ""
  draw_box "Instalasi Panel selesai!" "" "Terima kasih sudah memakai ${BRAND_NAME}."
  echo ""

  [ "$CONFIGURE_LETSENCRYPT" == true ] && output "Panel kamu bisa dibuka di $(hyperlink "$FQDN")"
  [ "$ASSUME_SSL" == true ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Kamu memilih memakai SSL tanpa Let's Encrypt otomatis. Panel tidak akan bisa dibuka sebelum SSL dipasang."
  [ "$ASSUME_SSL" == false ] && [ "$CONFIGURE_LETSENCRYPT" == false ] && output "Panel kamu bisa dibuka di $(hyperlink "$FQDN")"

  output ""
  output "Login pakai username dan password admin yang tadi kamu isi."
  output "Web server: nginx di $OS"
  [ "$CONFIGURE_FIREWALL" == false ] && echo -e "${COLOR_YELLOW}▲${COLOR_NC} ${COLOR_RED}Catatan${COLOR_NC}: kamu belum mengatur firewall, port 80/443 (HTTP/HTTPS) harus terbuka!"
  echo ""
}

ask_theme() {
  echo -e -n "\n${COLOR_YELLOW}›${COLOR_NC} Pasang tema Night (latar malam + pop up sambutan) sekarang? (y/N): "
  read -r CONFIRM_THEME
  if [[ "$CONFIRM_THEME" =~ [Yy] ]]; then
    THEME_ACTION=install bash <(curl -sSL "$GITHUB_URL"/ui/theme.sh) || warning "Tema gagal dipasang. Bisa dicoba lagi lewat menu utama."
  fi
}

main
ask_theme
goodbye
