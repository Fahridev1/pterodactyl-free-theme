#!/bin/bash

set -e

# Pasang / hapus tema malam di Pterodactyl Panel yang SUDAH terinstall.
# Tema dipasang lewat file CSS + JS di public/themes/night dan satu blok di wrapper.blade.php
# (dashboard & server) serta satu blok di admin.blade.php (area /admin).
#
# Aman dijalankan berulang kali (idempotent) dan tidak menimpa file lain:
#   - hanya menyentuh folder public/themes/night (folder public/themes/pterodactyl bawaan panel TIDAK disentuh)
#   - blok lama dibuang hanya kalau penanda START dan END-nya lengkap
#   - kalau ada langkah yang gagal, file blade dikembalikan seperti semula
#
# Variabel opsional:
#   PANEL_DIR=/path/ke/panel   folder panel (default /var/www/pterodactyl)
#   THEME_SRC=/path/ke/theme   pakai folder theme lokal, tanpa unduh dari GitHub
#   THEME_ACTION=install|uninstall

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
ADMIN="$PANEL_DIR/resources/views/layouts/admin.blade.php"
ADMIN_BACKUP="$ADMIN.night-backup"
MARK_START="<!-- NIGHT-THEME:START -->"
MARK_END="<!-- NIGHT-THEME:END -->"
THEME_FILES="night.css night.js night-admin.css night-admin.js bg.jpg"

WORK=""
cleanup_work() { [ -n "$WORK" ] && rm -rf "$WORK"; return 0; }
trap cleanup_work EXIT

# ---------------------------------------------------------------- helpers

# Buang blok tema dari satu file. Hanya jalan kalau START dan END sama-sama ada,
# karena "sed /START/,/END/d" tanpa END akan menghapus file sampai baris terakhir.
strip_block() {
  local file="$1" tmp
  [ -f "$file" ] || return 0
  grep -q "NIGHT-THEME:START" "$file" || return 0

  if ! grep -q "NIGHT-THEME:END" "$file"; then
    # penanda rusak: buang baris START saja, jangan hapus isi file
    warning "Penanda tema di $(basename "$file") tidak lengkap, hanya baris penanda yang dibuang."
    sed -i "/NIGHT-THEME:START/d" "$file"
    return 0
  fi

  tmp=$(mktemp)
  sed "/NIGHT-THEME:START/,/NIGHT-THEME:END/d" "$file" >"$tmp"
  # tulis dengan cat supaya pemilik & izin file blade asli tidak berubah
  cat "$tmp" >"$file"
  rm -f "$tmp"
  return 0
}

# Sisipkan isi file $2 SEBELUM baris pertama yang cocok dengan regex $3 di file $1.
# Return 1 kalau tidak ada baris yang cocok.
insert_before() {
  local file="$1" block="$2" pattern="$3" tmp
  grep -Eq "$pattern" "$file" || return 1
  tmp=$(mktemp)
  awk -v bf="$block" -v pat="$pattern" '
    $0 ~ pat && !done { while ((getline l < bf) > 0) print l; close(bf); done = 1 }
    { print }
  ' "$file" >"$tmp"
  cat "$tmp" >"$file"
  rm -f "$tmp"
}

clear_cache() {
  (cd "$PANEL_DIR" && php artisan view:clear >/dev/null 2>&1) || true
}

# Ambil satu file tema: dari THEME_SRC kalau ada, kalau tidak dari GitHub.
fetch_file() {
  local f="$1" dest="$2"
  if [ -n "${THEME_SRC:-}" ]; then
    [ -f "$THEME_SRC/$f" ] || return 1
    cp "$THEME_SRC/$f" "$dest"
  else
    curl -fsSL --retry 2 --connect-timeout 15 -o "$dest" "$GITHUB_URL/theme/$f" || return 1
  fi
  [ -s "$dest" ] || return 1
  # halaman error HTML (404 dsb) yang tersimpan sebagai .css/.js/.jpg = file rusak
  case "$f" in
    *.css | *.js) head -c 64 "$dest" | grep -qiE '^[[:space:]]*<(!doctype|html|\?xml)' && return 1 ;;
  esac
  return 0
}

# Kembalikan file blade dari salinan yang kita ambil sebelum diubah.
restore_from() {
  local saved="$1" target="$2"
  [ -f "$saved" ] && cat "$saved" >"$target"
  return 0
}

# ---------------------------------------------------------------- install

