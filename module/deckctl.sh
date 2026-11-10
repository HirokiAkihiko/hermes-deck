#!/system/bin/sh
# Hermes Deck - deckctl v1.1: satu-satunya jalur kendali stack Hermes di whyred.
# Dipanggil oleh: aplikasi Hermes Deck (via su), modul hermes_deck (service.sh),
# dan CLI manual: su -c sh /data/adb/hermes_deck/deckctl.sh <perintah>
#
# Perintah:
#   mode                -> ai | biasa
#   mode ai|biasa       -> tulis file mode + terapkan sekarang
#   status              -> baris key=value (mode,gateway,router,models,webui,tailscale,phantom)
#   restart             -> turunkan lalu naikkan stack (hanya Mode AI)
#   log                 -> ekor log deck + gateway + router
#   console <perintah>  -> jalankan perintah di Ubuntu proot (timeout 120 dtk)
#   ls [relpath]        -> daftar isi direktori di /data distro (relatif ke /data)
#   cat <relpath>       -> isi file teks di /data distro (maks ~64KB)
#
# Perubahan v1.1 (perbaikan bug v1.0):
#  - Pemindaian proses SATU lintasan /proc (sebelumnya berulang per pola ->
#    status/stop makan waktu menit di SD636, UI aplikasi menyerah duluan).
#  - console/ls/cat: bila rootfs Termux tidak terlihat dari konteks pemanggil
#    (aplikasi via su terkena kebutaan mount-namespace), permintaan diteruskan
#    lewat IPC berkas ke relay modul + agen Termux yang melihatnya.
#    DECK_FORCE_IPC=1 memaksa jalur IPC (untuk pengujian).
#  - Jumlah model: fallback ke cache relay (/data/adb/hermes_deck/models-cache)
#    bila log router tidak terbaca dari konteks pemanggil.

DECKDIR=/data/adb/hermes_deck
MODDIR=/data/adb/modules/hermes_deck
MODEFILE=$DECKDIR/mode
HELPERFILE=$DECKDIR/helper
LOGF=$DECKDIR/deck.log
IPC=$DECKDIR/ipc
TX=com.termux
TXUID=10194
TXHOME=/data/data/com.termux/files/home
TXPREFIX=/data/data/com.termux/files/usr
ROOTFS=$TXPREFIX/var/lib/proot-distro/containers/ubuntu/rootfs

mkdir -p "$DECKDIR" 2>/dev/null

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOGF" 2>/dev/null; }

write_mirror() {
  # Best-effort saja: penjamin sinkron cermin adalah relay modul
  # (master -> cermin tiap ~2 detik dari namespace global).
  # PERHATIAN urutan redireksi: 2>/dev/null harus SEBELUM > berkas.
  # Bila > gagal (pemanggil buta mount-namespace), pesan "cant create"
  # ditulis shell ke stderr SEBELUM redireksi > diproses - dengan urutan
  # lama, error itu bocor ke layar aplikasi (terlihat user 11 Nov 01:22).
  echo "$1" 2>/dev/null > "$TXHOME/.deck-mode"
  chown $TXUID:$TXUID "$TXHOME/.deck-mode" 2>/dev/null
}

get_mode() {
  m=$(cat "$MODEFILE" 2>/dev/null)
  case "$m" in ai|biasa) echo "$m" ;; *) echo ai ;; esac
}

# Flag Agen Pembantu (akses jarak jauh: Tailscale + sshd). Default off:
# file tidak ada / isi selain "on" berarti mati.
get_helper() {
  h=$(cat "$HELPERFILE" 2>/dev/null)
  case "$h" in on) echo on ;; *) echo off ;; esac
}

write_helper_mirror() {
  # Urutan redireksi sama seperti write_mirror: stderr dulu, baru berkas.
  echo "$(get_helper)" 2>/dev/null > "$TXHOME/.deck-helper"
  chown $TXUID:$TXUID "$TXHOME/.deck-helper" 2>/dev/null
}

sshd_running() {
  for p in /proc/[0-9]*/cmdline; do
    c=$(tr '\0' ' ' < "$p" 2>/dev/null)
    case "$c" in *sshd*) return 0 ;; esac
  done
  return 1
}

