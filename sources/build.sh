#!/usr/bin/env bash
# build.sh — build ternak_zygisk untuk semua ABI Android modern.
# Butuh: Android NDK r26+ terpasang, env NDK_HOME.
set -euo pipefail

NDK="${NDK_HOME:-${ANDROID_NDK_HOME:-}}"
[ -z "$NDK" ] && { echo "Set NDK_HOME atau ANDROID_NDK_HOME"; exit 1; }
[ -e "$NDK/build/cmake/android.toolchain.cmake" ] || { echo "NDK invalid: $NDK"; exit 1; }
chmod -R a+x "$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin" 2>/dev/null || true

# Beberapa action (misal nttld/setup-ndk) mengekstrak NDK ke direktori yang
# namanya berbeda dari folder asli (mis. "r27c" alih-alih "android-ndk-r27c").
# Akibatnya symlink clang/clang++ di dalam NDK -- yang memakai path relatif
# menunjuk ke nama folder asli -- menjadi broken symlink ("not a full path to
# an existing compiler tool"). Perbaiki dengan membuat ulang symlink tersebut
# agar menunjuk ke target yang benar relatif terhadap $NDK saat ini.
BIN_DIR="$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin"
if [ -d "$BIN_DIR" ]; then
    for link in "$BIN_DIR"/clang "$BIN_DIR"/clang++; do
        [ -L "$link" ] || continue
        [ -e "$link" ] && continue
        target="$(readlink "$link")"
        case "$target" in
            */toolchains/*)
                fixed="$NDK/toolchains/${target#*/toolchains/}"
                [ -e "$fixed" ] && ln -sf "$fixed" "$link"
                ;;
        esac
    done
fi

API=26                                   # min Android 8 (Zygisk sendiri butuh 26+)
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)
OUT="../module/zygisk"
mkdir -p "$OUT"

for abi in "${ABIS[@]}"; do
    echo ">>> Building $abi"
    rm -rf "build/$abi"
    cmake -S . -B "build/$abi" -G Ninja \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM="android-$API" \
        -DANDROID_STL=none \
        -DCMAKE_BUILD_TYPE=MinSizeRel
    cmake --build "build/$abi" -j
    cp "build/$abi/libternak_zygisk.so" "$OUT/$abi.so"
    ls -lh "$OUT/$abi.so"
done

echo ">>> Done. SO tersedia di $OUT/"