#!/system/bin/sh
# Hermes Deck - relay modul (v1.1). Jalan di konteks modul/root dengan
# namespace global, tempat direktori Termux TERLIHAT. Menjembatani pemanggil
# yang buta namespace (aplikasi Deck via su):
#   1. Sinkron cermin mode: file master -> ~/.deck-mode (agen Termux),
#      dua arah nilai (ai maupun biasa), tiap siklus ~2 detik.
#      (Watchdog v2.0 hanya menyinkron ke "ai" - itulah sumber pertarungan
#      master vs cermin yang membuat stack flap.)
#   2. IPC Berkas/Konsol: layani /data/adb/hermes_deck/ipc/req/*.req
#      - ls/cat dieksekusi langsung di sini (rootfs terlihat dari konteks ini)
#      - console diteruskan ke agen Termux (~/.deck-ipc) yang menjalankan
#        proot dari domain aplikasi; hasil disalin kembali ke ipc/res.
#   3. Cache jumlah model dari log router -> /data/adb/hermes_deck/models-cache
# Dinyalakan oleh service.sh. Singleton via pidfile + cek cmdline.

DECKDIR=/data/adb/hermes_deck
MODEFILE=$DECKDIR/mode
TXHOME=/data/data/com.termux/files/home
TXUID=10194
ROOTFS=/data/data/com.termux/files/usr/var/lib/proot-distro/containers/ubuntu/rootfs
IPC=$DECKDIR/ipc
AIPC=$TXHOME/.deck-ipc
LOGF=$DECKDIR/deck.log
PIDF=$DECKDIR/relay.pid

mkdir -p "$IPC/req" "$IPC/res" "$DECKDIR" 2>/dev/null

if [ -f "$PIDF" ]; then
  _old=$(cat "$PIDF" 2>/dev/null)
  if [ -n "$_old" ] && [ -r "/proc/$_old/cmdline" ] && \
     tr '\0' ' ' < "/proc/$_old/cmdline" 2>/dev/null | grep -q "relay.sh"; then
    exit 0
  fi
fi
echo $$ > "$PIDF"

log() { echo "$(date '+%Y-%m-%d %H:%M:%S') relay: $*" >> "$LOGF" 2>/dev/null; }
log "relay mulai (pid $$)"

