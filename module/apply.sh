#!/system/bin/sh
# Hermes Deck - tegaskan hardening KeepAlive (idempotent, aman diulang).
# Sama dengan hardening manual 10 Nov 03:50 + modul KeepAlive v1.

TX=com.termux
TS=com.tailscale.ipn

/system/bin/device_config set_sync_disabled_for_tests persistent 2>/dev/null
/system/bin/device_config put activity_manager max_phantom_processes 2147483647 2>/dev/null
/system/bin/cmd deviceidle whitelist +$TX >/dev/null 2>&1
/system/bin/cmd deviceidle whitelist +$TS >/dev/null 2>&1
/system/bin/am set-standby-bucket $TX active >/dev/null 2>&1
/system/bin/am set-standby-bucket $TS active >/dev/null 2>&1
/system/bin/cmd appops set $TX RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
/system/bin/cmd appops set $TS RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
/system/bin/settings put global cached_apps_freezer disabled >/dev/null 2>&1
/system/bin/settings put secure always_on_vpn_app $TS >/dev/null 2>&1
/system/bin/settings put secure always_on_vpn_lockdown 0 >/dev/null 2>&1
exit 0
