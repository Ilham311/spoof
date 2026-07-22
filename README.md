# Ternak Device Changer (shell + Zygisk)

[![Build](https://github.com/diru768/ternak-repo/actions/workflows/build.yml/badge.svg)](https://github.com/diru768/ternak-repo/actions)

## Overview
Ternak Device Changer adalah modul Magisk/KernelSU tingkat lanjut yang menggabungkan kemampuan shell script (`ternak_core_v4.sh`) dengan modul Zygisk C++ untuk melakukan spoofing identitas perangkat yang komprehensif, ditargetkan per-aplikasi.

## Fitur
- **Zygisk Hooking**: Melakukan spoofing pada field `android.os.Build` dan `android.os.Build$VERSION` pada proses yang ditargetkan tanpa memodifikasi sistem secara keseluruhan.
- **Targeting Per-Aplikasi**: Konfigurasi aplikasi mana yang akan di-spoof melalui `/data/adb/modules/ternak_device_changer/hook_targets.txt`. Mendukung wildcard suffix (`*`).
- **Kompatibilitas**: Mendukung PlayIntegrityFix, membaca properti spoof dari `/data/adb/modules/ternak_device_changer/spoof.prop` atau fallback ke `pif.prop`.
- **Ringan**: Dibuat menggunakan C++ dan JNI mentah, tanpa pustaka eksternal yang berat.
- **Mendukung Android 15**: Dikompilasi dengan dukungan 16KB page size.

## Struktur
- `module/`: Berisi file-file yang akan di-flash sebagai modul Magisk/KernelSU. (Tambahkan `post-fs-data.sh`, `ternak_core_v4.sh`, dan `bin/resetprop-rs` secara manual di sini).
- `sources/`: Source code C++ dan script build untuk modul Zygisk.

## Cara build lokal
1. Pastikan Anda memiliki Android NDK (r26 atau r27 direkomendasikan) dan CMake terinstal.
2. Setel environment variable `NDK_HOME` atau `ANDROID_NDK_HOME`.
3. Jalankan script build:
   ```bash
   ./sources/build.sh
   ```
4. Hasil build `.so` akan berada di `module/zygisk/`.

## Cara build via GitHub Actions
1. Fork atau push repositori ini ke GitHub.
2. GitHub Actions akan otomatis melakukan build setiap kali ada push ke branch `main` atau pull request.
3. Anda dapat mengunduh file `.zip` hasil build pada tab "Actions" di bagian "Artifacts".
4. Untuk merilis, buat tag dengan awalan `v` (misal: `v4.12.0`), dan rilis akan otomatis dibuat dengan file `.zip` terlampir.

## Cara flash
1. Unduh file `.zip` hasil rilis atau artifact.
2. (Opsional) Jika Anda mem-build sendiri, pastikan untuk meletakkan `post-fs-data.sh`, `ternak_core_v4.sh`, dan `bin/resetprop-rs` ke dalam direktori `module/` dan memaketkannya:
   ```bash
   cd module
   zip -r ../ternak_device_changer.zip .
   ```
3. Buka Magisk Manager atau KernelSU Manager.
4. Pergi ke tab Modules.
5. Pilih "Install from storage" dan pilih file `ternak_device_changer.zip`.
6. Reboot perangkat Anda.

## Verifikasi hook with logcat example
Anda dapat memverifikasi apakah modul Zygisk berhasil melakukan spoofing pada aplikasi target menggunakan `logcat`:

```bash
su -c "logcat -s TernakZygisk:*"
```

Contoh output yang diharapkan:
```
I/TernakZygisk(12345): com.shopee.id: 15 Build fields spoofed
I/TernakZygisk(12346): com.tokopedia.tkpd: 15 Build fields spoofed
```

## Kredit
- dikembangkan oleh `diru768`
- ZygiskNext dan Magisk
- Komunitas untuk riset spoofing identitas perangkat.
