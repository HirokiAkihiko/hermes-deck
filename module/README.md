# Hermes Deck — Modul Magisk v2 (hermes_deck) + Aplikasi Deck

Paket kendali Hermes di whyred (Redmi Note 5, LineageOS A14, Magisk):

- **File mode = satu-satunya sumber kebenaran**: `/data/adb/hermes_deck/mode`
  berisi `ai` atau `biasa`. Aplikasi Deck dan CLI membaca/menulis file yang sama
  lewat skrip yang sama: `/data/adb/hermes_deck/deckctl.sh`.
- **Mode AI**: hardening KeepAlive ditegaskan (phantom-process mati persisten,
  whitelist Doze Termux+Tailscale, standby bucket active, appops background allow,
  cached-apps freezer disabled, Tailscale always-on VPN) + watchdog menjaga
  sshd, router 9router (20128), gateway Hermes, dan hermes-webui (8787) tetap hidup.
- **HP Biasa**: stack Hermes diturunkan bersih (gateway, router, webui dibunuh),
  watchdog tidak menaikkan lagi sampai mode diganti.

## Perintah (root, dari Termux/SSH)

```bash
su -c sh /data/adb/hermes_deck/deckctl.sh status        # mode,gateway,router,models,webui,tailscale,phantom
su -c sh /data/adb/hermes_deck/deckctl.sh mode biasa    # turunkan stack
su -c sh /data/adb/hermes_deck/deckctl.sh mode ai       # naikkan stack + hardening
su -c sh /data/adb/hermes_deck/deckctl.sh restart
su -c sh /data/adb/hermes_deck/deckctl.sh log
su -c sh /data/adb/hermes_deck/deckctl.sh console "hermes --version"
su -c sh /data/adb/hermes_deck/deckctl.sh ls            # jelajah /data distro
su -c sh /data/adb/hermes_deck/deckctl.sh cat logs-gateway.txt
```

## Arsitektur start (penting)

Stack TIDAK diluncurkan dari konteks root/modul: proses warisan rantai `su`
jatuh ke domain SELinux `su` dan gagal membuat socket (gateway tewas dengan
`PermissionError` saat membuat listener). Karena itu ada **agen Termux**
(`~/deck-agent.sh`, berjalan di domain aplikasi Termux, dinyalakan
Termux:Boot lewat `~/.termux/boot/02-deck-agent.sh`) yang membaca file
cermin `~/.deck-mode` dan menaikkan/menurunkan stack dari domain yang benar.
deckctl (root) menulis file kebenaran + cerminnya; penghentian stack boleh
dari root maupun agen. Watchdog modul root menjaga hardening + sshd saja.

## Komponen di HP

| Komponen | Lokasi |
|---|---|
| Modul Magisk `hermes_deck` | `/data/adb/modules/hermes_deck/` (service.sh = watchdog) |
| File mode + deckctl + log | `/data/adb/hermes_deck/` |
| hermes-webui | `/data/hermes-webui` di Ubuntu proot, port 8787 (localhost saja) |
| Password webui | `/data/.hermes/webui-password.txt` (600, hanya di HP) — salin juga ke PassVault |
| Skrip sesi router/webui | `/data/stack-router.sh`, `/data/stack-webui.sh` di distro |
| Agen Termux | `~/deck-agent.sh` di Termux + `~/.termux/boot/02-deck-agent.sh` |
| Aplikasi Deck | package `com.hiroki.hermesdeck`, keystore sendiri di proyek |

Catatan: Termux:Boot tetap menaikkan stack saat boot; bila mode terakhir
"biasa", watchdog modul menurunkannya lagi dalam ±30–60 detik setelah boot.
Modul user `hermes_keepalive` (kiriman user, ter-audit bersih) TIDAK diubah
paket ini dan tetap berdiri sendiri.

## Batas jujur

- Watchdog memeriksa tiap 30 detik; relaunch stack dibatasi cooldown 180 detik.
- Konsol Deck = tanya-jawab per perintah (timeout 120 dtk), bukan terminal live.
- Berkas AI v1: baca + salin saja.


## Changelog v2.4 / Deck v1.4 (11 Nov 2026)

Latar: whyred adalah HP harian user juga. Insiden 11 Nov 01:22 — Mode AI
diketuk saat Termux mati total: tidak terjadi apa-apa, karena agen
pengeksekusi stack tinggal di dalam proses Termux.

- **deckctl resurrect** (baru): menghidupkan deck-agent dari luar.
  Tangga 1: intent RUN_COMMAND Termux (Termux hidup, agen mati — gerbang
  `allow-external-apps = true` di termux.properties wajib; diset 11 Nov).
  Tangga 2: buka TermuxActivity (mencabut status stopped) lalu
  RUN_COMMAND lagi. Aplikasi memanggilnya otomatis ±10 detik sesudah
  Mode AI bila gateway belum naik, dan juga saat Mode AI diketuk ulang
  dalam keadaan stack mati.
