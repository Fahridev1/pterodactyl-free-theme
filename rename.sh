#!/bin/bash
# Pakai: ./rename.sh "Nama Baru" github-username nama-repo
# Contoh: ./rename.sh "FahriPanel Installer" fahridev fahripanel-installer
set -e

NAME="$1"; GH_USER="$2"; REPO="$3"
if [ -z "$NAME" ] || [ -z "$GH_USER" ] || [ -z "$REPO" ]; then
  echo "Pakai: ./rename.sh \"Nama Baru\" github-username nama-repo"; exit 1
fi
[[ "$GH_USER" =~ ^[A-Za-z0-9-]+$ ]] || { echo "Username GitHub tidak valid"; exit 1; }
[[ "$REPO" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "Nama repo tidak valid"; exit 1; }
[[ "$NAME" =~ ^[A-Za-z0-9\ ._-]+$ ]] || { echo "Nama hanya boleh huruf, angka, spasi, . _ -"; exit 1; }

SLUG=$(echo "$NAME" | tr 'A-Z' 'a-z' | tr ' ' '-')
RAW="https://raw.githubusercontent.com/$GH_USER/$REPO"

sed -i -E "s|^export BRAND_NAME=.*|export BRAND_NAME=\${BRAND_NAME:-\"$NAME\"}|; s|^export BRAND_SLUG=.*|export BRAND_SLUG=\${BRAND_SLUG:-\"$SLUG\"}|" lib/lib.sh
sed -i -E "s|raw.githubusercontent.com/[A-Za-z0-9._/-]+\"|raw.githubusercontent.com/$GH_USER/$REPO\"|" install.sh lib/lib.sh
sed -i "s|/var/log/[a-z0-9-]*installer.log|/var/log/$SLUG.log|; s|\* nightpanel-installer \\\$(date)|* $SLUG \$(date)|" install.sh
sed -i "s|USERNAME/REPO|$GH_USER/$REPO|g; s|# NightPanel Installer|# $NAME|; s|NightPanel Installer|$NAME|g" README.md
sed -i "s|nightpanel-installer|$SLUG|g" README.md

echo "Selesai! Nama: $NAME | Repo: $GH_USER/$REPO"
echo "Cek: $RAW/master/install.sh"
