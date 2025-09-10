# =============================================================================
# CMake configuration for rnnoise
# =============================================================================

cmake_minimum_required(VERSION 3.12)
project(rnnoise VERSION 0.4.1 LANGUAGES C)

# =============================================================================
# Options (mirrors configure script options)
# =============================================================================

option(BUILD_SHARED_LIBS "Build shared libraries instead of static libraries" OFF)
option(RNNOISE_ENABLE_ASSERTIONS "Enable assertions in code" OFF)
option(RNNOISE_ENABLE_DNN_DEBUG_FLOAT "Use floating-point DNN computation" OFF)
option(RNNOISE_BUILD_EXAMPLES "Build the rnnoise_demo example" OFF)

option(RNNOISE_ENABLE_SSE4_1 "Enable SSE4.1-optimized code paths" ON)
option(RNNOISE_ENABLE_AVX2 "Enable AVX2-optimized code paths" OFF)
option(RNNOISE_ENABLE_FMA "Enable FMA-optimized code paths (requires AVX2)" OFF)

# Use GNUInstallDirs for standard installation paths (e.g., lib, lib64)
include(GNUInstallDirs)

# =============================================================================
# Compiler and System Checks
# =============================================================================

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Check for alloca.h (for celt_lpc.c)
include(CheckIncludeFile)
check_include_file(alloca.h HAVE_ALLOCA_H)
if(NOT HAVE_ALLOCA_H)
    # MSVC has _alloca in malloc.h
    check_include_file(malloc.h HAVE_MALLOC_H)
    if (HAVE_MALLOC_H)
        set(HAVE_ALLOCA_H 1) # Signal that we found a usable equivalent
    endif()
endif()

# =============================================================================
# Configure config.h Header
# =============================================================================
# This section translates autoconf's AC_DEFINE into CMake settings that will
# populate config.h.in

set(RNNOISE_BUILD 1) # Always defined for a library build
if(RNNOISE_ENABLE_ASSERTIONS)
    set(OP_ENABLE_ASSERTIONS 1)
endif()
if(NOT RNNOISE_ENABLE_DNN_DEBUG_FLOAT)
    set(DISABLE_DEBUG_FLOAT 1)
endif()

# =============================================================================
# Define the rnnoise library
# =============================================================================

# Source files for the library, broken down by type
set(RNNOISE_SOURCES_CORE
    src/denoise.c
    src/rnn.c
    src/pitch.c
    src/kiss_fft.c
    src/celt_lpc.c
    src/nnet.c
    src/nnet_default.c
    src/parse_lpcnet_weights.c
    src/rnnoise_data.c
    src/rnnoise_tables.c
)

set(RNNOISE_SOURCES_RTCD
    src/x86/x86_dnn_map.c
    src/x86/x86cpu.c
)

set(RNNOISE_SOURCES_SSE4_1 src/x86/nnet_sse4_1.c)
set(RNNOISE_SOURCES_AVX2   src/x86/nnet_avx2.c)

# Create the library target from all sources
add_library(rnnoise
    ${RNNOISE_SOURCES_CORE}
    ${RNNOISE_SOURCES_RTCD}
)

add_library(RNNoise::rnnoise ALIAS rnnoise)

# Set library properties (e.g., versioning for shared libs)
set_target_properties(rnnoise PROPERTIES
    SOVERSION 0 # Corresponds to libtool's -version-info 4:1:4
    VERSION ${PROJECT_VERSION}
    WINDOWS_EXPORT_ALL_SYMBOLS ON  # Auto-export all symbols on Windows
)

# =============================================================================
# Include Directories and General Compile Options
# =============================================================================

target_include_directories(rnnoise
    PUBLIC
        $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
        $<INSTALL_INTERFACE:include>
    PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/src
        ${CMAKE_CURRENT_BINARY_DIR} # For config.h
)

# General compiler flags for the library, taken from Makefile's CFLAGS
if(MSVC)
    target_compile_options(rnnoise PRIVATE /W4 /wd4244 /wd4267 /wd4018 /wd4389)
    target_compile_definitions(rnnoise PRIVATE _CRT_SECURE_NO_WARNINGS)
else() # GCC / Clang
    target_compile_options(rnnoise PRIVATE
        -fvisibility=hidden
        -pedantic -Wall -Wextra -Wno-sign-compare -Wno-parentheses -Wno-long-long
    )
    # Link against the math library (-lm)
    target_link_libraries(rnnoise PRIVATE m)
endif()

target_compile_definitions(rnnoise PRIVATE CPU_INFO_BY_ASM)
target_compile_definitions(rnnoise PRIVATE RNN_ENABLE_X86_RTCD)

# =============================================================================
# SIMD Optimizations (SSE4.1, AVX2, FMA)
# =============================================================================
# Conditionally add sources and flags based on the RNNOISE_ENABLE_* options.

