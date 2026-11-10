#!/system/bin/sh
# Hermes Deck - installer modul hermes_deck.

ui_print "- Hermes Deck v2.1 (Mode AI / HP Biasa + KeepAlive + Relay IPC)"
ui_print "- File mode: /data/adb/hermes_deck/mode (default: ai)"

DECKDIR=/data/adb/hermes_deck
mkdir -p "$DECKDIR"
[ -f "$DECKDIR/mode" ] || echo ai > "$DECKDIR/mode"
cp "$MODPATH/deckctl.sh" "$DECKDIR/deckctl.sh"
cp "$MODPATH/apply.sh" "$DECKDIR/apply.sh"
cp "$MODPATH/relay.sh" "$DECKDIR/relay.sh"

set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/apply.sh" 0 0 0755
set_perm "$MODPATH/deckctl.sh" 0 0 0755
set_perm "$MODPATH/relay.sh" 0 0 0755
set_perm "$DECKDIR/deckctl.sh" 0 0 0755
set_perm "$DECKDIR/apply.sh" 0 0 0755
set_perm "$DECKDIR/relay.sh" 0 0 0755

ui_print "- Kendali: su -c sh /data/adb/hermes_deck/deckctl.sh status"
ui_print "- Reboot sekali agar watchdog modul mulai jalan,"
ui_print "  atau jalankan service.sh manual dari root."
