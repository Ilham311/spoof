cmake_minimum_required(VERSION 3.22.1)
project(env LANGUAGES C CXX)

set(CMAKE_C_STANDARD   11)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_options(
    -Os
    -fvisibility=hidden
    -ffunction-sections
    -fdata-sections
    -fno-exceptions
    -fno-rtti
)
add_link_options(
    -Wl,--gc-sections
    -Wl,--strip-all
)

add_library(env SHARED main.cpp companion.cpp)
target_link_libraries(env log)

add_executable(envctl envctl.c)
