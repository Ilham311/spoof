cmake_minimum_required(VERSION 3.22.1)

project(ternak_zygisk CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_C_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(COMMON_COMPILE_OPTIONS
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

set(COMMON_LINK_OPTIONS
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

target_compile_options(ternak_zygisk PRIVATE ${COMMON_COMPILE_OPTIONS})
target_link_options(ternak_zygisk PRIVATE ${COMMON_LINK_OPTIONS})

target_link_libraries(ternak_zygisk log)

set_target_properties(ternak_zygisk PROPERTIES INTERPROCEDURAL_OPTIMIZATION TRUE)
