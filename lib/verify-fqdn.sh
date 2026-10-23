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

CHECKIP_URL="https://checkip.pterodactyl-installer.se"
DNS_SERVER="8.8.8.8"

# exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  echo "* Script ini harus dijalankan sebagai root (sudo)." 1>&2
  exit 1
fi

fail() {
  output "Record DNS ($dns_record) tidak sama dengan IP server kamu. Pastikan domain $fqdn mengarah ke IP server kamu: $ip"
  output "Kalau pakai Cloudflare, matikan proxy (awan oranye) atau jangan pakai Let's Encrypt."

  echo -en "${COLOR_YELLOW}›${COLOR_NC} Tetap lanjut (instalasi bisa rusak kalau kamu belum paham)? (y/N): "
  read -r override

  [[ ! "$override" =~ [Yy] ]] && error "Domain atau record DNS tidak valid" && exit 1
  return 0
}

dep_install() {
  update_repos true

  case "$OS" in
  ubuntu | debian)
    install_packages "dnsutils" true
    ;;
  rocky | almalinux)
    install_packages "bind-utils" true
    ;;
  esac

  return 0
}

confirm() {
  output "Script ini akan mengirim request HTTPS ke $CHECKIP_URL"
  output "Layanan cek-IP resmi dari pembuat script asli: https://checkip.pterodactyl-installer.se"
  output "- tidak menyimpan atau membagikan informasi IP ke pihak ketiga."
  output "Kalau mau pakai layanan lain, silakan ubah script-nya."

  echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Saya setuju request HTTPS ini dilakukan (y/N): "
  read -r confirm
  [[ "$confirm" =~ [Yy] ]] || (error "Pengguna tidak setuju" && false)
}

dns_verify() {
  step "Memeriksa DNS untuk $fqdn"
  ip=$(curl -4 -s $CHECKIP_URL)
  dns_record=$(dig +short @$DNS_SERVER "$fqdn" | tail -n1)
  [ "${ip}" != "${dns_record}" ] && fail
  success "DNS terverifikasi!"
}

main() {
  fqdn="$1"
  dep_install
  confirm && dns_verify
  true
}

main "$1" "$2"