start_sshd_now() {
  sshd_running && return 0
  su $TXUID -c "export HOME=$TXHOME PREFIX=$TXPREFIX PATH=$TXPREFIX/bin:/system/bin; $TXPREFIX/bin/sshd" 2>/dev/null
}

kill_sshd_now() {
  for p in /proc/[0-9]*; do
    pid=${p#/proc/}
    [ "$pid" = "$$" ] && continue
    c=$(tr '\0' ' ' < "$p/cmdline" 2>/dev/null)
    case "$c" in *sshd*) kill "$pid" 2>/dev/null ;; esac
  done
}

# --- Pemindaian proses SATU lintasan -------------------------------------
# Mengisi: SNAP_GW/SNAP_RT/SNAP_WU/SNAP_TS (0/1) dan PIDS_ALL (pid yang
# termasuk stack: gateway, router, webui, skrip stack-*).
# Jalur cepat: satu panggilan `ps` (toybox, ~0,1 dtk) lalu cocokkan pola
# per baris di shell. Cadangan: lintasan /proc (snapshot_proc_slow) bila
# ps gagal/kosong.
SNAP_GW=0; SNAP_RT=0; SNAP_WU=0; SNAP_TS=0; SNAP_SSHD=0; PIDS_ALL=""
snapshot_proc() {
  SNAP_GW=0; SNAP_RT=0; SNAP_WU=0; SNAP_TS=0; SNAP_SSHD=0; PIDS_ALL=""
  _snap="$DECKDIR/.ps-snap-$$"
  ps -A -w -o PID,ARGS > "$_snap" 2>/dev/null
  if [ ! -s "$_snap" ]; then
    rm -f "$_snap"
    snapshot_proc_slow
    return
  fi
  while read -r _pid _args; do
    case "$_pid" in ''|*[!0-9]*) continue ;; esac
    [ "$_pid" = "$$" ] && continue
    case "$_args" in
      *"gateway"*"run"*|*"gateway', 'run'"*)
        SNAP_GW=1; PIDS_ALL="$PIDS_ALL $_pid" ;;
    esac
    case "$_args" in
      *"custom-server.js"*|*"next-server"*)
        SNAP_RT=1; PIDS_ALL="$PIDS_ALL $_pid" ;;
    esac
    case "$_args" in
      *"hermes-webui"*)
        SNAP_WU=1; PIDS_ALL="$PIDS_ALL $_pid" ;;
    esac
    case "$_args" in
      *"com.tailscale.ipn"*) SNAP_TS=1 ;;
    esac
    case "$_args" in
      *sshd*) SNAP_SSHD=1 ;;
    esac
    case "$_args" in
      *"start-stack"*|*"stack-router"*|*"stack-webui"*)
        PIDS_ALL="$PIDS_ALL $_pid" ;;
    esac
  done < "$_snap"
  rm -f "$_snap"
}

snapshot_proc_slow() {
  SNAP_GW=0; SNAP_RT=0; SNAP_WU=0; SNAP_TS=0; SNAP_SSHD=0; PIDS_ALL=""
  for d in /proc/[0-9]*; do
    pid=${d#/proc/}
    [ "$pid" = "$$" ] && continue
    [ -r "$d/cmdline" ] || continue
    c=$(tr '\0' ' ' < "$d/cmdline" 2>/dev/null)
    [ -n "$c" ] || continue
    case "$c" in
      *"gateway"*"run"*|*"gateway', 'run'"*)
        SNAP_GW=1; PIDS_ALL="$PIDS_ALL $pid" ;;
    esac
    case "$c" in
      *"custom-server.js"*|*"next-server"*)
        SNAP_RT=1; PIDS_ALL="$PIDS_ALL $pid" ;;
    esac
    case "$c" in
      *"hermes-webui"*)
        SNAP_WU=1; PIDS_ALL="$PIDS_ALL $pid" ;;
    esac
    case "$c" in
      *"com.tailscale.ipn"*) SNAP_TS=1 ;;
    esac
    case "$c" in
      *sshd*) SNAP_SSHD=1 ;;
    esac
    case "$c" in
      *"start-stack"*|*"stack-router"*|*"stack-webui"*)
        PIDS_ALL="$PIDS_ALL $pid" ;;
    esac
  done
}

