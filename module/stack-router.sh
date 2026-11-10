#!/bin/bash
# Jalankan HANYA router 9router di sesi proot sendiri (foreground = sesi tertahan).
# Dipakai deckctl saat gateway hidup tapi router mati.
export NO_PROXY=127.0.0.1,localhost
NODE=/data/.hermes/tools/node-26.7.0-linux-arm64/bin/node
cd /data/9router || exit 1
exec "$NODE" custom-server.js --port 20128 >> /data/logs-router9.txt 2>&1
