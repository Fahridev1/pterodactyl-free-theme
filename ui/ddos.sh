#!/bin/bash

set -e

# Pasang / hapus NightGuard (anti-DDoS otomatis) di Pterodactyl Panel yang SUDAH terinstall.
# Isi: rate limit nginx, pengerasan kernel, daemon auto-deteksi + auto-blokir + mode ketat.

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* GAGAL: tidak bisa memuat lib script" && exit 1
fi

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
NG_NGINX_DIR="/etc/nginx/nightguard"
NG_CONF_DIR="/etc/nightguard"
NG_CONF="$NG_CONF_DIR/nightguard.conf"
NG_BIN="/usr/local/bin/nightguard"
NG_STATE_DIR="/var/lib/nightguard"
ZONES_FILE="/etc/nginx/conf.d/nightguard-zones.conf"
REALIP_FILE="/etc/nginx/conf.d/nightguard-realip.conf"
MARK_START="# NIGHTGUARD:START"
MARK_END="# NIGHTGUARD:END"

find_site() {
  local f
  for f in "${NGINX_SITE:-}" /etc/nginx/sites-available/pterodactyl.conf /etc/nginx/conf.d/pterodactyl.conf; do
    [ -n "$f" ] && [ -f "$f" ] && echo "$f" && return 0
  done
  return 1
}

confirm() {
  local a
  echo -en "${COLOR_YELLOW}›${COLOR_NC} $1"
  read -r a
  [[ "$a" =~ [Yy] ]]
}

dl() {
  # dl <file di folder ddos/> <tujuan>
  curl -fsSL -o "$2" "$GITHUB_URL/ddos/$1" || {
    error "Gagal mengunduh ddos/$1 (cek apakah folder ddos sudah di-push ke GitHub)."
    return 1
  }
}

# set_conf KUNCI NILAI -> menulis KUNCI="NILAI" di nightguard.conf (nilai sudah divalidasi pemanggil)
set_conf() {
  local esc
  esc=$(printf '%s' "$2" | sed -e 's/[\\&|]/\\&/g')
  sed -i -E "s|^$1=.*|$1=\"$esc\"|" "$NG_CONF"
}

conf_value() { (. "$NG_CONF" 2>/dev/null && eval "echo \"\${$1}\""); }

remove_site_block() { sed -i "\|$MARK_START|,\|$MARK_END|d" "$1"; }

setup_cloudflare_realip() {
  local v4 v6 r tmp
  v4=$(curl -fsS -m 15 https://www.cloudflare.com/ips-v4) && v6=$(curl -fsS -m 15 https://www.cloudflare.com/ips-v6) || {
    error "Tidak bisa mengambil daftar IP Cloudflare. Cek koneksi internet server."
    return 1
  }
  tmp=$(mktemp)
  {
    echo "# dikelola NightGuard - IP Cloudflare (jalankan menu pasang/perbarui lagi untuk menyegarkan)"
    for r in $v4 $v6; do
      [[ "$r" =~ ^[0-9a-fA-F:.]+/[0-9]+$ ]] && echo "set_real_ip_from $r;"
    done
    echo "real_ip_header CF-Connecting-IP;"
  } >"$tmp"
  mv "$tmp" "$REALIP_FILE"
  chmod 644 "$REALIP_FILE"
}

rollback_nginx() {
  local site=$1
  [ -f "$site.nightguard-backup" ] && cp "$site.nightguard-backup" "$site"
  rm -f "$ZONES_FILE" "$REALIP_FILE"
  rm -rf "$NG_NGINX_DIR"
}