gateway_alive() { snapshot_proc; [ "$SNAP_GW" = "1" ]; }
router_alive()  { snapshot_proc; [ "$SNAP_RT" = "1" ]; }
webui_alive()   { snapshot_proc; [ "$SNAP_WU" = "1" ]; }

run_as_termux() {
  su $TXUID -c "export HOME=$TXHOME PREFIX=$TXPREFIX PATH=$TXPREFIX/bin:/system/bin LD_LIBRARY_PATH=$TXPREFIX/lib TMPDIR=$TXPREFIX/tmp; $1"
}

start_gateway_stack() {
  gateway_alive && return 0
  run_as_termux "setsid nohup $TXPREFIX/bin/sh $TXHOME/run-hermes.sh >> $TXHOME/deck-start.log 2>&1 &"
  log "stack (router+gateway) diluncurkan"
}

start_router_only() {
  router_alive && return 0
  run_as_termux "setsid nohup proot-distro login ubuntu -- bash /data/stack-router.sh >> $TXHOME/deck-router.log 2>&1 &"
  log "router saja diluncurkan"
}

start_webui() {
  webui_alive && return 0
  run_as_termux "setsid nohup proot-distro login ubuntu -- bash /data/stack-webui.sh >> $TXHOME/deck-webui.log 2>&1 &"
  log "webui diluncurkan"
}

stop_stack() {
  snapshot_proc
  for pid in $PIDS_ALL; do kill "$pid" 2>/dev/null; done
  sleep 3
  snapshot_proc
  for pid in $PIDS_ALL; do kill -9 "$pid" 2>/dev/null; done
  log "stack diturunkan"
}

apply_mode() {
  m=$(get_mode)
  write_mirror "$m"
  if [ "$m" = "ai" ]; then
    sh "$MODDIR/apply.sh" 2>/dev/null || sh "$DECKDIR/apply.sh" 2>/dev/null
    # Stack SENGAJA tidak diluncurkan dari konteks root: proses warisan
    # rantai su jatuh ke domain SELinux su dan gagal membuat socket
    # (gateway: PermissionError). Agen Termux (deck-agent.sh, domain
    # aplikasi) membaca file cermin dan menaikkan stack <=10 detik.
    log "mode ai: hardening diterapkan, agen Termux menaikkan stack"
  else
    stop_stack
  fi
}

models_count() {
  # Dari konteks aplikasi (su), log router tidak terbaca (namespace) ->
  # jatuh ke cache yang ditulis relay dari namespace global.
  f="$ROOTFS/data/logs-router9.txt"
  if [ -r "$f" ]; then
    line=$(tail -c 300000 "$f" 2>/dev/null | grep "modelCatalog" | tail -1)
    n=$(echo "$line" | sed -n 's/.*modelCatalog\] \([0-9][0-9]*\) models.*/\1/p')
    [ -n "$n" ] && { echo "$n"; return; }
  fi
  n=$(cat "$DECKDIR/models-cache" 2>/dev/null)
  case "$n" in ''|*[!0-9]*) echo 0 ;; *) echo "$n" ;; esac
}

cmd_status() {
  snapshot_proc
  echo "mode=$(get_mode)"
  echo "helper=$(get_helper)"
  if [ "$SNAP_SSHD" = "1" ]; then echo "sshd=up"; else echo "sshd=down"; fi
  if [ "$SNAP_GW" = "1" ]; then echo "gateway=up"; else echo "gateway=down"; fi
  if [ "$SNAP_RT" = "1" ]; then echo "router=up"; else echo "router=down"; fi
  echo "models=$(models_count)"
  if [ "$SNAP_WU" = "1" ]; then echo "webui=up"; else echo "webui=down"; fi
  if [ "$SNAP_TS" = "1" ]; then echo "tailscale=up"; else echo "tailscale=down"; fi
  echo "phantom=$(/system/bin/device_config get activity_manager max_phantom_processes 2>/dev/null)"
}

