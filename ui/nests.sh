#!/bin/bash

set -e

# Buat nest Nodejs, Python, dan Minecraft Bedrock di Pterodactyl Panel yang SUDAH terinstall,
# lalu impor egg-nya (eggs/*.json). Nest atau egg yang sudah ada dilewati, jadi aman dijalankan ulang.
# Pakai service bawaan Panel (NestCreationService + EggImporterService), sama seperti tombol
# "Import Egg" di /admin/nests.

# Check if script is loaded, load if not or fail otherwise.
fn_exists() { declare -F "$1" >/dev/null; }
if ! fn_exists lib_loaded; then
  # shellcheck source=lib/lib.sh
  source /tmp/lib.sh || source <(curl -sSL "$GITHUB_BASE_URL/$GITHUB_SOURCE"/lib/lib.sh)
  ! fn_exists lib_loaded && echo "* GAGAL: tidak bisa memuat lib script" && exit 1
fi

PANEL_DIR="${PANEL_DIR:-/var/www/pterodactyl}"
# Isi EGG_DIR kalau mau pakai file egg lokal, bukan unduh dari GitHub
EGG_DIR="${EGG_DIR:-}"
WORK_DIR=""

# Format: "Nama Nest|Deskripsi|file egg"
NESTS=(
  "Nodejs|Egg berbasis Node.js (bot WhatsApp, bot Discord/Telegram, web app)|egg-botwa-versi-new.json"
  "Python|Egg berbasis Python (bot, script, web app)|python-generic.json"
  "Minecraft Bedrock|Server Minecraft Bedrock Edition|vanilla-bedrock.json"
)

cleanup() {
  [ -n "$WORK_DIR" ] && rm -rf "$WORK_DIR"
  return 0
}
trap cleanup EXIT

fetch_eggs() {
  local entry file
  for entry in "${NESTS[@]}"; do
    IFS='|' read -r _ _ file <<<"$entry"
    if [ -n "$EGG_DIR" ]; then
      [ -f "$EGG_DIR/$file" ] || {
        error "File egg $EGG_DIR/$file tidak ditemukan."
        exit 1
      }
      cp "$EGG_DIR/$file" "$WORK_DIR/$file"
    else
      step "Mengunduh egg $file"
      curl -fsSL -o "$WORK_DIR/$file" "$GITHUB_URL/eggs/$file" || {
        error "Gagal mengunduh eggs/$file (cek apakah folder eggs sudah di-push ke GitHub)."
        exit 1
      }
    fi
  done
}

write_php() {
  cat >"$WORK_DIR/import.php" <<'PHP'
<?php
// Dijalankan oleh ui/nests.sh. Argumen: PANEL_DIR WORK_DIR, lalu daftar "nama|deskripsi|file".
$panel = $argv[1];
$work = $argv[2];
$items = array_slice($argv, 3);

require $panel . '/vendor/autoload.php';
$app = require $panel . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Http\UploadedFile;
use Pterodactyl\Models\Egg;
use Pterodactyl\Models\Nest;
use Pterodactyl\Services\Eggs\Sharing\EggImporterService;
use Pterodactyl\Services\Nests\NestCreationService;

// Importer Panel memeriksa mime type; file JSON kadang terbaca text/plain, jadi dipaksa application/json.
class JsonUpload extends UploadedFile
{
    public function getMimeType(): ?string
    {
        return 'application/json';
    }
}

$nests = $app->make(NestCreationService::class);
$importer = $app->make(EggImporterService::class);
$failed = false;

foreach ($items as $item) {
    [$name, $description, $file] = explode('|', $item, 3);
    try {
        $nest = Nest::where('name', $name)->first();
        if ($nest) {
            echo "SKIP_NEST|$name\n";
        } else {
            $nest = $nests->handle(['name' => $name, 'description' => $description]);
            echo "NEST|$name\n";
        }

        $path = $work . '/' . $file;
        $eggName = json_decode(file_get_contents($path), true)['name'] ?? $file;
        if (Egg::where('nest_id', $nest->id)->where('name', $eggName)->exists()) {
            echo "SKIP_EGG|$name|$eggName\n";
            continue;
        }

        $importer->handle(new JsonUpload($path, $file, 'application/json', null, true), $nest->id);
        echo "EGG|$name|$eggName\n";
    } catch (\Throwable $e) {
        $failed = true;
        echo 'FAIL|' . $name . '|' . str_replace("\n", ' ', $e->getMessage()) . "\n";
    }
}

exit($failed ? 1 : 0);
PHP
}

main() {
  if [ "$EUID" -ne 0 ]; then
    error "Jalankan sebagai root."
    exit 1
  fi
  if [ ! -f "$PANEL_DIR/artisan" ]; then
    error "Panel tidak ditemukan di $PANEL_DIR (file artisan tidak ada)."
    output "Kalau panel ada di folder lain, jalankan dengan: PANEL_DIR=/path/ke/panel"
    exit 1
  fi
  if ! command -v php >/dev/null 2>&1; then
    error "PHP tidak ditemukan di server ini."
    exit 1
  fi

  section "Nest & Egg: Nodejs, Python, Minecraft Bedrock"

  WORK_DIR=$(mktemp -d)
  fetch_eggs
  write_php

  # Jalankan sebagai user pemilik Panel supaya file log/cache tidak jadi milik root (bisa bikin Panel error 500).
  local owner
  owner=$(stat -c %U "$PANEL_DIR/storage" 2>/dev/null || echo www-data)
  chmod 755 "$WORK_DIR"
  chmod 644 "$WORK_DIR"/*

  step "Membuat nest dan mengimpor egg"
  local rc=0 out kind a b
  out=$(sudo -u "$owner" php "$WORK_DIR/import.php" "$PANEL_DIR" "$WORK_DIR" "${NESTS[@]}") || rc=$?

  while IFS='|' read -r kind a b; do
    case "$kind" in
      NEST) success "Nest dibuat: $a" ;;
      SKIP_NEST) output "Nest $a sudah ada, dilewati." ;;
      EGG) success "Egg diimpor ke $a: $b" ;;
      SKIP_EGG) output "Egg \"$b\" sudah ada di nest $a, dilewati." ;;
      FAIL) error "Nest $a gagal: $b" ;;
      *) [ -n "$kind" ] && output "$kind" ;;
    esac
  done <<<"$out"

  (cd "$PANEL_DIR" && sudo -u "$owner" php artisan cache:clear >/dev/null 2>&1) || true

  if [ "$rc" -ne 0 ]; then
    error "Sebagian nest/egg gagal. Cek pesan di atas, atau impor manual lewat /admin/nests."
    exit 1
  fi
  success "Selesai! Buka /admin/nests untuk melihat hasilnya."
}

main
