# Rencana Perbaikan Hermes Deck v1.1
Disusun: 10 Nov 2026, ±16:20 WIB — mengambil alih diagnosis dari sesi WhatsApp.

## Masalah yang diperbaiki (dari laporan user + diagnosis WA)

1. **Kartu Mode AI tidak muncul** sampai menekan Mode HP Biasa.
2. **Mode HP Biasa tidak kunjung ter-apply** — UI menggantung di "sedang dijalankan".
3. **Konsol Hermes mati** — "rootfs tidak ditemukan".
4. **Berkas AI mati total** — "ls: bukan direktori".
Bonus: hitungan model terbaca 0 dari aplikasi, dan file cermin mode gagal ditulis dari aplikasi → master vs cermin bertarung → stack dibunuh-dihidupkan berulang (kejadian 15:55–16:11).

## Akar masalah (terbukti dari log + tangkapan layar user)

- **A. Kebutaan mount-namespace dari aplikasi.** deckctl yang dipanggil aplikasi lewat `su` tidak bisa melihat `/data/data/com.termux/**`. Semua fungsi yang jalurnya lewat direktori privat Termux mati dari aplikasi (tulis cermin, konsol, ls/cat, hitung model), tapi normal dari SSH/Termux dan dari service modul.
- **B. deckctl lambat.** Status/stop memindai seluruh `/proc` berulang kali per pola; di SD636 satu panggilan bisa semenit lebih. UI menyerah duluan, user mengetuk berulang, mode tertulis berkali-kali.

## Desain perbaikan v1.1

### 1. Relay root sebagai jembatan namespace (obat akar A)
- Tambahkan loop relay ringan di konteks modul (service.sh, namespace global — konteks ini terbukti bisa melihat direktori Termux).
- Relay menyalin file master `/data/adb/hermes_deck/mode` → cermin `~/.deck-mode` tiap siklus. **Cermin tidak lagi ditulis deckctl dari konteks aplikasi** — satu penulis, satu arah: master → cermin. Kelas bug "dua pengendali bertarung" hilang.
- Fungsi Konsol/Berkas dialihkan lewat antrean berkas di `/data/adb/hermes_deck/ipc/` (bisa ditulis semua konteks root):
  - deckctl/aplikasi menulis berkas permintaan (console/ls/cat + argumen).
  - Relay meneruskan permintaan ke agen Termux (menulis ke direktori home Termux yang terlihat dari konteks relay), agen menjalankan dari domain Termux, hasil ditulis balik, relay menyalin hasil ke `ipc/out` untuk dibaca aplikasi.
  - Timeout + id permintaan agar UI tidak menggantung tanpa kabar.

### 2. Pindai proses satu lintasan (obat akar B)
- Ganti `proc_has`/`pids_matching` per-pola dengan **satu lintasan** `/proc` yang mengumpulkan semua cmdline sekali, lalu semua pola (gateway, router, webui, tailscale) dicocokkan dari hasil tangkapan yang sama.
- `status` dan `stop` memakai tangkapan yang sama — target: status selesai dalam hitungan detik, bukan menit.

### 3. UI aplikasi (Kotlin, keystore Deck yang sama)
- Saklar mode: nonaktifkan tombol selama perintah berjalan + indikator jelas; cegah ketukan berulang menulis mode berkali-kali (debounce di sisi aplikasi).
- Penyegaran status memakai hasil IPC dengan timeout yang jujur (tampilkan "memeriksa…" lalu hasil, bukan kartu kosong).

## Yang TIDAK berubah
- Package `com.hiroki.hermesdeck`, keystore `deck.keystore` (cert e9579220…) — update bisa ditimpa tanpa copot.
- Arsitektur agen Termux sebagai penegak mode tetap; file master tetap sumber kebenaran tunggal.
- Modul KeepAlive lama user tidak disentuh.

