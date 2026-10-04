#!/bin/bash

set -e

######################################################################################
#                                                                                    #
# Project 'pterodactyl-installer' (modified)                                                  #
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

export GITHUB_SOURCE="master"
export SCRIPT_RELEASE="v1.0.0"
export GITHUB_BASE_URL="https://raw.githubusercontent.com/ainimuslimah10/pterodactyl-theme-free"

LOG_PATH="/var/log/nightpanel-installer.log"

# check for curl
if ! [ -x "$(command -v curl)" ]; then
  echo "* curl dibutuhkan agar script ini bisa jalan."
  echo "* pasang dulu pakai apt (Debian/Ubuntu) atau yum/dnf (CentOS/Rocky/Alma)"
  exit 1
fi

# Always remove lib.sh, before downloading it
[ -f /tmp/lib.sh ] && rm -rf /tmp/lib.sh
curl -sSL -o /tmp/lib.sh "$GITHUB_BASE_URL"/master/lib/lib.sh
# shellcheck source=lib/lib.sh
source /tmp/lib.sh

execute() {
  echo -e "\n\n* nightpanel-installer $(date) \n\n" >>$LOG_PATH

  [[ "$1" == *"canary"* ]] && export GITHUB_SOURCE="master" && export SCRIPT_RELEASE="canary"
  update_lib_source
  run_ui "${1//_canary/}" |& tee -a $LOG_PATH

  if [[ -n $2 ]]; then
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Instalasi $1 selesai. Lanjut ke instalasi $2? (y/N): "
    read -r CONFIRM
    if [[ "$CONFIRM" =~ [Yy] ]]; then
      execute "$2"
    else
      error "Instalasi $2 dibatalkan."
      exit 1
    fi
  fi
}

ask_username
welcome_popup
welcome ""

done=false
while [ "$done" == false ]; do
  options=(
    "Install Panel"
    "Install Wings"
    "Install Panel + Wings di satu mesin (Wings jalan setelah Panel)"
    # "Uninstall panel or wings\n"

    "Install Panel versi canary (versi terbaru di master, bisa saja error!)"
    "Install Wings versi canary (versi terbaru di master, bisa saja error!)"
    "Install Panel + Wings canary di satu mesin ([3] lalu [4])"
    "Uninstall Panel atau Wings (versi canary, bisa saja error!)"

    "Pasang / hapus tema Night di Panel yang sudah terinstall"
  )

  actions=(
    "panel"
    "wings"
    "panel;wings"
    # "uninstall"

    "panel_canary"
    "wings_canary"
    "panel_canary;wings_canary"
    "uninstall_canary"

    "theme"
  )

  echo ""
  output "${COLOR_MOON}Mau ngapain hari ini, @${INSTALLER_USER}?${COLOR_NC}"
  echo ""

  for i in "${!options[@]}"; do
    menu_button "$i" "${options[$i]}"
  done

  echo ""
  echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih 0-$((${#actions[@]} - 1)): "
  read -r action

  [ -z "$action" ] && error "Pilihan tidak boleh kosong" && continue

  valid_input=("$(for ((i = 0; i <= ${#actions[@]} - 1; i += 1)); do echo "${i}"; done)")
  [[ ! " ${valid_input[*]} " =~ ${action} ]] && error "Pilihan tidak valid"
  [[ " ${valid_input[*]} " =~ ${action} ]] && done=true && IFS=";" read -r i1 i2 <<<"${actions[$action]}" && execute "$i1" "$i2"
done

# Remove lib.sh, so next time the script is run the, newest version is downloaded.
rm -rf /tmp/lib.sh
