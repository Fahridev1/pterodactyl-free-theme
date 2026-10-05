#!/bin/bash
# NightGuard - auto-deteksi dan mitigasi DDoS untuk Pterodactyl Panel (nginx).
#
#   nightguard run              jalankan daemon (dipakai systemd)
#   nightguard status           ringkasan kondisi saat ini
#   nightguard list             daftar IP yang sedang diblokir
#   nightguard ban IP [detik]   blokir manual (bawaan 86400 detik)
#   nightguard unban IP         buka blokir
#   nightguard attack | calm    paksa mode serangan / normal (untuk uji coba)
#
# Cara kerja: nginx membatasi request (rate limit) dan mencatat setiap penolakan.
# Daemon membaca catatan itu + jumlah koneksi/SYN_RECV, memblokir IP pelanggar,
# lalu menaikkan ke "mode ketat" otomatis saat serangan terdeteksi dan
# menurunkannya lagi setelah tenang.

CONF="${NIGHTGUARD_CONF:-/etc/nightguard/nightguard.conf}"
STATE_DIR="/var/lib/nightguard"
LOG_FILE="/var/log/nightguard.log"
NG_DIR="/etc/nginx/nightguard"
NGINX_LOG="/var/log/nginx/nightguard.log"
BANS="$STATE_DIR/bans.db"        # ip kadaluarsa_epoch alasan
STRIKES="$STATE_DIR/strikes.db"  # ip jumlah_pelanggaran terakhir_epoch
NODES="$STATE_DIR/nodes.list"    # IP node Wings (otomatis dari database panel)
KV="$STATE_DIR/status.kv"

# ---- nilai bawaan (timpa lewat /etc/nightguard/nightguard.conf) ----
PANEL_DIR="/var/www/pterodactyl"
INTERVAL=5                  # detik per siklus pemeriksaan
CONN_PER_IP_BAN=80          # koneksi simultan dari 1 IP -> blokir
HIT_BAN=100                 # skor penolakan rate-limit (meluruh) -> blokir
TOTAL_CONN_ATTACK=700       # total koneksi ke 80/443 -> serangan
SYN_RECV_ATTACK=150         # koneksi setengah jadi (SYN flood) -> serangan
OFFENDERS_ATTACK=15         # jumlah IP pelanggar bersamaan -> serangan
EVENTS_ATTACK=400           # penolakan rate-limit per siklus -> serangan
CALM_CYCLES=12              # siklus tenang berturut-turut sebelum mode normal
MIN_ATTACK_HOLD=120         # detik minimum bertahan di mode ketat
MAX_BANS_PER_CYCLE=300
BAN_TIMES="3600 21600 86400 604800"   # 1 jam, 6 jam, 1 hari, 7 hari (naik tiap pelanggaran ulang)
WHITELIST="127.0.0.1 ::1"
BAN_BACKEND="ipset"         # ipset (firewall) atau nginx (deny list)
CF_MODE="false"             # true kalau panel di belakang Cloudflare
DISCORD_WEBHOOK=""
CF_API_TOKEN=""
CF_ZONE_ID=""

load_conf() {
  # shellcheck source=/dev/null
  [ -f "$CONF" ] && . "$CONF"
}

log() { echo "$(date '+%F %T') $*" >>"$LOG_FILE"; }

# ------------------------------ validasi IP ------------------------------ #

valid_ip() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && return 0
  [[ "$1" == *:* && "$1" =~ ^[0-9a-fA-F:]+$ ]] && return 0
  return 1
}

