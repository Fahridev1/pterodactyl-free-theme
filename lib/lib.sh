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

# ------------------ Variables ----------------- #

# Branding (diubah otomatis oleh rename.sh)
export BRAND_NAME=${BRAND_NAME:-"NightPanel Installer"}
export BRAND_SLUG=${BRAND_SLUG:-"nightpanel-installer"}

# Versioning
export GITHUB_SOURCE=${GITHUB_SOURCE:-main}
export SCRIPT_RELEASE=${SCRIPT_RELEASE:-canary}

# Pterodactyl versions
export PTERODACTYL_PANEL_VERSION=""
export PTERODACTYL_WINGS_VERSION=""

# Path (export everything that is possible, doesn't matter that it exists already)
export PATH="$PATH:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin"

# OS
export OS=""
export OS_VER_MAJOR=""
export CPU_ARCHITECTURE=""
export ARCH=""
export SUPPORTED=false

# download URLs
export PANEL_DL_URL="https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz"
export WINGS_DL_BASE_URL="https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_"
export MARIADB_URL="https://downloads.mariadb.com/MariaDB/mariadb_repo_setup"
export GITHUB_BASE_URL=${GITHUB_BASE_URL:-"https://raw.githubusercontent.com/Fahridev1/pterodactyl-free-theme"}
export GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"

# Colors
COLOR_YELLOW='\033[1;38;5;214m' # amber lantern
COLOR_GREEN='\033[1;38;5;114m'  # grass
COLOR_RED='\033[1;38;5;203m'
COLOR_NC='\033[0m'
COLOR_BLUE='\033[38;5;75m'      # night water
COLOR_MOON='\033[1;38;5;153m'   # moonlight
COLOR_DIM='\033[2;38;5;110m'

# email input validation regex
email_regex="^(([A-Za-z0-9]+((\.|\-|\_|\+)?[A-Za-z0-9]?)*[A-Za-z0-9]+)|[A-Za-z0-9]+)@(([A-Za-z0-9]+)+((\.|\-|\_)?([A-Za-z0-9]+)+)*)+\.([A-Za-z]{2,})+$"

# Charset used to generate random passwords
password_charset='A-Za-z0-9!"#%&()*+,-./:;<=>?@[\]^_`{|}~'

# --------------------- Lib -------------------- #

lib_loaded() {
  return 0
}

# -------------- Visual functions -------------- #

output() {
  if [ -z "$1" ]; then
    echo ""
  else
    echo -e "${COLOR_BLUE}│${COLOR_NC} $1"
  fi
}

# Langkah yang sedang dikerjakan
step() {
  echo -e "  ${COLOR_YELLOW}▸${COLOR_NC} ${COLOR_MOON}$1${COLOR_NC}"
}

