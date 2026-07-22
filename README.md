# Dynamic Environment Module (Pure Zygisk)

[![build](https://github.com/Ilham311/emulate/actions/workflows/build.yml/badge.svg)](https://github.com/Ilham311/emulate/actions/workflows/build.yml)

Halo! 👋 Selamat datang di repositori **Dynamic Environment Module**.

Modul ini adalah alat canggih (tapi gampang dipakai) untuk perangkat Android yang sudah di-root dengan Magisk atau KernelSU. Fungsinya simpel: **mengubah identitas perangkat kamu secara dinamis**.

Pernah butuh mengetes aplikasi seolah-olah kamu pakai HP yang berbeda? Atau butuh merotasi identitas device tanpa harus ribet edit konfigurasi manual? Modul ini jawabannya. Kami menggunakan arsitektur *Pure-Zygisk* yang ringan, bersih, dan ditulis sepenuhnya menggunakan C++ sehingga super ngebut dan aman.

---

## 🧐 Bagaimana Cara Kerjanya? (How It Works)

Daripada pakai script bash/shell lawas yang gampang ketahuan, modul ini bekerja langsung di jantung Android menggunakan **Zygisk**.

1. **Root Companion Process:** Saat sistem nyala, modul ini menjalankan *daemon* kecil di latar belakang yang berjalan sebagai root.
2. **Hooking Java & Native:** Modul akan mencegat (hook) permintaan dari aplikasi saat mereka mencoba membaca identitas HP kamu (seperti `Build.MODEL`, `ro.serialno`, sidik jari, dll).
3. **Emulasi Real-time:** Identitas yang dibaca oleh aplikasi akan diganti (emulate) secara *on-the-fly* menggunakan profil Google Pixel asli yang sudah tertanam di dalam modul. Semuanya terjadi dalam sekejap mata.

---

## 📋 Syarat Pemasangan (Requirements)

Sebelum mulai instalasi, pastikan HP kamu sudah memenuhi syarat berikut:
- **Akses Root**: Menggunakan Magisk atau KernelSU (KSU).
- **Zygisk Aktif**:
  - Jika pakai Magisk: pastikan Zygisk sudah dihidupkan di pengaturan Magisk.
  - Jika pakai KernelSU: pastikan kamu sudah menginstal modul tambahan seperti ZygiskNext atau ReZygisk.

*(Opsional)* **resetprop-rs**: Untuk hasil emulasi maksimal sampai ke level *boot-time*, disarankan untuk menaruh binary `resetprop-rs` (bisa diambil dari rilis Magisk terbaru) ke dalam folder `prebuilt/` saat kamu mengunduh *source code*. Namun jika kamu pengguna biasa, cukup pakai file rilis ZIP yang sudah disediakan.

---

## 🚀 Panduan Instalasi (How to Install)

Gampang banget kok! Proses instalasinya sama persis seperti kamu menginstal modul Magisk/KSU pada umumnya:

1. Pergi ke halaman [Releases](https://github.com/Ilham311/emulate/releases) dan unduh file `.zip` terbaru (contoh: `env-v5.0.0-pure-zygisk.zip`).
2. Jika kamu punya versi lama dari modul ini, pastikan untuk menghapusnya (uninstall) terlebih dahulu dan **Restart/Reboot** HP kamu.
3. Buka aplikasi **Magisk** atau **KernelSU**.
4. Masuk ke menu **Modules**, lalu pilih **Install from storage**.
5. Pilih file `.zip` yang baru saja kamu unduh.
6. Tunggu proses flashing selesai, lalu klik **Reboot**.

Selesai! Modul sekarang sudah aktif.

---

## 🛠️ Cara Menggunakan (How to Use)

Setelah HP kamu menyala kembali, saatnya membuat identitas pertamamu.

**Cara paling gampang:**
Buka aplikasi Magisk/KSU Manager, masuk ke menu *Modules*, lalu tekan tombol **Action** di modul ini.

**Cara pro (lewat Terminal/Termux):**
Kamu bisa mengatur semuanya dengan cepat menggunakan perintah `envctl` (Environment Controller) lewat terminal.

Buka aplikasi terminal kesayanganmu (seperti Termux), masuk sebagai root dengan mengetik `su`, lalu jalankan perintah berikut sesuai kebutuhan:

```bash
# Mengecek status identitas yang sedang dipakai saat ini
su -c /data/adb/modules/dynamic_env_module/bin/envctl status

# Merotasi/mengganti perangkat secara acak (membuat identitas baru yang fresh)
su -c /data/adb/modules/dynamic_env_module/bin/envctl regenerate

# Mengganti perangkat, TAPI membiarkan Serial Number dan Android ID tetap sama
su -c /data/adb/modules/dynamic_env_module/bin/envctl regenerate --keep-id

# Mengatur ke mode "Persistent"
# (Setiap restart/regenerate, Sidik Jari akan acak, tapi Serial/Android ID dikunci)
su -c /data/adb/modules/dynamic_env_module/bin/envctl set-mode persistent

# Mengunci identitas secara manual (mencegah identitas terganti secara tidak sengaja)
su -c /data/adb/modules/dynamic_env_module/bin/envctl set-mode locked
```

---

## 🏆 Kredit

- **diru768** - Pembuat Modul Original
- **John Wu** - Kreator [Magisk](https://github.com/topjohnwu/Magisk) dan arsitektur Zygisk yang luar biasa
