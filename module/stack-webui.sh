#!/bin/bash
# Jalankan hermes-webui (port 8787) di sesi proot sendiri, foreground.
# Password dibaca dari /data/.hermes/webui-password.txt (chmod 600, hanya di HP).
export HERMES_HOME=/data/.hermes
export HERMES_WEBUI_AGENT_DIR=/data/.hermes/hermes-agent
export HERMES_WEBUI_HOST=127.0.0.1
export HERMES_WEBUI_PORT=8787
export NO_PROXY=127.0.0.1,localhost
if [ -f /data/.hermes/webui-password.txt ]; then
  HERMES_WEBUI_PASSWORD=$(cat /data/.hermes/webui-password.txt)
  export HERMES_WEBUI_PASSWORD
fi
cd /data/hermes-webui || exit 1
exec /data/.hermes/arm-venv/bin/python bootstrap.py --foreground >> /data/logs-webui.txt 2>&1
