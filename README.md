# Dynamic Environment Device Changer (Pure Zygisk)

[![build](https://github.com/Ilham311/emulate/actions/workflows/build.yml/badge.svg)](https://github.com/Ilham311/emulate/actions/workflows/build.yml)

## Overview
Modul Magisk/KernelSU v5.0+ pure Zygisk untuk mengubah identitas device secara dinamis. Modul ini telah direwrite sepenuhnya dalam C++ dan menggunakan companion process untuk generate identity. Shell scripts sekarang minimal dan hanya memicu native CLI.

## Fitur
- **Pure-Zygisk Architecture:** Companion process di-spawn di root oleh Zygisk framework, handle atomic write dan UDS listener.
- **Embedded Pixel Pool:** Mendukung pool device Google Pixel tanpa memerlukan konfigurasi shell yang rumit.
- **Intercept Native Props:** Mendukung hook pada `SystemProperties.native_get()` untuk memalsukan read akses native libc (menutupi `ro.serialno`, `display.id`, dan `baseband`).
- **Hook Java `Build.*` Fields:** Menemulate 25 build property berbeda di JVM/JNI level.
- **Instant Rotate:** Putar device tanpa restart via CLI `envctl`.

## Struktur Repository
- `jni/`: Source code C++ Zygisk hook (`main.cpp`), Zygisk root companion (`companion.cpp`), dan CLI trigger (`envctl.c`).
- `prebuilt/`: Placeholder untuk external/prebuilt binaries seperti `resetprop-rs`.
- `module.prop`, `customize.sh`, dkk: File standar installer modul Magisk/KernelSU.
- `.github/workflows/`: Konfigurasi GitHub Action CI/CD (otomatis kompilasi ke 4 ABI via NDK r27b).

## Cara Build Lokal
```bash
# Set NDK location (wajib NDK r27b atau yang kompatibel)
export NDK=/path/to/android-ndk-r27b

# Ambil header zygisk.hpp (GitHub Actions sudah otomatis, untuk lokal butuh download)
curl -sSL https://raw.githubusercontent.com/topjohnwu/zygisk-module-sample/master/module/jni/zygisk.hpp \
     -o jni/zygisk.hpp

# Build menggunakan CMake per ABI
for abi in arm64-v8a armeabi-v7a x86_64 x86; do
  cmake -B build/$abi \
    -DCMAKE_TOOLCHAIN_FILE=$NDK/build/cmake/android.toolchain.cmake \
    -DANDROID_ABI=$abi -DANDROID_PLATFORM=android-26 \
    -DCMAKE_BUILD_TYPE=Release -S jni
  cmake --build build/$abi --parallel
done
```

## Memasukkan `resetprop-rs` (Prebuilt)
Binary `resetprop-rs` (Rust port dari Magisk resetprop) digunakan untuk apply properti boot-time. Jika kamu menggunakan GitHub action atau kompilasi lokal, modul masih dapat digunakan tanpanya (akan tampil sebagai warning saat instalasi).
Untuk dukungan penuh:
1. Download rilis `resetprop-rs` dari GitHub resmi atau ambil binary `resetprop` dari Magisk/KernelSU bundle terbaru.
2. Letakkan file tersebut di `prebuilt/resetprop-rs`
3. CI Actions akan secara otomatis meng-include-nya ke dalam `pkg/bin/resetprop-rs` jika terdeteksi, atau kamu dapat mencobanya lokal.

## Instalasi dan Penggunaan
1. Unduh rilis ZIP (`env-v5.0.0-pure-zygisk.zip`) dari GitHub Releases.
2. Copot pemasangan versi sebelumnya (seperti v4.13) dan **Reboot**.
3. Flash versi `v5.0.0` zip melalui menu Module Magisk/KernelSU dan **Reboot**.
4. Generate identitas pertama dengan menekan tombol **Action** di KSU Manager, atau jalankan via shell:
   ```bash
   su -c /data/adb/modules/dynamic_env_module/action.sh
   ```

### Command `envctl`
```bash
# Cek identitas sekarang
su -c /data/adb/modules/dynamic_env_module/bin/envctl status

# Putar ulang, namun biarkan SERIAL dan ANDROID_ID sama
su -c /data/adb/modules/dynamic_env_module/bin/envctl regenerate --keep-id

# Set persistent (FINGERPRINT random, serial/android id freeze)
su -c /data/adb/modules/dynamic_env_module/bin/envctl set-mode persistent

# Lock manual (cegah regenerate)
su -c /data/adb/modules/dynamic_env_module/bin/envctl set-mode locked
```

## Kredit
- `diru768` - Author
- [Zygisk](https://github.com/topjohnwu/Magisk) oleh John Wu