# --- IPC ke relay + agen Termux -------------------------------------------
# Berkas permintaan: $IPC/req/<id>.req  (baris 1: op, baris 2+: argumen)
# Berkas jawaban:    $IPC/res/<id>.res  (baris 1: kode keluar, baris 2+: output)
ipc_call() {
  _op="$1"; _arg="$2"; _tmo="$3"; _arg2="$4"
  mkdir -p "$IPC/req" "$IPC/res" 2>/dev/null
  _id="$(date +%s)-$$"
  _tmp="$IPC/req/.$_id.tmp"
  { echo "$_op"; printf '%s\n' "$_arg"; if [ -n "$_arg2" ]; then printf '%s\n' "$_arg2"; fi; } > "$_tmp" 2>/dev/null || {
    echo "ipc: tidak bisa menulis permintaan ke $IPC/req"; return 1; }
  mv "$_tmp" "$IPC/req/$_id.req"
  _waited=0
  while [ ! -f "$IPC/res/$_id.res" ]; do
    sleep 1; _waited=$((_waited + 1))
    if [ "$_waited" -ge "$_tmo" ]; then
      rm -f "$IPC/req/$_id.req"
      echo "ipc: timeout ${_tmo} dtk (relay/agen tidak menjawab)"
      return 1
    fi
  done
  _code=$(sed -n '1p' "$IPC/res/$_id.res" 2>/dev/null)
  sed -n '2,$p' "$IPC/res/$_id.res" 2>/dev/null
  rm -f "$IPC/res/$_id.res"
  [ "$_code" = "0" ]
}

rootfs_visible() { [ -d "$ROOTFS/data" ]; }
use_ipc() { [ -n "$DECK_FORCE_IPC" ] || ! rootfs_visible; }

# path aman di dalam /data distro untuk ls/cat
safe_data_path() {
  rel="$1"
  case "$rel" in ""|"." ) echo "$ROOTFS/data"; return 0 ;; esac
  case "$rel" in *".."*|/*) return 1 ;; esac
  echo "$ROOTFS/data/$rel"
}
valid_rel() {
  case "$1" in *".."*|/*) return 1 ;; *) return 0 ;; esac
}

cmd_console() {
  cmd="$*"
  [ -n "$cmd" ] || { echo "console: perintah kosong"; return 1; }
  if use_ipc; then
    ipc_call console "$cmd" 150
    return $?
  fi
  { echo 'export HERMES_HOME=/data/.hermes'
    echo 'export PATH=/data/.hermes/arm-venv/bin:/data/.hermes/tools/node-26.7.0-linux-arm64/bin:$PATH'
    echo 'hermes() { /data/.hermes/arm-venv/bin/python /data/.hermes/hermes-agent/hermes "$@"; }'
    printf '%s\n' "$cmd"
  } > "$ROOTFS/data/deck-console.sh" 2>/dev/null || {
    echo "console: rootfs tidak ditemukan di $ROOTFS"; return 1; }
  chown $TXUID:$TXUID "$ROOTFS/data/deck-console.sh" 2>/dev/null
  run_as_termux "timeout 120 proot-distro login ubuntu -- bash /data/deck-console.sh"
}

cmd_ls() {
  rel="$1"
  if use_ipc; then
    valid_rel "$rel" || { echo "ls: path ditolak"; return 1; }
    ipc_call ls "$rel" 40
    return $?
  fi
  p=$(safe_data_path "$rel") || { echo "ls: path ditolak"; return 1; }
  [ -d "$p" ] || { echo "ls: bukan direktori: $rel"; return 1; }
  for e in "$p"/* "$p"/.*; do
    [ -e "$e" ] || continue
    name=${e##*/}
    [ "$name" = "." ] || [ "$name" = ".." ] && continue
    if [ -d "$e" ]; then echo "$name/"; else echo "$name"; fi
  done
}

