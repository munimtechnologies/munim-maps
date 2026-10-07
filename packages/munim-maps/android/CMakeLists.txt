project(NitroMunimMaps)
cmake_minimum_required(VERSION 3.9.0)

set (PACKAGE_NAME NitroMunimMaps)
set (CMAKE_VERBOSE_MAKEFILE ON)
set (CMAKE_CXX_STANDARD 20)

# Enable Raw Props parsing in react-native (for Nitro Views)
add_compile_options(-DRN_SERIALIZABLE_STATE=1)

# Define C++ library and add all sources
add_library(${PACKAGE_NAME} SHARED
        src/main/cpp/cpp-adapter.cpp
)

# Add Nitrogen specs :)
include(${CMAKE_SOURCE_DIR}/../nitrogen/generated/android/NitroMunimMaps+autolinking.cmake)

# Set up local includes
include_directories(
        "src/main/cpp"
        "../cpp"
)

find_library(LOG_LIB log)

# 16 KB page alignment (Android 15+ devices with 16 KB pages, Play requirement).
target_link_options(${PACKAGE_NAME} PRIVATE "-Wl,-z,max-page-size=16384" "-Wl,-z,common-page-size=16384")

# Link all libraries together
target_link_libraries(
        ${PACKAGE_NAME}
        ${LOG_LIB}
        android                                   # <-- Android core
)