# Judul bagian
section() {
  local pad
  pad=$((52 - ${#1}))
  [ "$pad" -lt 3 ] && pad=3
  echo ""
  echo -e "${COLOR_BLUE}━━ ${COLOR_MOON}$1${COLOR_BLUE} $(printf '%*s' "$pad" '' | sed 's/ /━/g')${COLOR_NC}"
}

success() {
  echo -e "  ${COLOR_GREEN}✔${COLOR_NC} $1"
}

error() {
  echo ""
  echo -e "  ${COLOR_RED}✘ GAGAL${COLOR_NC}  $1" 1>&2
  echo ""
}

warning() {
  echo ""
  echo -e "  ${COLOR_YELLOW}▲ PERINGATAN${COLOR_NC}  $1"
  echo ""
}

# Baris "label : nilai" yang rata, dipakai untuk ringkasan
kv() {
  printf "  ${COLOR_BLUE}%-24s${COLOR_NC} ${COLOR_MOON}%s${COLOR_NC}\n" "$1" "$2"
}

print_brake() {
  for ((n = 0; n < $1; n++)); do
    echo -n "#"
  done
  echo ""
}

print_list() {
  print_brake 30
  for word in $1; do
    output "$word"
  done
  print_brake 30
  echo ""
}

hyperlink() {
  echo -e "\e]8;;${1}\a${1}\e]8;;\a"
}

# ----------- Night theme: banner, popup, buttons ----------- #

# Hapus karakter aneh dari username, maksimal 32 karakter
sanitize_username() {
  local clean
  clean=$(echo "$1" | sed 's/^@//' | tr -cd 'A-Za-z0-9._-' | cut -c1-32)
  echo "$clean"
}

# Tanya username (sekali saja). Bisa di-skip dengan: INSTALLER_USER=nama bash install.sh
ask_username() {
  if [ -z "${INSTALLER_USER:-}" ]; then
    local default
    default=$(sanitize_username "${SUDO_USER:-$(whoami)}")
    echo -en "${COLOR_YELLOW}›${COLOR_NC} ${COLOR_MOON}Siapa namamu / username GitHub-mu?${COLOR_NC} [${default}]: "
    read -r typed || typed=""
    INSTALLER_USER=$(sanitize_username "${typed:-$default}")
    [ -z "$INSTALLER_USER" ] && INSTALLER_USER="player"
  fi
  export INSTALLER_USER
}

# Kotak ala pop up di terminal. Argumen: baris-baris teks (ASCII saja biar rapi)
draw_box() {
  local width=0 line pad
  for line in "$@"; do
    if [ "${#line}" -gt "$width" ]; then width=${#line}; fi
  done
  echo -e "${COLOR_BLUE}  +$(printf '%*s' $((width + 4)) '' | tr ' ' '-')+${COLOR_NC}"
  for line in "$@"; do
    pad=$((width - ${#line}))
    echo -e "${COLOR_BLUE}  |${COLOR_NC}  ${COLOR_MOON}${line}${COLOR_NC}$(printf '%*s' "$pad" '')  ${COLOR_BLUE}|${COLOR_NC}"
  done
  echo -e "${COLOR_BLUE}  +$(printf '%*s' $((width + 4)) '' | tr ' ' '-')+${COLOR_NC}"
}

# Pop up sambutan: pakai whiptail (dialog beneran) kalau ada, kalau tidak pakai kotak ANSI
welcome_popup() {
  local user="${INSTALLER_USER:-player}"
  if command -v whiptail >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
    whiptail --title "$BRAND_NAME" --msgbox \
      "\nHai, selamat datang @${user}!\n\nTerima kasih sudah memakai ${BRAND_NAME}.\nTekan OK untuk lanjut ke menu instalasi." \
      12 60 2>/dev/null && return 0
  fi
  echo ""
  draw_box "Hai, selamat datang @${user}!" "" "Terima kasih sudah memakai ${BRAND_NAME}." "Siap-siap bangun panel kamu."
  echo ""
}

# Tombol menu: nomor jadi "button" berwarna
menu_button() {
  printf "  \033[48;5;24m\033[1;38;5;255m %s \033[0m  \033[38;5;153m%s\033[0m\n" "[$1]" "$2"
}

print_banner() {
  echo -e "${COLOR_DIM}      .    *      .        ${COLOR_MOON}_.._${COLOR_DIM}      .     *     .${COLOR_NC}"
  echo -e "${COLOR_DIM}   *       .          ${COLOR_MOON}.' .-'\`${COLOR_DIM}        .         *${COLOR_NC}"
  echo -e "${COLOR_YELLOW}    [*]${COLOR_DIM}       .      ${COLOR_MOON}'.__.'${COLOR_DIM}        ${COLOR_YELLOW}[*]${COLOR_NC}"
  echo -e "${COLOR_BLUE}  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${COLOR_NC}"
  echo -e "${COLOR_MOON}   ${BRAND_NAME}${COLOR_NC}  ${COLOR_DIM}@ ${SCRIPT_RELEASE}${COLOR_NC}"
  echo -e "${COLOR_BLUE}  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~${COLOR_NC}"
}

# First argument is wings / panel / neither
welcome() {
  get_latest_versions

  echo ""
  print_banner
  [ -n "${INSTALLER_USER:-}" ] && output "Halo ${COLOR_MOON}@${INSTALLER_USER}${COLOR_NC}!"
  output ""
  output "Based on pterodactyl-installer, Copyright (C) 2018 - 2026, Vilhelm Prytz"
  output "https://github.com/pterodactyl-installer/pterodactyl-installer"
  output "Script ini tidak berafiliasi dengan Pterodactyl Project resmi."
  output ""
  output "Sistem: $OS versi $OS_VER"
  if [ "$1" == "panel" ]; then
    output "Panel Pterodactyl terbaru: $PTERODACTYL_PANEL_VERSION"
  elif [ "$1" == "wings" ]; then
    output "Wings Pterodactyl terbaru: $PTERODACTYL_WINGS_VERSION"
  fi
  print_brake 50
}

# ---------------- Lib functions --------------- #

get_latest_release() {
  curl -sL "https://api.github.com/repos/$1/releases/latest" | # Get latest release from GitHub api
    grep '"tag_name":' |                                       # Get tag line
    sed -E 's/.*"([^"]+)".*/\1/'                               # Pluck JSON value
}

get_latest_versions() {
  step "Mengambil informasi rilis terbaru..."
  PTERODACTYL_PANEL_VERSION=$(get_latest_release "pterodactyl/panel")
  PTERODACTYL_WINGS_VERSION=$(get_latest_release "pterodactyl/wings")
}

update_lib_source() {
  GITHUB_URL="$GITHUB_BASE_URL/$GITHUB_SOURCE"
  rm -rf /tmp/lib.sh
  curl -sSL -o /tmp/lib.sh "$GITHUB_URL"/lib/lib.sh
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh
}

run_installer() {
  bash <(curl -sSL "$GITHUB_URL/installers/$1.sh")
}

run_ui() {
  bash <(curl -sSL "$GITHUB_URL/ui/$1.sh")
}

array_contains_element() {
  local e match="$1"
  shift
  for e; do [[ "$e" == "$match" ]] && return 0; done
  return 1
}

valid_email() {
  [[ $1 =~ ${email_regex} ]]
}

invalid_ip() {
  ip route get "$1" >/dev/null 2>&1
  echo $?
}

gen_passwd() {
  local length=$1
  local password=""
  while [ ${#password} -lt "$length" ]; do
    password=$(echo "$password""$(head -c 100 /dev/urandom | LC_ALL=C tr -dc "$password_charset")" | fold -w "$length" | head -n 1)
  done
  echo "$password"
}

# -------------------- MYSQL ------------------- #

create_db_user() {
  local db_user_name="$1"
  local db_user_password="$2"
  local db_host="${3:-127.0.0.1}"

  step "Membuat user database $db_user_name..."

  mariadb -u root -e "CREATE USER '$db_user_name'@'$db_host' IDENTIFIED BY '$db_user_password';"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  success "User database $db_user_name dibuat"
}

grant_all_privileges() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  step "Memberi semua hak akses $db_name ke $db_user_name..."

  mariadb -u root -e "GRANT ALL PRIVILEGES ON $db_name.* TO '$db_user_name'@'$db_host' WITH GRANT OPTION;"
  mariadb -u root -e "FLUSH PRIVILEGES;"

  success "Hak akses diberikan"

}

create_db() {
  local db_name="$1"
  local db_user_name="$2"
  local db_host="${3:-127.0.0.1}"

  step "Membuat database $db_name..."

  mariadb -u root -e "CREATE DATABASE $db_name;"
  grant_all_privileges "$db_name" "$db_user_name" "$db_host"

  success "Database $db_name dibuat"
}

# --------------- Package Manager -------------- #

update_repos() {
  local args=""
  
  [[ "$1" == true ]] && args="-qq"

  case "$OS" in
    ubuntu | debian)
      step "Memperbarui repositori paket..."
      if ! apt-get update -y $args; then
        error "Gagal memperbarui repositori."
        return 1
      fi
      ;;
    centos | almalinux | rockylinux)
      # Skip since these distros auto-refresh metadata
      step "Melewati pembaruan repositori (otomatis di $OS)."
      ;;
    *)
      warning "OS tidak didukung: $OS — melewati pembaruan repositori."
      ;;
  esac
}


# First argument list of packages to install, second argument for quite mode
install_packages() {
  local args=""
  if [[ $2 == true ]]; then
    case "$OS" in
    ubuntu | debian) args="-qq" ;;
    *) args="-q" ;;
    esac
  fi

  # Eval needed for proper expansion of arguments
  case "$OS" in
  ubuntu | debian)
    eval apt-get -y $args install "$1"
    ;;
  rocky | almalinux)
    eval dnf -y $args install "$1"
    ;;
  esac
}

# ------------ User input functions ------------ #

required_input() {
  local __resultvar=$1
  local result=''

  while [ -z "$result" ]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} ${2}"
    read -r result

    if [ -z "${3}" ]; then
      [ -z "$result" ] && result="${4}"
    else
      [ -z "$result" ] && error "${3}"
    fi
  done

  eval "$__resultvar="'$result'""
}

