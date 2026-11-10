#!/data/data/com.termux/files/usr/bin/bash
# Hermes Deck - agen sisi Termux (berjalan di domain aplikasi Termux).
# Tugas: menaikkan/menurunkan stack Hermes mengikuti file mode.
# Kenapa di sini, bukan di modul root: proses yang diluncurkan lewat rantai
# `su` jatuh ke domain SELinux su dan gagal membuat socket (gateway tewas
# dengan PermissionError). Dari domain Termux, socket normal.
#
# File mode cermin: ~/.deck-mode (isi: ai | biasa) - ditulis deckctl (root)
# dari file kebenaran /data/adb/hermes_deck/mode.
# Dinyalakan oleh: Termux:Boot (~/.termux/boot/02-deck-agent.sh) atau manual.

MIRROR="$HOME/.deck-mode"
LOG="$HOME/deck-agent.log"
LASTSTART="$HOME/.deck-last-start"
LASTWEBUI="$HOME/.deck-last-webui"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG" 2>/dev/null; }

scan() { # $1=pola1 $2=pola2(sukarela, harus ikut setelah pola1)
  for p in /proc/[0-9]*/cmdline; do
    [ -r "$p" ] || continue
    c=$(tr '\0' ' ' < "$p" 2>/dev/null)
    if [ -n "$2" ]; then
      case "$c" in *"$1"*"$2"*) return 0 ;; esac
    else
      case "$c" in *"$1"*) return 0 ;; esac
    fi
  done
  return 1
}

gw_alive() { scan "gateway" "run"; }
rt_alive() { scan "custom-server.js" || scan "next-server"; }
wu_alive() { scan "hermes-webui"; }

kill_stack() {
  for pat in "gateway" "next-server" "custom-server.js" "hermes-webui" "start-stack" "stack-router" "stack-webui"; do
    for d in /proc/[0-9]*; do
      pid=${d#/proc/}
      [ "$pid" = "$$" ] && continue
      [ -r "$d/cmdline" ] || continue
      c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
      case "$pat" in
        gateway) case "$c" in *"gateway"*"run"*) kill "$pid" 2>/dev/null ;; esac ;;
        *) case "$c" in *"$pat"*) kill "$pid" 2>/dev/null ;; esac ;;
      esac
    done
  done
}

cooldown_ok() { # $1=file cap waktu, $2=detik
  now=$(date +%s)
  prev=$(cat "$1" 2>/dev/null || echo 0)
  [ $((now - prev)) -gt "$2" ]
}

log "deck-agent mulai (pid $$)"

# --- Eksekutor IPC konsol (v1.1) -------------------------------------------
# Relay modul meneruskan permintaan konsol dari aplikasi (yang buta
# mount-namespace) ke ~/.deck-ipc/req. Di sini perintah dijalankan lewat
# proot dari domain Termux, hasilnya ditulis ke ~/.deck-ipc/res.
AIPC="$HOME/.deck-ipc"
ROOTFS_L="${PREFIX:-/data/data/com.termux/files/usr}/var/lib/proot-distro/containers/ubuntu/rootfs"
mkdir -p "$AIPC/req" "$AIPC/res"
ipc_loop() {
  while true; do
    for f in "$AIPC/req"/*.req; do
      [ -e "$f" ] || continue
      id=$(basename "$f" .req)
      op=$(sed -n '1p' "$f" 2>/dev/null)
      if [ "$op" = "console" ]; then
        { echo 'export HERMES_HOME=/data/.hermes'
          echo 'export PATH=/data/.hermes/arm-venv/bin:/data/.hermes/tools/node-26.7.0-linux-arm64/bin:$PATH'
          echo 'hermes() { /data/.hermes/arm-venv/bin/python /data/.hermes/hermes-agent/hermes "$@"; }'
          sed -n '2,$p' "$f"
        } > "$ROOTFS_L/data/deck-console.sh" 2>/dev/null
        out=$(timeout 120 proot-distro login ubuntu -- bash /data/deck-console.sh 2>&1)
        code=$?
        { echo "$code"; printf '%s' "$out"; } > "$AIPC/res/$id.tmp" 2>/dev/null
        mv "$AIPC/res/$id.tmp" "$AIPC/res/$id.res" 2>/dev/null
        log "ipc console dilayani (id $id, kode $code)"
      else
        { echo 1; echo "ipc: op tidak dikenal: $op"; } > "$AIPC/res/$id.res" 2>/dev/null
      fi
      rm -f "$f"
    done
    sleep 1
  done
}
ipc_loop &

while true; do
  mode=$(cat "$MIRROR" 2>/dev/null)
  case "$mode" in ai|biasa) ;; *) mode=ai ;; esac
  if [ "$mode" = "ai" ]; then
    if ! gw_alive; then
      if cooldown_ok "$LASTSTART" 120; then
        date +%s > "$LASTSTART"
        setsid nohup sh "$HOME/run-hermes.sh" >> "$HOME/deck-start.log" 2>&1 &
        log "stack diluncurkan (gateway mati)"
      fi
    elif ! rt_alive; then
      if cooldown_ok "$LASTSTART" 120; then
        date +%s > "$LASTSTART"
        setsid nohup proot-distro login ubuntu -- bash /data/stack-router.sh >> "$HOME/deck-router.log" 2>&1 &
        log "router diluncurkan (gateway hidup, router mati)"
      fi
    fi
    if ! wu_alive; then
      if cooldown_ok "$LASTWEBUI" 120; then
        date +%s > "$LASTWEBUI"
        setsid nohup proot-distro login ubuntu -- bash /data/stack-webui.sh >> "$HOME/deck-webui.log" 2>&1 &
        log "webui diluncurkan"
      fi
    fi
  else
    if gw_alive || rt_alive || wu_alive; then
      kill_stack
      log "mode biasa: stack diturunkan oleh agen Termux"
    fi
  fi
  sleep 5
done