## Urutan kerja saat digas
1. Ubah deckctl.sh (satu lintasan + IPC klien) + service.sh (relay) di `~/workspace/hermes-deck-module/`.
2. Ubah deck-agent.sh (eksekutor IPC) di sisi Termux.
3. Ubah MainActivity.kt (debounce + status via IPC), build APK v1.1 dengan build.sh + keystore lama.
4. Pasang: modul diperbarui + APK ditimpa; uji: ganti mode dua arah, Konsol, Berkas, hitungan model, lalu uji reboot.
5. Kriteria lulus: status < 10 dtk dari aplikasi; Konsol & Berkas jalan dari aplikasi; mode tertulis tepat satu kali per ketukan; tidak ada baris "stack diturunkan/diluncurkan" berulang selama 10 menit Mode AI diam.

## Status saat rencana ini ditulis
- Stabilisasi manual SELESAI 10 Nov 16:14 WIB (perintah user di chat utama): `deckctl mode ai` dari SSH → master = cermin = `ai`.
- Verifikasi 16:16–16:21 WIB: gateway/router/webui/Tailscale semua up, phantom maksimum, Telegram Connected, router menjawab katalog, webui HTTP 302. Nol baris flap baru sejak 16:14 (sebelumnya siklus bunuh-hidup tiap ±2–3 menit).
- Bug v1.0 di aplikasi tetap ada — jangan mengetuk saklar mode berulang; kalau UI macet, tunggu, jangan ditekan-tekan. Kendali aman sementara: CLI deckctl dari SSH/Termux.


## HASIL PEMBANGUNAN (10 Nov 2026, 16:24–16:31 WIB) — SELESAI & TERPASANG

Dibangun dan dipasang oleh agen chat utama atas perintah user "Gas bangun Deck v1.1":

- **APK HermesDeck v1.1** (versionCode 2, cert sama e9579220… → ditimpa bersih):
  `HermesDeck-v1.1.apk`, SHA-256 `8de04bee…f306`. Debounce saklar mode +
  refresh status anti-tumpuk + timeout status 90 dtk.
- **Modul hermes_deck v2.1**: `HermesDeck-Module-v2.1.zip`, SHA-256
  `e0b7a8de…8cf`. Isi terpasang langsung ke HP (backup v1.0/v2.0 di
  `/data/adb/deck-backup-v10/`); zip untuk arsip/pemasangan ulang.
- **relay.sh jalan** (pid tercatat di deck.log 16:25:28): sinkron cermin dua
  arah + IPC + cache model (5655 terbaca).
- **deckctl status: 0,63 detik** (sebelumnya ±60 detik) — snapshot kini satu
  panggilan `ps` toybox, bukan belasan lintasan /proc.
- **Uji IPC paksa (DECK_FORCE_IPC=1) LULUS**: ls 3,4 dtk, cat utuh,
  console `echo` kembali dalam 5,5 dtk lewat rantai relay → agen → proot.
- **Uji mode dua arah LULUS**: biasa → cermin ikut `biasa`, gateway/router/
  webui turun bersih, Tailscale tetap up; ai → semua naik, Telegram
  Connected baru 16:30:34 WIB, log mode tertulis tepat satu kali per perintah.
- Belum diuji: tampilan aplikasi v1.1 dari sisi user (buka aplikasi, coba
  Konsol/Berkas/Mode dari layar) dan uji reboot dengan susunan v2.1.

- **Uji reboot susunan v2.1: LULUS (10 Nov 16:43–16:49 WIB)** — watchdog
  mulai 16:47:08, relay menyala sendiri dari service.sh (pid 4181), agen
  mulai 16:47:49, Telegram Connected baru 16:49:06, status akhir semua up.
  Tersisa hanya uji aplikasi dari sisi user (Konsol/Berkas/saklar di layar).

- **Lanjutan 10 Nov sore (permintaan user 17:04)**: konsol diperbaiki
  (env Hermes), webui + dashboard 9router tanpa password (requireLogin
  false; backup DB di HP), dan **Deck v1.2 / modul v2.2** terbit:
  explorer Berkas dengan Salin/Tempel/Unggah (op IPC cp/put) — teruji.