cmd_cp() {
  src="$1"; dst="$2"
  [ -n "$src" ] && [ -n "$dst" ] || { echo "pakai: deckctl cp <sumber-rel> <folder-tujuan-rel>"; return 1; }
  valid_rel "$src" || { echo "cp: path sumber ditolak"; return 1; }
  valid_rel "$dst" || { echo "cp: path tujuan ditolak"; return 1; }
  if use_ipc; then
    ipc_call cp "$src" 150 "$dst"
    return $?
  fi
  s=$(safe_data_path "$src"); d=$(safe_data_path "$dst")
  [ -e "$s" ] || { echo "cp: sumber tidak ada: $src"; return 1; }
  [ -d "$d" ] || { echo "cp: tujuan bukan direktori: $dst"; return 1; }
  base=${s##*/}; t="$d/$base"; n=2
  while [ -e "$t" ]; do t="$d/$base ($n)"; n=$((n + 1)); done
  cp -r "$s" "$t" || { echo "cp: gagal menyalin"; return 1; }
  echo "tersalin: ${t#$ROOTFS/data/}"
}

cmd_put() {
  staging="$1"; dst="$2"
  [ -n "$staging" ] && [ -n "$dst" ] || { echo "pakai: deckctl put <file-staging-abs> <folder-tujuan-rel>"; return 1; }
  valid_rel "$dst" || { echo "put: path tujuan ditolak"; return 1; }
  [ -f "$staging" ] || { echo "put: file staging tidak ditemukan: $staging"; return 1; }
  if use_ipc; then
    ipc_call put "$staging" 150 "$dst"
    return $?
  fi
  d=$(safe_data_path "$dst")
  [ -d "$d" ] || { echo "put: tujuan bukan direktori: $dst"; return 1; }
  base=${staging##*/}; t="$d/$base"; n=2
  while [ -e "$t" ]; do t="$d/$base ($n)"; n=$((n + 1)); done
  cp "$staging" "$t" || { echo "put: gagal menyalin"; return 1; }
  echo "terunggah: ${t#$ROOTFS/data/}"
}

cmd_cat() {
  rel="$1"
  if use_ipc; then
    valid_rel "$rel" || { echo "cat: path ditolak"; return 1; }
    ipc_call cat "$rel" 40
    return $?
  fi
  p=$(safe_data_path "$rel") || { echo "cat: path ditolak"; return 1; }
  [ -f "$p" ] || { echo "cat: bukan file: $rel"; return 1; }
  head -c 65536 "$p"
}

agent_alive() {
  for p in /proc/[0-9]*/cmdline; do
    c=$(tr '\0' ' ' < "$p" 2>/dev/null)
    case "$c" in *"deck-agent.sh"*) return 0 ;; esac
  done
  return 1
}

run_command_agent() {
  /system/bin/am startservice --user 0 \
    -n com.termux/com.termux.app.RunCommandService \
    -a com.termux.RUN_COMMAND \
    --es com.termux.RUN_COMMAND_PATH "$TXHOME/deck-agent.sh" \
    --ez com.termux.RUN_COMMAND_BACKGROUND true >/dev/null 2>&1
}

# resurrect: hidupkan deck-agent dari luar Termux (v1.4).
# Konteks pemanggil WAJIB rantai aplikasi/su dari Deck atau sesi interaktif:
# dari skrip lepas (orphan sesi SSH) perintah `am start/startservice` gagal
# dengan "Failure calling service activity: Failed transaction" (terbukti
# di uji resurrect-test 11 Nov 01:59) - konteks modul/Deck tidak.
cmd_resurrect() {
  if agent_alive; then echo "agen sudah hidup"; return 0; fi
  # Anak tangga 1: Termux hidup, agen mati -> RUN_COMMAND langsung.
  run_command_agent
  sleep 5
  if agent_alive; then log "resurrect: agen hidup via RUN_COMMAND"; echo "agen hidup (RUN_COMMAND)"; return 0; fi
  # Anak tangga 2: Termux berstatus stopped -> buka aktivitasnya dulu
  # (mencabut status stopped), lalu RUN_COMMAND lagi.
  /system/bin/am start -n com.termux/com.termux.app.TermuxActivity >/dev/null 2>&1
  sleep 4
  run_command_agent
  sleep 5
  if agent_alive; then log "resurrect: agen hidup via activity+RUN_COMMAND"; echo "agen hidup (activity+RUN_COMMAND)"; return 0; fi
  log "resurrect: GAGAL total"
  echo "agen belum hidup — buka Termux sekali secara manual"
  return 1
}

cmd_helper() {
  case "$1" in
    on)
      echo on > "$HELPERFILE"
      write_helper_mirror
      /system/bin/settings put secure always_on_vpn_app com.tailscale.ipn 2>/dev/null
      /system/bin/am start -n com.tailscale.ipn/.MainActivity >/dev/null 2>&1
      # sshd SENGAJA tidak dinyalakan dari sini: proses dari rantai
      # aplikasi/su jatuh ke domain SELinux su dan sshd-nya sakit
      # (menerima koneksi lalu menutup tanpa banner; terbukti 10 Nov
      # 17:40). Yang menyalakan sshd adalah watchdog modul (konteks
      # boot/init) <=30 detik setelah flag on, sama seperti pola mode.
      log "helper dihidupkan (deckctl)"
      echo "helper=on diterapkan"
      ;;
    off)
      echo off > "$HELPERFILE"
      write_helper_mirror
      /system/bin/settings delete secure always_on_vpn_app 2>/dev/null
      /system/bin/am force-stop com.tailscale.ipn 2>/dev/null
      kill_sshd_now
      log "helper dimatikan (deckctl)"
      echo "helper=off diterapkan"
      ;;
    *) get_helper ;;
  esac
}