email_input() {
  local __resultvar=$1
  local result=''

  while ! valid_email "$result"; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} ${2}"
    read -r result

    valid_email "$result" || error "${3}"
  done

  eval "$__resultvar="'$result'""
}

password_input() {
  local __resultvar=$1
  local result=''
  local default="$4"

  while [ -z "$result" ]; do
    echo -en "${COLOR_YELLOW}›${COLOR_NC} ${2}"

    # modified from https://stackoverflow.com/a/22940001
    while IFS= read -r -s -n1 char; do
      [[ -z $char ]] && {
        printf '\n'
        break
      }                               # ENTER pressed; output \n and break.
      if [[ $char == $'\x7f' ]]; then # backspace was pressed
        # Only if variable is not empty
        if [ -n "$result" ]; then
          # Remove last char from output variable.
          [[ -n $result ]] && result=${result%?}
          # Erase '*' to the left.
          printf '\b \b'
        fi
      else
        # Add typed char to output variable.  [ -z "$result" ] && [ -n "
        result+=$char
        # Print '*' in its stead.
        printf '*'
      fi
    done
    [ -z "$result" ] && [ -n "$default" ] && result="$default"
    [ -z "$result" ] && error "${3}"
  done

  eval "$__resultvar="'$result'""
}

# ------------------ Firewall ------------------ #