install_guard() {
  local site first=true cf=false wl="" my_ip="" hook="" token="" zone=""
  local re_wl='^[0-9a-fA-F:./ ]*$'

  site=$(find_site) || {
    error "File nginx panel tidak ditemukan (sites-available/pterodactyl.conf atau conf.d/pterodactyl.conf)."
    output "Kalau lokasinya beda, jalankan dengan: NGINX_SITE=/path/ke/config.conf"
    exit 1
  }
  command -v nginx >/dev/null || { error "nginx belum terpasang."; exit 1; }
  [ -f "$NG_CONF" ] && first=false

  if [ "$first" == true ]; then
    section "Pengaturan NightGuard"
    if confirm "Panel kamu di belakang Cloudflare (proxy awan oranye)? (y/N): "; then cf=true; fi

    [ -n "${SSH_CLIENT:-}" ] && my_ip=${SSH_CLIENT%% *}
    output "IP yang TIDAK boleh pernah dibatasi/diblokir (IP kamu sendiri, kantor, dll)."
    output "IP node Wings dan IP server ini otomatis dikecualikan."
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Whitelist IP, pisahkan spasi [${my_ip:-kosong}]: "
    read -r wl
    wl=${wl:-$my_ip}
    if ! [[ "$wl" =~ $re_wl ]]; then
      error "Format whitelist tidak valid (hanya angka, titik, titik dua, garis miring, spasi)."
      exit 1
    fi

    echo -en "${COLOR_YELLOW}›${COLOR_NC} Discord webhook untuk notifikasi serangan (kosongkan kalau tidak perlu): "
    read -r hook
    if [ -n "$hook" ] && ! [[ "$hook" =~ ^https://[A-Za-z0-9./_?=\&%-]+$ ]]; then
      error "URL webhook tidak valid."
      exit 1
    fi

    if [ "$cf" == true ]; then
      output "Opsional: NightGuard bisa otomatis menyalakan \"Under Attack Mode\" Cloudflare saat serangan."
      echo -en "${COLOR_YELLOW}›${COLOR_NC} Cloudflare API token (kosongkan untuk lewati): "
      read -r token
      if [ -n "$token" ]; then
        [[ "$token" =~ ^[A-Za-z0-9_-]+$ ]] || { error "Token tidak valid."; exit 1; }
        echo -en "${COLOR_YELLOW}›${COLOR_NC} Cloudflare Zone ID: "
        read -r zone
        [[ "$zone" =~ ^[a-f0-9]{32}$ ]] || { error "Zone ID harus 32 karakter hex."; exit 1; }
      fi
    fi
  fi

  section "Memasang paket pendukung"
  update_repos true
  case "$OS" in
    ubuntu | debian) install_packages "ipset iptables iproute2 curl" true ;;
    rocky | almalinux) install_packages "ipset iptables-nft iproute curl" true ;;
  esac
  success "Paket terpasang"

  section "Memasang NightGuard"
  step "Mengunduh komponen dari $GITHUB_URL/ddos ..."
  mkdir -p "$NG_NGINX_DIR" "$NG_CONF_DIR" "$NG_STATE_DIR"
  dl nightguard.sh "$NG_BIN.new" || exit 1
  bash -n "$NG_BIN.new" || { error "Skrip yang diunduh rusak."; rm -f "$NG_BIN.new"; exit 1; }
  chmod 755 "$NG_BIN.new" && mv "$NG_BIN.new" "$NG_BIN"
  dl nginx-zones.conf "$ZONES_FILE" || exit 1
  dl nginx-server.conf "$NG_NGINX_DIR/server.conf" || exit 1
  dl profile-normal.conf "$NG_NGINX_DIR/profile-normal.conf" || exit 1
  dl profile-strict.conf "$NG_NGINX_DIR/profile-strict.conf" || exit 1
  cp "$NG_NGINX_DIR/profile-normal.conf" "$NG_NGINX_DIR/profile.conf"
  [ -f "$NG_NGINX_DIR/deny.conf" ] || echo "# dikelola NightGuard" >"$NG_NGINX_DIR/deny.conf"
  [ -f "$NG_NGINX_DIR/whitelist.list" ] || echo "127.0.0.1 1;" >"$NG_NGINX_DIR/whitelist.list"
  dl nightguard.service /etc/systemd/system/nightguard.service || exit 1
  dl sysctl-nightguard.conf /etc/sysctl.d/99-nightguard.conf || exit 1

  if [ "$first" == true ]; then
    dl nightguard.conf "$NG_CONF" || exit 1
    chmod 600 "$NG_CONF"
    set_conf PANEL_DIR "$PANEL_DIR"
    set_conf WHITELIST "127.0.0.1 ::1 $wl"
    set_conf CF_MODE "$cf"
    [ "$cf" == true ] && set_conf BAN_BACKEND "nginx"
    [ -n "$hook" ] && set_conf DISCORD_WEBHOOK "$hook"
    [ -n "$token" ] && set_conf CF_API_TOKEN "$token" && set_conf CF_ZONE_ID "$zone"
  else
    output "Konfigurasi lama dipertahankan di $NG_CONF"
  fi
  [ "$(conf_value CF_MODE)" == "true" ] && cf=true

  if [ "$cf" == true ]; then
    step "Mengambil daftar IP Cloudflare (real IP pengunjung)..."
    setup_cloudflare_realip || { rollback_nginx "$site"; exit 1; }
  else
    rm -f "$REALIP_FILE"
  fi

  step "Menyisipkan rate limit ke $site ..."
  [ -f "$site.nightguard-backup" ] || cp "$site" "$site.nightguard-backup"
  remove_site_block "$site"
  awk -v s="$MARK_START" -v e="$MARK_END" '
    { print }
    /^[[:space:]]*root[[:space:]]+[^;]*\/public;/ {
      print "    " s
      print "    include /etc/nginx/nightguard/server.conf;"
      print "    " e
    }' "$site" >"$site.nightguard-tmp" && cat "$site.nightguard-tmp" >"$site" && rm -f "$site.nightguard-tmp"

  if ! grep -q "NIGHTGUARD:START" "$site"; then
    rollback_nginx "$site"
    error "Baris 'root ...;' tidak ditemukan di $site. Konfigurasi dikembalikan seperti semula."
    exit 1
  fi

  if ! nginx -t >/dev/null 2>&1; then
    nginx -t 2>&1 | tail -n 5
    rollback_nginx "$site"
    error "Konfigurasi nginx tidak valid. Semua perubahan dikembalikan seperti semula."
    exit 1
  fi
  success "Konfigurasi nginx valid"

  step "Mengeraskan kernel (SYN cookies, anti-spoofing)..."
  sysctl -q -p /etc/sysctl.d/99-nightguard.conf >/dev/null 2>&1 || warning "Sebagian pengaturan kernel tidak bisa diterapkan (normal di VPS tertentu)."

  cat >/etc/logrotate.d/nightguard <<'LOGR'
/var/log/nightguard.log {
    weekly
    rotate 4
    compress
    missingok
    notifempty
    copytruncate
}
LOGR

  step "Menyalakan layanan NightGuard..."
  systemctl daemon-reload
  systemctl enable nightguard >/dev/null 2>&1
  systemctl restart nightguard
  sleep 3
  if systemctl is-active --quiet nightguard; then
    success "NightGuard aktif dan memantau panel"
  else
    warning "Layanan belum aktif. Cek: journalctl -u nightguard -n 30"
  fi

  echo ""
  draw_box "NightGuard terpasang!" "" "Auto-deteksi DDoS aktif 24 jam."
  echo ""
  kv "Cek kondisi" "nightguard status"
  kv "Daftar IP diblokir" "nightguard list"
  kv "Buka blokir" "nightguard unban IP"
  kv "Ubah ambang" "$NG_CONF"
  kv "Log" "/var/log/nightguard.log"
  echo ""
  output "Dashboard admin (tema Night) otomatis menampilkan status proteksi."
  output "Perlindungan mencakup web panel (port 80/443), bukan port game server Wings."
  output "Untuk serangan volumetrik besar, tetap aktifkan proteksi DDoS dari provider/Cloudflare."
}

