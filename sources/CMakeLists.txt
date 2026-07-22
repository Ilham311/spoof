cmake_minimum_required(VERSION 3.22.1)

project(ternak_zygisk CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_C_STANDARD 17)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

add_compile_options(
    -Wall
    -Wextra
    -Wno-unused-parameter
    -Os
    -fvisibility=hidden
    -fvisibility-inlines-hidden
    -ffunction-sections
    -fdata-sections
    -fno-exceptions
    -fno-rtti
    -fno-stack-protector
    -fomit-frame-pointer
    -fno-unwind-tables
    -fno-asynchronous-unwind-tables
)

add_link_options(
    -Wl,--gc-sections
    -Wl,--exclude-libs,ALL
    -Wl,--build-id=none
    -Wl,-z,max-page-size=16384
    -Wl,--hash-style=both
    -Wl,-z,now
    -Wl,-z,relro
    -s
)

add_library(ternak_zygisk SHARED jni/main.cpp)

set_property(TARGET ternak_zygisk PROPERTY INTERPROCEDURAL_OPTIMIZATION TRUE)

target_link_libraries(ternak_zygisk log)
