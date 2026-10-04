#!/bin/bash

set -e

# Pasang / hapus tema malam di Pterodactyl Panel yang SUDAH terinstall.
# Tema dipasang lewat file CSS + JS di public/themes/night dan satu blok di wrapper.blade.php.

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* GAGAL: tidak bisa memuat lib script" && exit 1
fi

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
THEME_DIR="$PANEL_DIR/public/themes/night"
WRAPPER="$PANEL_DIR/resources/views/templates/wrapper.blade.php"
BACKUP="$WRAPPER.night-backup"
MARK_START="<!-- NIGHT-THEME:START -->"
MARK_END="<!-- NIGHT-THEME:END -->"

remove_block() {
  sed -i "/NIGHT-THEME:START/,/NIGHT-THEME:END/d" "$WRAPPER"
}

clear_cache() {
  (cd "$PANEL_DIR" && php artisan view:clear >/dev/null 2>&1) || true
}

install_theme() {
  local ts block
  ts=$(date +%s)

  output "Mengunduh file tema dari $GITHUB_URL/theme ..."
  mkdir -p "$THEME_DIR"
  for f in night.css night.js bg.jpg; do
    curl -fsSL -o "$THEME_DIR/$f" "$GITHUB_URL/theme/$f" || {
      error "Gagal mengunduh theme/$f (cek apakah folder theme sudah di-push ke GitHub)."
      exit 1
    }
  done
  chown -R --reference="$PANEL_DIR/public" "$THEME_DIR" 2>/dev/null || true

  [ -f "$BACKUP" ] || cp "$WRAPPER" "$BACKUP"
  remove_block

  block=$(mktemp)
  cat >"$block" <<BLOCK
        $MARK_START
        <link rel="stylesheet" href="/themes/night/night.css?v=$ts">
        <script src="/themes/night/night.js?v=$ts" defer></script>
        $MARK_END
BLOCK
  awk -v bf="$block" '/@include\(.layouts.scripts.\)/ && !d { while ((getline l < bf) > 0) print l; d=1 } { print }' \
    "$WRAPPER" >"$WRAPPER.tmp" && mv "$WRAPPER.tmp" "$WRAPPER"
  rm -f "$block"
  chown --reference="$BACKUP" "$WRAPPER" 2>/dev/null || true

  if ! grep -q "NIGHT-THEME:START" "$WRAPPER"; then
    error "Gagal memasang blok tema ke wrapper.blade.php. Mengembalikan file asli."
    cp "$BACKUP" "$WRAPPER"
    exit 1
  fi

  clear_cache
  success "Tema Night terpasang! Buka panel lalu tekan Ctrl+F5 untuk refresh total."
  output "Catatan: update Pterodactyl akan menimpa wrapper.blade.php. Jalankan menu ini lagi setelah update."
}

uninstall_theme() {
  [ -f "$WRAPPER" ] && remove_block
  rm -rf "$THEME_DIR"
  rmdir "$PANEL_DIR/public/themes" 2>/dev/null || true
  clear_cache
  success "Tema Night sudah dihapus. Tekan Ctrl+F5 di browser."
}

main() {
  if [ "$EUID" -ne 0 ]; then
    error "Jalankan sebagai root."
    exit 1
  fi
  if [ ! -f "$WRAPPER" ]; then
    error "Panel tidak ditemukan di $PANEL_DIR (file $WRAPPER tidak ada)."
    output "Kalau panel ada di folder lain, jalankan dengan: PANEL_DIR=/path/ke/panel"
    exit 1
  fi

  local choice="${THEME_ACTION:-}"
  if [ -z "$choice" ]; then
    echo ""
    output "${COLOR_MOON}Tema Night untuk Panel${COLOR_NC}"
    menu_button 1 "Pasang / perbarui tema"
    menu_button 2 "Hapus tema (kembali ke tampilan asli)"
    echo ""
    echo -en "${COLOR_YELLOW}›${COLOR_NC} Pilih 1-2: "
    read -r choice
  fi

  case "$choice" in
    1 | install) install_theme ;;
    2 | uninstall) uninstall_theme ;;
    *) error "Pilihan tidak valid." ; exit 1 ;;
  esac
}

main