if(MSVC)
    # For MSVC, we set the highest required architecture level. /arch:AVX2
    # implies support for AVX and SSE. We must also manually define the
    # preprocessor macros that GCC/Clang set automatically.
    if(RNNOISE_ENABLE_AVX2)
        message(STATUS "Enabling AVX2 support (for MSVC)")
        target_compile_options(rnnoise PRIVATE /arch:AVX2)
        target_sources(rnnoise PRIVATE 
            ${RNNOISE_SOURCES_AVX2} 
            ${RNNOISE_SOURCES_SSE4_1}
        )
        target_compile_definitions(rnnoise PRIVATE 
            __AVX2__ 
            __AVX__ 
            __SSE4_1__ 
            __SSE2__ 
            __SSE__
        )
        if(RNNOISE_ENABLE_FMA)
            message(STATUS "Enabling FMA support (for MSVC)")
            target_compile_definitions(rnnoise PRIVATE __FMA__)
        endif()
    elseif(RNNOISE_ENABLE_SSE4_1)
        message(STATUS "Enabling SSE4.1 support (for MSVC)")
        target_compile_options(rnnoise PRIVATE /arch:AVX)
        target_sources(rnnoise PRIVATE 
            ${RNNOISE_SOURCES_SSE4_1}
        )
        target_compile_definitions(rnnoise PRIVATE 
            __AVX__ 
            __SSE4_1__ 
            __SSE2__ 
            __SSE__
        )
    else()
        message(STATUS "No x86 SIMD extensions enabled.")
    endif()
else() # GCC / Clang
    # For GCC/Clang, we add flags individually. The -m<ext> flags enable
    # code generation and define the appropriate preprocessor macros.
    if(RNNOISE_ENABLE_AVX2)
        message(STATUS "Enabling AVX2 support (for GCC/Clang)")
        target_compile_options(rnnoise PRIVATE -mavx2 -mavx -msse4.1)
        target_sources(rnnoise PRIVATE 
            ${RNNOISE_SOURCES_AVX2} 
            ${RNNOISE_SOURCES_SSE4_1}
        )
        if(RNNOISE_ENABLE_FMA)
            message(STATUS "Enabling FMA support (for GCC/Clang)")
            target_compile_options(rnnoise PRIVATE -mfma)
        endif()
    elseif(RNNOISE_ENABLE_SSE4_1)
        message(STATUS "Enabling SSE4.1 support (for GCC/Clang)")
        target_compile_options(rnnoise PRIVATE -msse4.1)
        target_sources(rnnoise PRIVATE 
            ${RNNOISE_SOURCES_SSE4_1}
        )
    else()
        message(STATUS "No x86 SIMD extensions enabled.")
    endif()
endif()

# =============================================================================
# EXAMPLES
# =============================================================================
if(RNNOISE_BUILD_EXAMPLES)
    add_executable(rnnoise_demo examples/rnnoise_demo.c)
    target_link_libraries(rnnoise_demo PRIVATE rnnoise)
endif()

# =============================================================================
# Installation Rules
# =============================================================================
# Install the public header
install(FILES include/rnnoise.h DESTINATION ${CMAKE_INSTALL_INCLUDEDIR})

# Install the library targets and runtime components (DLLs)
install(TARGETS rnnoise
    EXPORT rnnoise-targets
    ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)

# Install pkg-config file for compatibility
# (Requires rnnoise.pc.in from previous steps)
string(REPLACE "${CMAKE_INSTALL_PREFIX}/" "" CMAKE_INSTALL_LIBDIR_REL ${CMAKE_INSTALL_LIBDIR})
string(REPLACE "${CMAKE_INSTALL_PREFIX}/" "" CMAKE_INSTALL_INCLUDEDIR_REL ${CMAKE_INSTALL_INCLUDEDIR})
configure_file(rnnoise.pc.in rnnoise.pc @ONLY)
install(
    FILES "${CMAKE_CURRENT_BINARY_DIR}/rnnoise.pc"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/pkgconfig"
)

# This part is a value-add over the Makefile, making it easy for other
# CMake projects to use this library with `find_package(rnnoise)`.
include(CMakePackageConfigHelpers)
configure_package_config_file(
    cmake/rnnoise-config.cmake.in
    "${CMAKE_CURRENT_BINARY_DIR}/rnnoise-config.cmake"
    INSTALL_DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/rnnoise"
    PATH_VARS CMAKE_INSTALL_INCLUDEDIR CMAKE_INSTALL_LIBDIR
)
write_basic_package_version_file(
    "${CMAKE_CURRENT_BINARY_DIR}/rnnoise-config-version.cmake"
    VERSION ${PROJECT_VERSION}
    COMPATIBILITY AnyNewerVersion
)
install(
    FILES
        "${CMAKE_CURRENT_BINARY_DIR}/rnnoise-config.cmake"
        "${CMAKE_CURRENT_BINARY_DIR}/rnnoise-config-version.cmake"
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/rnnoise"
)
install(
    EXPORT rnnoise-targets
    FILE rnnoise-targets.cmake
    NAMESPACE RNNoise::
    DESTINATION "${CMAKE_INSTALL_LIBDIR}/cmake/rnnoise"
)