install_theme() {
  local ts block ablock w_saved a_saved
  ts=$(date +%s)
  WORK=$(mktemp -d)
  w_saved="$WORK/wrapper.saved"
  a_saved="$WORK/admin.saved"

  # 1. Unduh semua file ke folder sementara dulu. Kalau satu gagal, panel belum disentuh sama sekali.
  if [ -n "${THEME_SRC:-}" ]; then
    output "Memakai file tema lokal dari $THEME_SRC ..."
  else
    output "Mengunduh file tema dari $GITHUB_URL/theme ..."
  fi
  mkdir -p "$WORK/files"
  local f
  for f in $THEME_FILES; do
    if ! fetch_file "$f" "$WORK/files/$f"; then
      error "Gagal mengambil theme/$f (file tidak ada, kosong, atau bukan file tema yang benar)."
      output "Cek koneksi, dan pastikan folder theme sudah ada di repo GitHub: $GITHUB_URL/theme"
      exit 1
    fi
  done

  # 2. Simpan kondisi file blade sebelum diubah, untuk rollback.
  cp "$WRAPPER" "$w_saved"
  [ -f "$ADMIN" ] && cp "$ADMIN" "$a_saved"

  # 3. Siapkan backup. Backup selalu dari kondisi TANPA blok tema, dan diperbarui kalau panel
  #    sudah di-update (supaya tidak menyimpan versi lama yang sudah tidak cocok).
  strip_block "$WRAPPER"
  cp "$WRAPPER" "$BACKUP"
  if [ -f "$ADMIN" ]; then
    strip_block "$ADMIN"
    cp "$ADMIN" "$ADMIN_BACKUP"
  fi

  # 4. Pasang file tema. Hanya menyentuh public/themes/night. Folder public/themes sudah ada di
  #    panel (berisi "pterodactyl"), jadi mkdir -p dan tidak ada yang dihapus/ditimpa di luar night.
  mkdir -p "$THEME_DIR"
  for f in $THEME_FILES; do
    cp -f "$WORK/files/$f" "$THEME_DIR/$f"
    chmod 644 "$THEME_DIR/$f"
  done
  chmod 755 "$THEME_DIR"
  chown -R --reference="$PANEL_DIR/public" "$THEME_DIR" 2>/dev/null || true

  # 5. Blok untuk dashboard + server (wrapper.blade.php).
  block="$WORK/block-wrapper"
  cat >"$block" <<BLOCK
        $MARK_START
        <link rel="stylesheet" href="/themes/night/night.css?v=$ts">
        <script src="/themes/night/night.js?v=$ts" defer></script>
        $MARK_END
BLOCK
  if ! insert_before "$WRAPPER" "$block" "@include\\(['\"]layouts\\.scripts['\"]\\)" &&
     ! insert_before "$WRAPPER" "$block" "</head>"; then
    error "Titik sisip tema tidak ditemukan di wrapper.blade.php (versi panel tidak dikenal?). File dikembalikan seperti semula."
    restore_from "$w_saved" "$WRAPPER"
    exit 1
  fi
  if ! grep -q "NIGHT-THEME:START" "$WRAPPER" || ! grep -q "NIGHT-THEME:END" "$WRAPPER"; then
    error "Blok tema gagal ditulis ke wrapper.blade.php. File dikembalikan seperti semula."
    restore_from "$w_saved" "$WRAPPER"
    exit 1
  fi

  # 6. Blok untuk area admin (admin.blade.php). Kalau gagal, dashboard tetap terpasang.
  if [ -f "$ADMIN" ]; then
    ablock="$WORK/block-admin"
    cat >"$ablock" <<BLOCK
        $MARK_START
        <link rel="stylesheet" href="/themes/night/night-admin.css?v=$ts">
        <script src="/themes/night/night-admin.js?v=$ts" defer></script>
        $MARK_END
BLOCK
    if ! insert_before "$ADMIN" "$ablock" "</head>" || ! grep -q "NIGHT-THEME:END" "$ADMIN"; then
      warning "Tema admin gagal dipasang (tag </head> tidak ditemukan di admin.blade.php). Tema dashboard tetap terpasang."
      restore_from "$a_saved" "$ADMIN"
    fi
  else
    warning "File layouts/admin.blade.php tidak ditemukan, tema admin dilewati."
  fi

  clear_cache
  success "Tema Night terpasang (dashboard + admin)! Buka panel lalu tekan Ctrl+F5 untuk refresh total."
  output "Catatan: update Pterodactyl akan menimpa wrapper.blade.php dan admin.blade.php. Jalankan menu ini lagi setelah update."
}

# -------------------------------------------------------------- uninstall

uninstall_theme() {
  strip_block "$WRAPPER"
  strip_block "$ADMIN"
  rm -f "$WRAPPER.night-backup" "$ADMIN_BACKUP"
  # hanya folder milik tema; public/themes/pterodactyl bawaan panel tidak disentuh
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
  if [ ! -w "$WRAPPER" ]; then
    error "File $WRAPPER tidak bisa ditulis."
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