status_guard() {
  if [ -x "$NG_BIN" ]; then
    echo ""
    "$NG_BIN" status || true
    echo ""
    output "IP yang sedang diblokir:"
    "$NG_BIN" list || true
  else
    error "NightGuard belum terpasang."
  fi
}

uninstall_guard() {
  local site cmd ipset_name
  systemctl disable --now nightguard >/dev/null 2>&1 || true

  if site=$(find_site); then
    remove_site_block "$site"
  fi
  rm -f "$ZONES_FILE" "$REALIP_FILE"
  rm -rf "$NG_NGINX_DIR"
  if command -v nginx >/dev/null; then
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx >/dev/null 2>&1 || true
    else
      warning "nginx -t gagal setelah penghapusan. Cek konfigurasi, backup ada di ${site:-config}.nightguard-backup"
    fi
  fi

  for pair in "iptables nightguard" "ip6tables nightguard6"; do
    read -r cmd ipset_name <<<"$pair"
    command -v "$cmd" >/dev/null || continue
    while "$cmd" -D INPUT -p tcp -m multiport --dports 80,443 -m set --match-set "$ipset_name" src -j DROP 2>/dev/null; do :; done
  done
  command -v ipset >/dev/null && { ipset destroy nightguard 2>/dev/null || true; ipset destroy nightguard6 2>/dev/null || true; }

  rm -f "$NG_BIN" /etc/systemd/system/nightguard.service /etc/sysctl.d/99-nightguard.conf /etc/logrotate.d/nightguard
  rm -f "$PANEL_DIR/public/themes/night/ddos-status.json"
  rm -rf "$NG_CONF_DIR" "$NG_STATE_DIR"
  systemctl daemon-reload
  success "NightGuard dihapus. (Pengaturan kernel kembali normal setelah reboot.)"
}

main() {
  if [ "$EUID" -ne 0 ]; then
    error "Jalankan sebagai root."
    exit 1
  fi
  if [ ! -d "$PANEL_DIR" ]; then
    error "Panel tidak ditemukan di $PANEL_DIR."
    output "Kalau panel ada di folder lain, jalankan dengan: PANEL_DIR=/path/ke/panel"
    exit 1
  fi

  local choice="${GUARD_ACTION:-}"
  if [ -z "$choice" ]; then
    echo ""
    output "${COLOR_MOON}NightGuard - anti-DDoS otomatis untuk Panel${COLOR_NC}"
    menu_button 1 "Pasang / perbarui NightGuard"
    menu_button 2 "Lihat status & IP yang diblokir"
    menu_button 3 "Hapus NightGuard"
    echo ""
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih 1-3: "
    read -r choice
  fi

  case "$choice" in
    1 | install) install_guard ;;
    2 | status) status_guard ;;
    3 | uninstall) uninstall_guard ;;
    *) error "Pilihan tidak valid."; exit 1 ;;
  esac
}

main
