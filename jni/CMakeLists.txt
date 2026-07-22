cmake_minimum_required(VERSION 3.18)
project(ternak_zygisk LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# Size + hide-symbols optimization
set(COMMON_FLAGS "-Os -fvisibility=hidden -ffunction-sections -fdata-sections")
set(CMAKE_CXX_FLAGS_RELEASE "${COMMON_FLAGS} -fvisibility-inlines-hidden -fno-exceptions -fno-rtti")
set(CMAKE_C_FLAGS_RELEASE   "${COMMON_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_RELEASE
    "-Wl,--gc-sections -Wl,--strip-all -Wl,--exclude-libs,ALL")
set(CMAKE_EXE_LINKER_FLAGS_RELEASE
    "-Wl,--gc-sections -Wl,--strip-all")

# ============================================================
# libternak.so — main hook + companion (single .so)
# ============================================================
add_library(ternak SHARED
    main.cpp
    companion.cpp
)
target_include_directories(ternak PRIVATE ${CMAKE_SOURCE_DIR})
target_link_libraries(ternak PRIVATE log)

# Zygisk framework expects the .so at /data/adb/modules/<id>/zygisk/<ABI>.so
# The GitHub Actions job renames libternak.so → <ABI>.so when packaging.

# ============================================================
# ternakctl — CLI trigger binary
# ============================================================
add_executable(ternakctl ternakctl.c)
# No extra libs needed — pure POSIX socket + libc.