case "$1" in
  helper) cmd_helper "$2" ;;
  mode)
    if [ -n "$2" ]; then
      case "$2" in
        ai|biasa)
          echo "$2" > "$MODEFILE"
          write_mirror "$2"
          log "mode diganti ke $2 (deckctl)"
          apply_mode
          if [ "$2" = "biasa" ] && [ "$(get_helper)" = "off" ]; then
            # Mode Biasa total (v1.4): proses Termux ikut dimatikan.
            # Hanya di jalur perintah mode eksplisit ini - BUKAN di
            # apply_mode/ensure yang dipanggil watchdog, supaya Termux
            # yang dibuka user untuk keperluan lain tidak ikut dibunuh.
            # Bila helper on, Termux dibiarkan hidup sebagai rumah sshd.
            sleep 2
            /system/bin/am force-stop com.termux 2>/dev/null
            log "mode biasa: Termux di-force-stop (helper off)"
            echo "mode=biasa diterapkan (Termux ikut dimatikan)"
          else
            echo "mode=$2 diterapkan"
          fi
          ;;
        *) echo "mode tidak dikenal: $2 (pakai ai|biasa)"; exit 1 ;;
      esac
    else
      get_mode
    fi
    ;;
  status) cmd_status ;;
  restart)
    [ "$(get_mode)" = "ai" ] || { echo "restart ditolak: mode biasa"; exit 1; }
    stop_stack
    sleep 2
    apply_mode
    echo "restart: stack diturunkan; agen Termux menaikkan lagi <=10 detik"
    ;;
  log)
    echo "--- deck.log ---"
    tail -n 30 "$LOGF" 2>/dev/null
    echo "--- gateway (ekor) ---"
    tail -n 15 "$ROOTFS/data/logs-gateway.txt" 2>/dev/null
    echo "--- router (ekor) ---"
    tail -n 10 "$ROOTFS/data/logs-router9.txt" 2>/dev/null
    echo "--- webui (ekor) ---"
    tail -n 10 "$ROOTFS/data/logs-webui.txt" 2>/dev/null
    ;;
  console) shift; cmd_console "$@" ;;
  ls) cmd_ls "$2" ;;
  cat) cmd_cat "$2" ;;
  cp) cmd_cp "$2" "$3" ;;
  put) cmd_put "$2" "$3" ;;
  ensure) apply_mode ;;   # dipakai watchdog modul
  stop) stop_stack ;;      # dipakai watchdog modul (mode biasa)
  resurrect) cmd_resurrect ;;   # v1.4: hidupkan agen Termux dari luar
  *) echo "pakai: deckctl mode [ai|biasa] | helper [on|off] | status | restart | resurrect | log | console <cmd> | ls [path] | cat <path> | cp <sumber> <tujuan> | put <staging> <tujuan>"; exit 1 ;;
esac
exit 0
