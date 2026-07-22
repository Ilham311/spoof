#!/usr/bin/env bash
set -euo pipefail

if [ -z "${NDK_HOME:-}" ] && [ -z "${ANDROID_NDK_HOME:-}" ]; then
    echo "Error: NDK_HOME or ANDROID_NDK_HOME must be set"
    exit 1
fi

NDK_PATH="${NDK_HOME:-${ANDROID_NDK_HOME:-}}"

if [ ! -d "$NDK_PATH" ]; then
    echo "Error: NDK_PATH '$NDK_PATH' is not a valid directory"
    exit 1
fi

CLANGXX="$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64/bin/clang++"
if [ ! -x "$CLANGXX" ]; then
    echo "Error: clang++ not found at '$CLANGXX' (NDK installation looks incomplete)"
    exit 1
fi

API=26
ABIS=("arm64-v8a" "armeabi-v7a" "x86_64" "x86")

mkdir -p ../module/zygisk

for abi in "${ABIS[@]}"; do
    echo "Building for $abi..."
    cmake -S . -B "build/$abi" \
        -DCMAKE_TOOLCHAIN_FILE="$NDK_PATH/build/cmake/android.toolchain.cmake" \
        -DANDROID_ABI="$abi" \
        -DANDROID_PLATFORM="android-$API" \
        -DCMAKE_BUILD_TYPE=MinSizeRel \
        -DANDROID_STL=none

    cmake --build "build/$abi" -j"$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"

    cp "build/$abi/libternak_zygisk.so" "../module/zygisk/$abi.so"
done

echo "Build complete. Output sizes:"
ls -lh ../module/zygisk/*.so