ask_firewall() {
  local __resultvar=$1

  case "$OS" in
  ubuntu | debian)
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Atur firewall UFW secara otomatis? (y/N): "
    read -r CONFIRM_UFW

    if [[ "$CONFIRM_UFW" =~ [Yy] ]]; then
      eval "$__resultvar="'true'""
    fi
    ;;
  rocky | almalinux)
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Atur firewall-cmd secara otomatis? (y/N): "
    read -r CONFIRM_FIREWALL_CMD

    if [[ "$CONFIRM_FIREWALL_CMD" =~ [Yy] ]]; then
      eval "$__resultvar="'true'""
    fi
    ;;
  esac
}

install_firewall() {
  case "$OS" in
  ubuntu | debian)
    output ""
    section "Memasang Uncomplicated Firewall (UFW)"

    if ! [ -x "$(command -v ufw)" ]; then
      update_repos true
      install_packages "ufw" true
    fi

    ufw --force enable

    success "Firewall UFW aktif"

    ;;
  rocky | almalinux)

    output ""
    section "Memasang FirewallD"

    if ! [ -x "$(command -v firewall-cmd)" ]; then
      install_packages "firewalld" true
    fi

    systemctl --now enable firewalld >/dev/null

    success "FirewallD aktif"

    ;;
  esac
}

firewall_allow_ports() {
  case "$OS" in
  ubuntu | debian)
    for port in $1; do
      ufw allow "$port"
    done
    ufw --force reload
    ;;
  rocky | almalinux)
    for port in $1; do
      firewall-cmd --zone=public --add-port="$port"/tcp --permanent
    done
    firewall-cmd --reload -q
    ;;
  esac
}

# ---------------- System checks --------------- #

