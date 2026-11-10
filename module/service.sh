#!/system/bin/sh
# Hermes Deck - watchdog modul hermes_deck (Magisk late_start service).
# File mode adalah satu-satunya sumber kebenaran:
#   /data/adb/hermes_deck/mode  berisi "ai" atau "biasa"
# Mode AI    : hardening ditegaskan + sshd/stack/webui dijaga hidup.
# HP Biasa   : stack diturunkan sekali, lalu dibiarkan mati.

MODDIR="${0%/*}"
DECKDIR=/data/adb/hermes_deck
DECKCTL=$DECKDIR/deckctl.sh
TXHOME=/data/data/com.termux/files/home
LOGF=$DECKDIR/deck.log

mkdir -p "$DECKDIR"
[ -f "$DECKDIR/mode" ] || echo ai > "$DECKDIR/mode"
# deckctl + apply + relay selalu disalin segar dari modul
cp "$MODDIR/deckctl.sh" "$DECKCTL" 2>/dev/null
cp "$MODDIR/apply.sh" "$DECKDIR/apply.sh" 2>/dev/null
cp "$MODDIR/relay.sh" "$DECKDIR/relay.sh" 2>/dev/null
chmod 755 "$DECKCTL" "$DECKDIR/apply.sh" "$DECKDIR/relay.sh" 2>/dev/null

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') watchdog: $*" >> "$LOGF" 2>/dev/null; }

# Tunggu boot selesai (maks ~5 menit), beri jeda tambahan
i=0
while [ "$(getprop sys.boot_completed)" != "1" ] && [ "$i" -lt 60 ]; do sleep 5; i=$((i + 1)); done
sleep 15

log "watchdog mulai (mode=$(cat $DECKDIR/mode 2>/dev/null))"

# Relay v1.1: sinkron cermin dua arah + IPC aplikasi (singleton via pidfile)
nohup sh "$DECKDIR/relay.sh" >/dev/null 2>&1 &

LASTSTART=0
STOPPED_FOR_BIASA=0
while true; do
  MODE=$(cat "$DECKDIR/mode" 2>/dev/null)
  case "$MODE" in ai|biasa) ;; *) MODE=ai ;; esac
  NOW=$(date +%s)
  if [ "$MODE" = "ai" ]; then
    STOPPED_FOR_BIASA=0
    # phantom kadang ter-reset sinkronisasi: tegaskan tiap siklus
    V=$(/system/bin/device_config get activity_manager max_phantom_processes 2>/dev/null)
    [ "$V" = "2147483647" ] || sh "$DECKDIR/apply.sh"
    # sshd hanya dijaga bila Agen Pembantu aktif (flag helper, default off)
    HELPER=$(cat "$DECKDIR/helper" 2>/dev/null)
    if [ "$HELPER" = "on" ]; then
      SSHD=0
      for p in /proc/[0-9]*/cmdline; do
        c=$(tr '\0' ' ' < "$p" 2>/dev/null)
        case "$c" in *sshd*) SSHD=1; break ;; esac
      done
      if [ "$SSHD" = "0" ]; then
        su 10194 -c "export HOME=$TXHOME PREFIX=/data/data/com.termux/files/usr PATH=/data/data/com.termux/files/usr/bin:/system/bin; /data/data/com.termux/files/usr/bin/sshd" 2>/dev/null
        log "sshd dihidupkan ulang"
      fi
    fi
    # Sinkronkan cermin mode untuk agen Termux (dia yang menaikkan stack;
    # proses dari rantai su gagal membuat socket di domain SELinux su).
    CUR=$(cat $TXHOME/.deck-mode 2>/dev/null)
    [ "$CUR" = "ai" ] || echo ai > $TXHOME/.deck-mode 2>/dev/null
  else
    # Mode Biasa: cermin WAJIB ikut biasa (v2.0 tidak menyinkronkannya -
    # agen Termux terus menaikkan stack dan bertarung dengan watchdog)
    CUR=$(cat $TXHOME/.deck-mode 2>/dev/null)
    [ "$CUR" = "biasa" ] || echo biasa > $TXHOME/.deck-mode 2>/dev/null
    # Mode Biasa: turunkan sekali saja per pergantian mode
    if [ "$STOPPED_FOR_BIASA" = "0" ]; then
      sh "$DECKCTL" stop
      STOPPED_FOR_BIASA=1
      log "mode biasa: stack diturunkan"
    fi
  fi
  sleep 30
done