valid_cidr() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && return 0
  [[ "$1" == *:*/* && "$1" =~ ^[0-9a-fA-F:]+/[0-9]{1,3}$ ]] && return 0
  return 1
}

ip2int() {
  local IFS=.
  local a b c d
  read -r a b c d <<<"$1"
  echo $(((a << 24) + (b << 16) + (c << 8) + d))
}

is_whitelisted() {
  local ip=$1 w net bits mask
  for w in $WHITELIST $NODE_IPS; do
    [ "$w" = "$ip" ] && return 0
    if [[ "$w" == */* && "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ && "${w%/*}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      net=${w%/*}
      bits=${w#*/}
      mask=$(((0xFFFFFFFF << (32 - bits)) & 0xFFFFFFFF))
      [ $(($(ip2int "$ip") & mask)) -eq $(($(ip2int "$net") & mask)) ] && return 0
    fi
  done
  return 1
}

# ----------------------- whitelist untuk nginx (geo) ---------------------- #

gen_whitelist() {
  local tmp w
  tmp=$(mktemp "$NG_DIR/.wl.XXXXXX")
  {
    echo "# dikelola NightGuard - jangan diedit manual"
    for w in $WHITELIST $NODE_IPS; do
      if valid_ip "$w" || valid_cidr "$w"; then echo "$w 1;"; fi
    done
  } >"$tmp"
  if ! cmp -s "$tmp" "$NG_DIR/whitelist.list"; then
    chmod 644 "$tmp" && mv "$tmp" "$NG_DIR/whitelist.list"
    NGINX_DIRTY=1
  else
    rm -f "$tmp"
  fi
}

# ------------------------------ nginx helpers ----------------------------- #

nginx_reload() {
  if nginx -t >/dev/null 2>&1; then
    systemctl reload nginx >/dev/null 2>&1 || nginx -s reload >/dev/null 2>&1
  else
    log "nginx -t GAGAL, reload dibatalkan (cek konfigurasi)"
  fi
  NGINX_DIRTY=0
}

set_profile() {
  # $1 = normal | strict
  if ! cmp -s "$NG_DIR/profile-$1.conf" "$NG_DIR/profile.conf"; then
    cp "$NG_DIR/profile-$1.conf" "$NG_DIR/profile.conf"
    NGINX_DIRTY=1
  fi
}

nginx_deny_sync() {
  local tmp
  tmp=$(mktemp "$NG_DIR/.deny.XXXXXX")
  {
    echo "# dikelola NightGuard - jangan diedit manual"
    awk -v now="$NOW" '$2 > now { print "deny " $1 ";" }' "$BANS" | tail -n 5000
  } >"$tmp"
  if ! cmp -s "$tmp" "$NG_DIR/deny.conf"; then
    chmod 644 "$tmp" && mv "$tmp" "$NG_DIR/deny.conf"
    NGINX_DIRTY=1
  else
    rm -f "$tmp"
  fi
}

# ------------------------------ ban backend ------------------------------- #

detect_backend() {
  BACKEND="nginx"
  if [ "$BAN_BACKEND" = "ipset" ] && [ "$CF_MODE" != "true" ] &&
    command -v ipset >/dev/null && command -v iptables >/dev/null; then
    BACKEND="ipset"
  fi
}

fw_rule() {
  local cmd=$1 set=$2
  command -v "$cmd" >/dev/null || return 0
  "$cmd" -C INPUT -p tcp -m multiport --dports 80,443 -m set --match-set "$set" src -j DROP 2>/dev/null ||
    "$cmd" -I INPUT 1 -p tcp -m multiport --dports 80,443 -m set --match-set "$set" src -j DROP 2>/dev/null
}

fw_setup() {
  ipset create nightguard hash:ip family inet timeout 0 maxelem 262144 -exist 2>/dev/null
  ipset create nightguard6 hash:ip family inet6 timeout 0 maxelem 262144 -exist 2>/dev/null
  fw_rule iptables nightguard
  fw_rule ip6tables nightguard6
}

fw_ban() {
  if [[ "$1" == *:* ]]; then
    ipset add nightguard6 "$1" timeout "$2" -exist 2>/dev/null
  else
    ipset add nightguard "$1" timeout "$2" -exist 2>/dev/null
  fi
}

fw_unban() {
  ipset del nightguard "$1" 2>/dev/null
  ipset del nightguard6 "$1" 2>/dev/null
}

# ------------------------------- ban state -------------------------------- #

strike_count() {
  awk -v ip="$1" -v now="$NOW" -v win=604800 '$1 == ip && now - $3 < win { print $2; f = 1 } END { if (!f) print 0 }' "$STRIKES"
}

strike_inc() {
  local ip=$1 tmp
  if grep -q "^$ip " "$STRIKES" 2>/dev/null; then
    tmp=$(mktemp "$STATE_DIR/.st.XXXXXX")
    awk -v ip="$ip" -v now="$NOW" -v win=604800 '
      $1 == ip { c = (now - $3 < win) ? $2 + 1 : 1; print ip, c, now; next } { print }' "$STRIKES" >"$tmp" && mv "$tmp" "$STRIKES"
  else
    echo "$ip 1 $NOW" >>"$STRIKES"
  fi
}

is_banned() {
  awk -v ip="$1" -v now="$NOW" '$1 == ip && $2 > now { f = 1 } END { exit !f }' "$BANS"
}

# ban_ip IP ALASAN [DURASI_DETIK]  (tanpa DURASI = eskalasi otomatis, whitelist dihormati)
ban_ip() {
  local ip=$1 reason=$2 dur=$3 s idx
  local -a T
  valid_ip "$ip" || return 1
  if [ -z "$dur" ]; then
    is_whitelisted "$ip" && return 0
    is_banned "$ip" && return 0
    read -ra T <<<"$BAN_TIMES"
    s=$(strike_count "$ip")
    idx=$s
    [ "$idx" -ge "${#T[@]}" ] && idx=$((${#T[@]} - 1))
    dur=${T[$idx]}
    strike_inc "$ip"
  fi
  echo "$ip $((NOW + dur)) $reason" >>"$BANS"
  if [ "$BACKEND" = "ipset" ]; then
    fw_ban "$ip" "$dur"
  else
    nginx_deny_sync
  fi
  log "BLOKIR $ip selama ${dur}s ($reason)"
  BANS_THIS_CYCLE=$((BANS_THIS_CYCLE + 1))
}

unban_ip() {
  local tmp
  tmp=$(mktemp "$STATE_DIR/.bn.XXXXXX")
  awk -v ip="$1" '$1 != ip' "$BANS" >"$tmp" && mv "$tmp" "$BANS"
  [ "$BACKEND" = "ipset" ] && fw_unban "$1"
  [ "$BACKEND" = "nginx" ] && nginx_deny_sync
}

sweep() {
  local tmp
  tmp=$(mktemp "$STATE_DIR/.sw.XXXXXX")
  awk -v now="$NOW" '$2 > now' "$BANS" >"$tmp" && mv "$tmp" "$BANS"
  tmp=$(mktemp "$STATE_DIR/.sw.XXXXXX")
  awk -v now="$NOW" -v win=604800 'now - $3 < win' "$STRIKES" >"$tmp" && mv "$tmp" "$STRIKES"
  [ "$BACKEND" = "nginx" ] && nginx_deny_sync
}

# ---------------------------- notifikasi & CF API ------------------------- #

notify() {
  [ -n "$DISCORD_WEBHOOK" ] || return 0
  local msg=${1//\"/}
  curl -fsS -m 8 -H 'Content-Type: application/json' \
    -d "{\"content\":\"$msg\"}" "$DISCORD_WEBHOOK" >/dev/null 2>&1 &
}

cf_api() {
  curl -fsS -m 10 -X "$1" "https://api.cloudflare.com/client/v4/zones/$CF_ZONE_ID/settings/security_level" \
    -H "Authorization: Bearer $CF_API_TOKEN" -H "Content-Type: application/json" ${2:+--data "$2"} 2>/dev/null
}

cf_enter() {
  [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ] || return 0
  local prev
  prev=$(cf_api GET | grep -o '"value":"[a-z_]*"' | head -1 | cut -d'"' -f4)
  [ -n "$prev" ] && [ "$prev" != "under_attack" ] && echo "$prev" >"$STATE_DIR/cf_prev_level"
  if cf_api PATCH '{"value":"under_attack"}' >/dev/null; then
    log "Cloudflare security level -> under_attack"
  else
    log "gagal mengatur Cloudflare (cek token/zone id)"
  fi
}

cf_leave() {
  [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ZONE_ID" ] || return 0
  local prev=medium
  [ -f "$STATE_DIR/cf_prev_level" ] && prev=$(tr -cd 'a-z_' <"$STATE_DIR/cf_prev_level")
  [ -n "$prev" ] || prev=medium
  if cf_api PATCH "{\"value\":\"$prev\"}" >/dev/null; then
    log "Cloudflare security level -> $prev"
  else
    log "gagal mengembalikan level Cloudflare ke $prev"
  fi
}

# ------------------------- whitelist node Wings -------------------------- #

envval() {
  grep -E "^$1=" "$PANEL_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d "\"'\r"
}

sync_nodes() {
  [ -r "$PANEL_DIR/.env" ] && command -v mysql >/dev/null || return 0
  local h p d u w fq f tmp
  h=$(envval DB_HOST)
  p=$(envval DB_PORT)
  d=$(envval DB_DATABASE)
  u=$(envval DB_USERNAME)
  w=$(envval DB_PASSWORD)
  fq=$(MYSQL_PWD="$w" mysql -N -B -h"${h:-127.0.0.1}" -P"${p:-3306}" -u"$u" "$d" -e 'SELECT fqdn FROM nodes' 2>/dev/null) || return 0
  tmp=$(mktemp "$STATE_DIR/.nd.XXXXXX")
  for f in $fq; do
    if valid_ip "$f"; then
      echo "$f"
    else
      getent ahosts "$f" 2>/dev/null | awk '{ print $1 }' | sort -u
    fi
  done | while read -r ip; do valid_ip "$ip" && echo "$ip"; done >"$tmp"
  mv "$tmp" "$NODES"
}

load_nodes() {
  # IP node Wings + IP server ini sendiri (koneksi hairpin Wings -> Panel di mesin yang sama)
  NODE_IPS="$(tr '\n' ' ' <"$NODES" 2>/dev/null) $(hostname -I 2>/dev/null)"
}

# -------------------------------- status --------------------------------- #

write_status() {
  local banned
  banned=$(awk -v now="$NOW" '$2 > now' "$BANS" | wc -l)
  cat >"$KV.tmp" <<KVEOF
S_MODE=$mode
S_SINCE=$attack_since
S_CONN=$total
S_SYN=$syn
S_BANNED=$banned
S_OFFENDERS=$offenders
S_EVENTS=$events
S_ATTACKS=$ATTACKS
S_LAST_ATTACK=$LAST_ATTACK
S_UPDATED=$NOW
S_BACKEND=$BACKEND
S_CF=$CF_MODE
KVEOF
  mv "$KV.tmp" "$KV"
  local out="$PANEL_DIR/public/themes/night/ddos-status.json"
  if [ -d "${out%/*}" ]; then
    printf '{"mode":"%s","since":%s,"conn":%s,"syn":%s,"banned":%s,"offenders":%s,"events":%s,"attacks":%s,"last_attack":%s,"updated":%s,"backend":"%s","cf":%s}\n' \
      "$mode" "$attack_since" "$total" "$syn" "$banned" "$offenders" "$events" "$ATTACKS" "$LAST_ATTACK" "$NOW" "$BACKEND" "$CF_MODE" \
      >"$out.tmp" && chmod 644 "$out.tmp" && mv "$out.tmp" "$out"
  fi
}

# ------------------------------ mode serangan ----------------------------- #

enter_attack() {
  mode=attack
  attack_since=$NOW
  calm=0
  ATTACKS=$((ATTACKS + 1))
  LAST_ATTACK=$NOW
  echo "$ATTACKS $LAST_ATTACK" >"$STATE_DIR/attacks"
  set_profile strict
  cf_enter
  log "SERANGAN TERDETEKSI ($1) -> mode ketat aktif"
  notify "[$(uname -n)] Serangan DDoS terdeteksi: $1. Mode ketat aktif."
}

leave_attack() {
  mode=normal
  set_profile normal
  cf_leave
  log "Serangan mereda -> kembali ke mode normal (berlangsung $((NOW - attack_since))s)"
  notify "[$(uname -n)] Serangan mereda, panel kembali ke mode normal (berlangsung $((NOW - attack_since)) detik)."
  attack_since=0
}

# ---------------------------------- daemon -------------------------------- #

run() {
  load_conf
  mkdir -p "$STATE_DIR" "$NG_DIR"
  touch "$BANS" "$STRIKES" "$NODES" "$LOG_FILE"
  detect_backend
  [ "$BACKEND" = "ipset" ] && fw_setup
  trap 'log "NightGuard berhenti"; exit 0' TERM INT

  local -A HITS=()
  local mode=normal attack_since=0 calm=0 cycle=0 OFFSET size from
  local total=0 syn=0 events=0 offenders=0 c ip v why quiet force
  NGINX_DIRTY=0
  ATTACKS=0
  LAST_ATTACK=0
  [ -f "$STATE_DIR/attacks" ] && read -r ATTACKS LAST_ATTACK <"$STATE_DIR/attacks"
  : "${ATTACKS:=0}" "${LAST_ATTACK:=0}"

  sync_nodes
  load_nodes
  printf -v NOW '%(%s)T' -1
  gen_whitelist
  set_profile normal
  [ "$BACKEND" = "nginx" ] && nginx_deny_sync
  nginx_reload
  OFFSET=$(stat -c %s "$NGINX_LOG" 2>/dev/null || echo 0)
  log "NightGuard berjalan (backend ban: $BACKEND, cloudflare: $CF_MODE)"

  while true; do
    sleep "$INTERVAL" &
    wait $!
    printf -v NOW '%(%s)T' -1
    cycle=$((cycle + 1))
    BANS_THIS_CYCLE=0

    [ $((cycle % 12)) -eq 0 ] && { load_conf; gen_whitelist; }
    [ $((cycle % 120)) -eq 0 ] && { sync_nodes; load_nodes; gen_whitelist; }

    # 1) koneksi aktif per IP + total (dilewati per-IP kalau di belakang Cloudflare)
    total=0
    while read -r c ip; do
      [ -n "$ip" ] || continue
      total=$((total + c))
      if [ "$CF_MODE" != "true" ] && [ "$c" -ge "$CONN_PER_IP_BAN" ] && [ "$BANS_THIS_CYCLE" -lt "$MAX_BANS_PER_CYCLE" ]; then
        ban_ip "$ip" "koneksi-$c"
      fi
    done < <(ss -Htn state established '( sport = :80 or sport = :443 )' 2>/dev/null |
      awk '{ p = $4; sub(/:[0-9]+$/, "", p); gsub(/[\[\]]/, "", p); sub(/^::ffff:/, "", p); n[p]++ } END { for (i in n) print n[i], i }')
    syn=$(ss -Htn state syn-recv '( sport = :80 or sport = :443 )' 2>/dev/null | wc -l)

    # 2) peluruhan skor lalu tambah penolakan rate-limit baru dari log nginx
    for ip in "${!HITS[@]}"; do
      v=$((HITS["$ip"] * 7 / 8))
      if [ "$v" -le 0 ]; then unset 'HITS[$ip]'; else HITS["$ip"]=$v; fi
    done
    events=0
    size=$(stat -c %s "$NGINX_LOG" 2>/dev/null || echo 0)
    [ "$size" -lt "$OFFSET" ] && OFFSET=0
    if [ "$size" -gt "$OFFSET" ]; then
      from=$OFFSET
      OFFSET=$size
      while read -r c ip; do
        [ -n "$ip" ] || continue
        events=$((events + c))
        HITS["$ip"]=$((${HITS["$ip"]:-0} + c))
      done < <(tail -c +"$((from + 1))" "$NGINX_LOG" | head -c 8000000 | awk '
        /limiting (requests|connections)/ {
          if (match($0, /client: [^,]+/)) n[substr($0, RSTART + 8, RLENGTH - 8)]++
        }
        END { for (i in n) print n[i], i }')
    fi

    # 3) blokir pelanggar & hitung jumlah pelanggar
    offenders=0
    for ip in "${!HITS[@]}"; do
      v=${HITS["$ip"]}
      [ "$v" -ge $((HIT_BAN / 4)) ] && offenders=$((offenders + 1))
      if [ "$v" -ge "$HIT_BAN" ] && [ "$BANS_THIS_CYCLE" -lt "$MAX_BANS_PER_CYCLE" ]; then
        ban_ip "$ip" "rate-limit-$v"
        unset 'HITS[$ip]'
      fi
    done

    # 4) auto-deteksi serangan (dengan histeresis supaya tidak bolak-balik)
    why=""
    [ "$syn" -ge "$SYN_RECV_ATTACK" ] && why+="SYN_RECV=$syn "
    [ "$total" -ge "$TOTAL_CONN_ATTACK" ] && why+="koneksi=$total "
    [ "$offenders" -ge "$OFFENDERS_ATTACK" ] && why+="pelanggar=$offenders "
    [ "$events" -ge "$EVENTS_ATTACK" ] && why+="penolakan/siklus=$events "

    force=""
    [ -f "$STATE_DIR/force" ] && force=$(cat "$STATE_DIR/force")
    [ "$force" = "attack" ] && why="uji-coba-manual"

    if [ "$mode" = "normal" ]; then
      [ -n "$why" ] && enter_attack "${why% }"
    else
      quiet=1
      [ $((syn * 2)) -ge "$SYN_RECV_ATTACK" ] && quiet=0
      [ $((total * 2)) -ge "$TOTAL_CONN_ATTACK" ] && quiet=0
      [ $((offenders * 2)) -ge "$OFFENDERS_ATTACK" ] && quiet=0
      [ $((events * 2)) -ge "$EVENTS_ATTACK" ] && quiet=0
      if [ "$quiet" -eq 1 ] && [ -z "$why" ]; then calm=$((calm + 1)); else calm=0; fi
      if [ "$force" = "calm" ]; then
        rm -f "$STATE_DIR/force"
        leave_attack
      elif [ "$calm" -ge "$CALM_CYCLES" ] && [ $((NOW - attack_since)) -ge "$MIN_ATTACK_HOLD" ]; then
        leave_attack
      fi
    fi
    [ "$force" = "calm" ] && rm -f "$STATE_DIR/force"

    # 5) rumah tangga: kadaluarsa ban, self-heal aturan firewall, reload nginx, status
    if [ $((cycle % 6)) -eq 0 ]; then
      sweep
      if [ "$BACKEND" = "ipset" ]; then
        fw_setup
      fi
    fi
    [ "$NGINX_DIRTY" -eq 1 ] && nginx_reload
    write_status
  done
}

# ---------------------------------- CLI ----------------------------------- #

cli_prepare() {
  load_conf
  mkdir -p "$STATE_DIR"
  touch "$BANS" "$STRIKES"
  printf -v NOW '%(%s)T' -1
  detect_backend
  NODE_IPS=""
  BANS_THIS_CYCLE=0
}

cli_status() {
  [ -f "$KV" ] || { echo "NightGuard belum berjalan (systemctl status nightguard)."; exit 1; }
  # shellcheck source=/dev/null
  . "$KV"
  local ago=$(($(date +%s) - S_UPDATED))
  echo "NightGuard"
  printf '  %-20s %s\n' "Mode" "$([ "$S_MODE" = attack ] && echo 'SERANGAN (mode ketat)' || echo 'Normal')"
  printf '  %-20s %s\n' "Koneksi aktif" "$S_CONN"
  printf '  %-20s %s\n' "SYN_RECV" "$S_SYN"
  printf '  %-20s %s\n' "IP diblokir" "$S_BANNED"
  printf '  %-20s %s\n' "Pelanggar (live)" "$S_OFFENDERS"
  printf '  %-20s %s\n' "Serangan tercatat" "$S_ATTACKS"
  [ "$S_LAST_ATTACK" -gt 0 ] && printf '  %-20s %s\n' "Serangan terakhir" "$(date -d "@$S_LAST_ATTACK" '+%F %T')"
  printf '  %-20s %s\n' "Backend blokir" "$S_BACKEND"
  printf '  %-20s %ss lalu%s\n' "Pembaruan" "$ago" "$([ "$ago" -gt 30 ] && echo '  (daemon tidak merespons?)')"
}

cli_list() {
  printf -v NOW '%(%s)T' -1
  awk -v now="$NOW" '$2 > now { printf "%-40s sisa %6ds  %s\n", $1, $2 - now, $3 }' "$BANS" | sort
}

case "$1" in
  run) run ;;
  status) cli_status ;;
  list) cli_list ;;
  ban)
    valid_ip "$2" || { echo "IP tidak valid: $2"; exit 1; }
    [[ "${3:-86400}" =~ ^[0-9]+$ ]] || { echo "Durasi harus angka (detik)"; exit 1; }
    cli_prepare
    NGINX_DIRTY=0
    ban_ip "$2" "manual" "${3:-86400}"
    [ "$BACKEND" = "nginx" ] && nginx_reload
    echo "IP $2 diblokir."
    ;;
  unban)
    valid_ip "$2" || { echo "IP tidak valid: $2"; exit 1; }
    cli_prepare
    NGINX_DIRTY=0
    unban_ip "$2"
    [ "$BACKEND" = "nginx" ] && nginx_reload
    echo "IP $2 dibuka blokirnya."
    ;;
  attack | calm)
    mkdir -p "$STATE_DIR"
    echo "$1" >"$STATE_DIR/force"
    echo "Perintah '$1' dikirim; berlaku di siklus berikutnya (maks ${INTERVAL}s)."
    ;;
  *)
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
    exit 1
    ;;
esac
