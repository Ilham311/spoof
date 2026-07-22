#!/usr/bin/env bash

set -euo pipefail

if [ -z "${NDK_HOME:-}" ] && [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "Error: NDK_HOME or ANDROID_NDK_HOME is not set."
    exit 1
fi

NDK="${NDK_HOME:-${ANDROID_NDK_HOME:-}}"

if [ ! -d "$NDK" ]; then
    echo "Error: Invalid NDK path: $NDK"
    exit 1
fi

API=26
ABIS=(arm64-v8a armeabi-v7a x86_64 x86)

cd "$(dirname "$0")"

for abi in "${ABIS[@]}"; do
    echo "Building for $abi..."
    cmake -S . -B "build/$abi" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DANDROID_STL=none

    cmake --build "build/$abi" -j"$(nproc)"

    cp "build/$abi/libternak_zygisk.so" "../module/zygisk/$abi.so"
done

echo "Build complete. File sizes:"
ls -lh ../module/zygisk/*.so