safe_data_path() {
  rel="$1"
  case "$rel" in ""|"." ) echo "$ROOTFS/data"; return 0 ;; esac
  case "$rel" in *".."*|/*) return 1 ;; esac
  echo "$ROOTFS/data/$rel"
}

copy_target() { # $1=dir-tujuan-abs $2=basename -> path bebas (anti-timpa)
  _t="$1/$2"; _n=2
  while [ -e "$_t" ]; do _t="$1/$2 ($_n)"; _n=$((_n + 1)); done
  echo "$_t"
}

write_res() { # $1=id $2=code $3=file-output
  { echo "$2"; cat "$3" 2>/dev/null; } > "$IPC/res/$1.tmp" 2>/dev/null
  mv "$IPC/res/$1.tmp" "$IPC/res/$1.res" 2>/dev/null
}

handle_req() {
  _f="$1"
  _id=$(basename "$_f" .req)
  _op=$(sed -n '1p' "$_f" 2>/dev/null)
  _arg=$(sed -n '2,$p' "$_f" 2>/dev/null)
  _out="$IPC/res/$_id.out"
  case "$_op" in
    ls)
      _p=$(safe_data_path "$_arg") || { echo "ls: path ditolak" > "$_out"; write_res "$_id" 1 "$_out"; }
      if [ -n "$_p" ]; then
        if [ -d "$_p" ]; then
          : > "$_out"
          for e in "$_p"/* "$_p"/.*; do
            [ -e "$e" ] || continue
            name=${e##*/}
            [ "$name" = "." ] || [ "$name" = ".." ] && continue
            if [ -d "$e" ]; then echo "$name/"; else echo "$name"; fi >> "$_out"
          done
          write_res "$_id" 0 "$_out"
        else
          echo "ls: bukan direktori: $_arg" > "$_out"; write_res "$_id" 1 "$_out"
        fi
      fi
      ;;
    cat)
      _p=$(safe_data_path "$_arg") || { echo "cat: path ditolak" > "$_out"; write_res "$_id" 1 "$_out"; }
      if [ -n "$_p" ]; then
        if [ -f "$_p" ]; then
          head -c 65536 "$_p" > "$_out" 2>/dev/null
          write_res "$_id" 0 "$_out"
        else
          echo "cat: bukan file: $_arg" > "$_out"; write_res "$_id" 1 "$_out"
        fi
      fi
      ;;
    cp)
      _src_rel=$(printf '%s\n' "$_arg" | sed -n '1p')
      _dst_rel=$(printf '%s\n' "$_arg" | sed -n '2p')
      _s=$(safe_data_path "$_src_rel"); _d=$(safe_data_path "$_dst_rel")
      if [ -z "$_s" ] || [ -z "$_d" ] || [ ! -e "$_s" ] || [ ! -d "$_d" ]; then
        echo "cp: sumber/tujuan tidak valid" > "$_out"; write_res "$_id" 1 "$_out"
      else
        _t=$(copy_target "$_d" "${_s##*/}")
        if cp -r "$_s" "$_t" 2>/dev/null; then
          echo "tersalin: ${_t#$ROOTFS/data/}" > "$_out"; write_res "$_id" 0 "$_out"
        else
          echo "cp: gagal menyalin" > "$_out"; write_res "$_id" 1 "$_out"
        fi
      fi
      ;;
    put)
      _stage=$(printf '%s\n' "$_arg" | sed -n '1p')
      _dst_rel=$(printf '%s\n' "$_arg" | sed -n '2p')
      _d=$(safe_data_path "$_dst_rel")
      if [ -z "$_d" ] || [ ! -d "$_d" ] || [ ! -f "$_stage" ]; then
        echo "put: staging/tujuan tidak valid" > "$_out"; write_res "$_id" 1 "$_out"
      else
        _t=$(copy_target "$_d" "${_stage##*/}")
        if cp "$_stage" "$_t" 2>/dev/null; then
          echo "terunggah: ${_t#$ROOTFS/data/}" > "$_out"; write_res "$_id" 0 "$_out"
        else
          echo "put: gagal menyalin" > "$_out"; write_res "$_id" 1 "$_out"
        fi
      fi
      ;;
    console)
      mkdir -p "$AIPC/req" "$AIPC/res" 2>/dev/null
      cp "$_f" "$AIPC/req/$_id.req" 2>/dev/null && chown $TXUID:$TXUID "$AIPC/req/$_id.req" 2>/dev/null
      # Tunggu agen di subshell latar agar loop utama (sinkron cermin)
      # tidak ikut tertahan selama konsol berjalan.
      (
        _w=0
        while [ ! -f "$AIPC/res/$_id.res" ] && [ "$_w" -lt 140 ]; do
          sleep 1; _w=$((_w + 1))
        done
        if [ -f "$AIPC/res/$_id.res" ]; then
          cp "$AIPC/res/$_id.res" "$IPC/res/$_id.tmp" 2>/dev/null
          mv "$IPC/res/$_id.tmp" "$IPC/res/$_id.res" 2>/dev/null
          rm -f "$AIPC/res/$_id.res" "$AIPC/req/$_id.req" 2>/dev/null
        else
          echo "ipc: agen Termux tidak menjawab (140 dtk)" > "$_out"
          write_res "$_id" 1 "$_out"
          rm -f "$AIPC/req/$_id.req" 2>/dev/null
        fi
      ) &
      ;;
    *)
      echo "ipc: op tidak dikenal: $_op" > "$_out"
      write_res "$_id" 1 "$_out"
      ;;
  esac
  rm -f "$_out" 2>/dev/null
}

CYCLE=0
while true; do
  # 1. Sinkron cermin mode (master adalah sumber kebenaran tunggal)
  _m=$(cat "$MODEFILE" 2>/dev/null)
  case "$_m" in ai|biasa) ;; *) _m=ai ;; esac
  _cur=$(cat "$TXHOME/.deck-mode" 2>/dev/null)
  if [ "$_cur" != "$_m" ]; then
    echo "$_m" > "$TXHOME/.deck-mode.tmp" 2>/dev/null && \
      mv "$TXHOME/.deck-mode.tmp" "$TXHOME/.deck-mode" 2>/dev/null
    chown $TXUID:$TXUID "$TXHOME/.deck-mode" 2>/dev/null
  fi
  # 1b. Sinkron cermin helper (master -> ~/.deck-helper; dibaca skrip boot)
  _h=$(cat "$DECKDIR/helper" 2>/dev/null)
  case "$_h" in on) ;; *) _h=off ;; esac
  _curh=$(cat "$TXHOME/.deck-helper" 2>/dev/null)
  if [ "$_curh" != "$_h" ]; then
    echo "$_h" > "$TXHOME/.deck-helper.tmp" 2>/dev/null && \
      mv "$TXHOME/.deck-helper.tmp" "$TXHOME/.deck-helper" 2>/dev/null
    chown $TXUID:$TXUID "$TXHOME/.deck-helper" 2>/dev/null
  fi
  # 2. Layani permintaan IPC
  for _f in "$IPC/req"/*.req; do
    [ -e "$_f" ] || continue
    handle_req "$_f"
    rm -f "$_f"
  done
  # 3. Cache jumlah model tiap ~30 detik
  CYCLE=$((CYCLE + 1))
  if [ $((CYCLE % 15)) = "0" ]; then
    _line=$(tail -c 300000 "$ROOTFS/data/logs-router9.txt" 2>/dev/null | grep "modelCatalog" | tail -1)
    _n=$(echo "$_line" | sed -n 's/.*modelCatalog\] \([0-9][0-9]*\) models.*/\1/p')
    [ -n "$_n" ] && echo "$_n" > "$DECKDIR/models-cache" 2>/dev/null
  fi
  sleep 2
done
