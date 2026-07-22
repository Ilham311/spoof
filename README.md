# Ternak Device Changer (shell + Zygisk)

[![build](https://github.com/Ilham311/spoof/actions/workflows/build.yml/badge.svg)](https://github.com/Ilham311/spoof/actions/workflows/build.yml)

## Overview
Modul Magisk/KernelSU untuk mengubah identitas device (spoofing) di level shell dan JNI. Modul ini menggabungkan script shell-level identity forge dengan companion C++ Zygisk yang melakukan hooking pada field `android.os.Build` secara spesifik per-target aplikasi.

## Fitur
- **Zygisk C++ Hook:** Hooking dinamis pada `android.os.Build` dan `android.os.Build$VERSION`.
- **Per-Target App:** Menargetkan aplikasi tertentu (mendukung akhiran wildcard `*`).
- **Dynamic Spoof Loading:** Membaca properti spoofing secara real-time pada setiap peluncuran aplikasi tanpa memerlukan reboot.
- **Kompatibilitas:** Mendukung Zygisk-Next (KernelSU) dan stock Magisk Zygisk.
- **Efisiensi:** Dibuild menggunakan C++20/C17 dengan ukuran file `.so` yang sangat kecil (< 50KB per ABI).

## Struktur
- `module/`: Berisi file-file yang akan di-flash sebagai modul Magisk/KernelSU. (User harus menambahkan `post-fs-data.sh`, `ternak_core_v4.sh`, dan `bin/resetprop-rs`).
- `sources/`: Source code C++ JNI dan build script untuk Zygisk companion.
- `.github/workflows/`: Konfigurasi CI/CD untuk build otomatis dengan GitHub Actions.

## Cara build lokal
1. Pastikan Anda memiliki Android NDK terinstal.
2. Set environment variable `NDK_HOME` atau `ANDROID_NDK_HOME`.
3. Jalankan script build:
   ```bash
   cd sources
   ./build.sh
   ```
4. File `.so` akan otomatis disalin ke `module/zygisk/`.

## Cara build via GitHub Actions
1. Fork atau clone repository ini.
2. Push ke branch `main`.
3. GitHub Actions akan otomatis mem-build modul dan menghasilkan file zip yang dapat diunduh di tab "Actions".
4. Untuk merilis versi baru, buat dan push tag yang diawali dengan `v` (contoh: `v4.12`). Release akan otomatis dibuat dengan file zip terlampir.

## Cara flash
1. Pastikan Anda sudah menyiapkan struktur folder `module/` dengan lengkap (tambahkan script shell companion Anda).
2. Zip isi folder `module/` (bukan folder `module`-nya).
3. Flash via Magisk atau KernelSU.
4. Reboot perangkat.

## Verifikasi hook with logcat
Anda dapat memverifikasi apakah hook berjalan dan properti di-spoof menggunakan logcat.

```bash
adb logcat -s TernakZygisk:*
```

Contoh output yang diharapkan saat membuka aplikasi target:
```
TernakZygisk: com.shopee.id: 4 Build fields spoofed
```

## Kredit
- `diru768` - Author
- [Zygisk](https://github.com/topjohnwu/Magisk) oleh John Wu
