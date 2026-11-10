#!/data/data/com.termux/files/usr/bin/sh
# Boot stack Hermes (whyred). sshd hanya bila Agen Pembantu aktif:
# cermin flag ~/.deck-helper (disinkronkan relay dari master modul,
# default off). Selain itu boot seperti biasa: wake-lock + stack.
if [ "$(cat /data/data/com.termux/files/home/.deck-helper 2>/dev/null)" = "on" ]; then
  /data/data/com.termux/files/usr/bin/sshd
fi
/data/data/com.termux/files/usr/bin/termux-wake-lock
sleep 15
/data/data/com.termux/files/home/run-hermes.sh >> /data/data/com.termux/files/home/boot-hermes.log 2>&1