- **Mode Biasa total**: sesudah stack turun, bila helper off deckctl
  me-force-stop com.termux — tidak ada proses AI/Termux tersisa. Sengaja
  hanya di jalur perintah mode eksplisit, bukan di ensure watchdog.
  Bila helper on, Termux dibiarkan hidup sebagai rumah sshd.
- **Agen keluar sendiri saat Mode Biasa** (termasuk loop IPC-nya).
- Perbaikan redireksi write_mirror/write_helper_mirror: 2>/dev/null
  dipindah sebelum > berkas; urutan lama membocorkan pesan
  "can't create …/.deck-helper" ke layar aplikasi dari konteks buta
  namespace (terlihat user 11 Nov 01:22).
- Pelajaran uji resurrect (11 Nov 01:32 & 01:59): `am start`/
  `am startservice` dari skrip lepas (orphan sesi SSH) gagal dengan
  "Failure calling service activity: Failed transaction (2147483646)"
  untuk start, sementara force-stop-nya bekerja — konteks pemanggil
  menentukan; jalur Deck (aplikasi → su → deckctl) adalah konteks yang
  terbukti untuk am (membuka Tailscale di helper on, 10 Nov).

## Changelog v2.3.1 (10 Nov 2026, patch deckctl saja)

- `helper on` tidak lagi menyalakan sshd langsung: sshd dari rantai
  aplikasi/su jatuh ke domain SELinux su dan sakit (koneksi diterima
  lalu ditutup tanpa banner — terbukti pada uji siklus 17:40). sshd
  kini murni tugas watchdog modul (konteks boot) <=30 detik sesudah
  flag on. Catatan lapangan uji yang sama: watchdog yang dinyalakan
  manual dari sesi SSH juga melahirkan sshd yang mati berulang —
  rantai proses bersih total kembali sesudah reboot berikutnya
  (watchdog dari boot). Bila SSH tak kembali sesudah Hidupkan,
  obatnya dari Termux: `pkill -9 sshd; sleep 1; sshd`.

## Changelog v2.3 / Deck v1.3 (10 Nov 2026)

- **Agen Pembantu** (akses jarak jauh) jadi saklar sendiri, default MATI:
  flag master `/data/adb/hermes_deck/helper` (on/off), cermin
  `~/.deck-helper` disinkronkan relay. `deckctl helper on` = pasang
  always-on VPN Tailscale + buka aplikasi Tailscale + nyalakan sshd;
  `helper off` = cabut always-on + force-stop Tailscale + bunuh sshd.
  Watchdog hanya menjaga sshd bila flag on; skrip boot Termux
  start-hermes.sh hanya menyalakan sshd bila cermin on (diedit di HP,
  bukan bagian zip). Beranda aplikasi dapat kartu Agen Pembantu +
  baris status SSH. Stack Hermes sendiri tidak tergantung flag ini —
  HP jalan mandiri penuh dengan helper mati.

## Changelog v2.2 / Deck v1.2 (10 Nov 2026)

- Konsol: perintah dibungkus env Hermes (HERMES_HOME + fungsi hermes ke
  venv) — `hermes --version`/`hermes status` kini jalan dari aplikasi.
- Explorer Berkas jadi sungguhan: tekan lama berkas/folder = Salin,
  tombol "Tempel di sini" di folder tujuan (anti-timpa: nama duplikat
  diberi akhiran (2), (3), ...), tombol "Unggah berkas" memakai pemilih
  berkas Android (SAF) lalu `deckctl put` menyalinnya ke folder /data
  yang sedang dibuka. Op IPC baru: cp, put (relay + deckctl).

## Changelog v2.1 / Deck v1.1 (10 Nov 2026)

Perbaikan bug v1.0 (kebutaan mount-namespace aplikasi + deckctl lambat):

- **relay.sh** (baru, jalan di konteks modul): menyinkronkan cermin mode
  master -> `~/.deck-mode` dua arah tiap ~2 detik (v2.0 hanya menyinkron ke
  `ai`, sehingga mode `biasa` bertarung dengan agen Termux dan stack flap),
  melayani IPC `ls`/`cat` langsung dan meneruskan `console` ke agen Termux,
  serta menulis cache jumlah model (`models-cache`).
- **deckctl v1.1**: pemindaian proses satu lintasan /proc untuk
  status/stop/restart; `console`/`ls`/`cat` otomatis lewat IPC bila rootfs
  Termux tidak terlihat dari konteks pemanggil (`DECK_FORCE_IPC=1` memaksa
  jalur IPC untuk pengujian); jumlah model jatuh ke cache relay.
- **deck-agent.sh**: loop eksekutor IPC konsol di domain Termux
  (`~/.deck-ipc/req|res`).
- **service.sh**: menyalin + menyalakan relay; cabang mode biasa kini ikut
  menyinkronkan cermin ke `biasa`.
- **Aplikasi v1.1**: saklar mode di-debounce (tombol mati selama perintah
  berjalan, ketukan pada mode yang sama diabaikan), refresh status tidak
  menumpuk, timeout status diperpanjang.