# panel x86_64 check
check_os_x86_64() {
  if [ "${ARCH}" != "amd64" ]; then
    warning "Arsitektur CPU terdeteksi: $CPU_ARCHITECTURE"
    warning "Selain 64 bit (x86_64) akan menimbulkan masalah."

    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Yakin mau lanjut? (y/N): "
    read -r choice

    if [[ ! "$choice" =~ [Yy] ]]; then
      error "Instalasi dibatalkan!"
      exit 1
    fi
  fi
}

# wings virtualization check
check_virt() {
  step "Memasang virt-what..."

  update_repos true
  install_packages "virt-what" true

  # Export sbin for virt-what
  export PATH="$PATH:/sbin:/usr/sbin"

  virt_serv=$(virt-what)

  case "$virt_serv" in
  *openvz* | *lxc*)
    warning "Jenis virtualisasi ini tidak didukung. Tanya penyedia hosting kamu apakah server ini bisa menjalankan Docker. Lanjut dengan risiko sendiri."
    echo -e -n "${COLOR_YELLOW}›${COLOR_NC} Yakin mau lanjut? (y/N): "
    read -r CONFIRM_PROCEED
    if [[ ! "$CONFIRM_PROCEED" =~ [Yy] ]]; then
      error "Instalasi dibatalkan!"
      exit 1
    fi
    ;;
  *)
    [ "$virt_serv" != "" ] && warning "Virtualisasi terdeteksi: $virt_serv"
    ;;
  esac

  if uname -r | grep -q "xxxx"; then
    error "Kernel tidak didukung."
    exit 1
  fi

  success "Sistem kompatibel dengan Docker"
}

# Exit with error status code if user is not root
if [[ $EUID -ne 0 ]]; then
  error "Script ini harus dijalankan sebagai root."
  exit 1
fi

# Detect OS
if [ -f /etc/os-release ]; then
  # freedesktop.org and systemd
  . /etc/os-release
  OS=$(echo "$ID" | awk '{print tolower($0)}')
  OS_VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
  # linuxbase.org
  OS=$(lsb_release -si | awk '{print tolower($0)}')
  OS_VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
  # For some versions of Debian/Ubuntu without lsb_release command
  . /etc/lsb-release
  OS=$(echo "$DISTRIB_ID" | awk '{print tolower($0)}')
  OS_VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
  # Older Debian/Ubuntu/etc.
  OS="debian"
  OS_VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
  # Older SuSE/etc.
  OS="SuSE"
  OS_VER="?"
elif [ -f /etc/redhat-release ]; then
  # Older Red Hat, CentOS, etc.
  OS="Red Hat/CentOS"
  OS_VER="?"
else
  # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
  OS=$(uname -s)
  OS_VER=$(uname -r)
fi

OS=$(echo "$OS" | awk '{print tolower($0)}')
OS_VER_MAJOR=$(echo "$OS_VER" | cut -d. -f1)
CPU_ARCHITECTURE=$(uname -m)

case "$CPU_ARCHITECTURE" in
x86_64)
  ARCH=amd64
  ;;
arm64 | aarch64)
  ARCH=arm64
  ;;
*)
  error "Hanya x86_64 dan arm64 yang didukung!"
  exit 1
  ;;
esac

case "$OS" in
ubuntu)
  [ "$OS_VER_MAJOR" == "22" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "24" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "26" ] && SUPPORTED=true
  export DEBIAN_FRONTEND=noninteractive
  ;;
debian)
  [ "$OS_VER_MAJOR" == "10" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "11" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "12" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "13" ] && SUPPORTED=true
  export DEBIAN_FRONTEND=noninteractive
  ;;
rocky | almalinux)
  [ "$OS_VER_MAJOR" == "8" ] && SUPPORTED=true
  [ "$OS_VER_MAJOR" == "9" ] && SUPPORTED=true
  ;;
*)
  SUPPORTED=false
  ;;
esac

# exit if not supported
if [ "$SUPPORTED" == false ]; then
  output "$OS $OS_VER belum didukung"
  error "OS tidak didukung"
  exit 1
fi
