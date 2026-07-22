cmake_minimum_required(VERSION 3.22.1)
project(ternak_zygisk C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Zygote fork setiap app baru = SO ini ke-load di TIAP proses.
# Ukuran & startup cost harus seminim mungkin.
add_library(ternak_zygisk SHARED
    jni/main.cpp
)

target_include_directories(ternak_zygisk PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/jni
)

target_compile_options(ternak_zygisk PRIVATE
    -Wall -Wextra -Wno-unused-parameter
    -Os
    -fvisibility=hidden -fvisibility-inlines-hidden
    -ffunction-sections -fdata-sections
    -fno-exceptions -fno-rtti
    -fno-stack-protector
    -fomit-frame-pointer
    -fno-unwind-tables -fno-asynchronous-unwind-tables
)

target_link_options(ternak_zygisk PRIVATE
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,--build-id=none
    -Wl,-z,max-page-size=16384          # Android 15 / Pixel 8+ page-size compat
    -Wl,--hash-style=both
    -Wl,-z,now -Wl,-z,relro
    -s                                   # strip
)

target_link_libraries(ternak_zygisk PRIVATE
    log
)

# LTO — pangkas SO lebih kecil lagi
set_property(TARGET ternak_zygisk PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)

# Output nama SO tanpa "lib" prefix (opsional; Zygisk terima keduanya)
set_target_properties(ternak_zygisk PROPERTIES
    OUTPUT_NAME "ternak_zygisk"
    PREFIX "lib"
)