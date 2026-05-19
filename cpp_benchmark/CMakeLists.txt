cmake_minimum_required(VERSION 3.20)
project(benchmark_app LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# On Windows with conda-forge, cmake config files live under $CONDA_PREFIX/Library.
# Pixi sets CONDA_PREFIX when activating the environment.
if(DEFINED ENV{CONDA_PREFIX})
    list(APPEND CMAKE_PREFIX_PATH "$ENV{CONDA_PREFIX}/Library")
endif()

find_package(Boost      REQUIRED)
find_package(Eigen3     REQUIRED NO_MODULE)
find_package(fmt        REQUIRED)
find_package(spdlog     REQUIRED)
find_package(nlohmann_json REQUIRED)
find_package(absl       CONFIG REQUIRED)
find_package(range-v3   CONFIG REQUIRED)

add_executable(benchmark_app src/main.cpp)

# Glob all module translation units (module_01.cpp … module_30.cpp)
file(GLOB MODULE_SOURCES src/module_*.cpp)
target_sources(benchmark_app PRIVATE ${MODULE_SOURCES})

target_link_libraries(benchmark_app PRIVATE
    Boost::headers
    Eigen3::Eigen
    fmt::fmt
    spdlog::spdlog
    nlohmann_json::nlohmann_json
    absl::strings
    absl::str_format
    range-v3::range-v3
)
