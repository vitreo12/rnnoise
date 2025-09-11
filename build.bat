@echo off
setlocal enabledelayedexpansion

:: ============================================================================
::  CMake Build Script for Windows and Cross-Compilation
:: ============================================================================
::  Usage:
::    build.bat [options...]
::
::  By default, this script builds for Windows x64 with AVX2 as the
::  maximum optimization level for modern CPUs.
::
::  Build Options:
::    /static               (Default) Build static libraries (.lib).
::    /shared               Build shared libraries (DLLs).
::
::  SIMD Options (for x86/x64 builds):
::    /fma                  Enable FMA, which also enables AVX2 and SSE4.1.
::    /noavx2               Disable AVX2 and FMA, building with SSE4.1 only.
::    /nosse4.1             Disable all SIMD (SSE4.1, AVX2, FMA) for max compatibility.
::
::  Platform Options:
::    /platform:<name>      Specify a platform name for the build. This sets
::                          the build directory to "build_<name>".
::    /toolchain:<path>     Required for custom platforms. Specifies the CMake
::                          toolchain file to use for cross-compilation.
::                          If the path contains spaces, enclose it in quotes.
::
::  Advanced Options:
::    /cflags:"<flags>"     Append additional C compiler flags. Useful for
::                          custom optimizations or warnings.
::    /cmake:<def>          Pass a custom CMake definition directly. Can be used
::                          multiple times. Example: /cmake:TargetEdition=241000
::
::  Examples:
::    :: Build for Windows with AVX2 (default)
::    build.bat
::
::    :: Build with AVX2 and FMA for the most modern CPUs
::    build.bat /fma
::
::    :: Build with only SSE4.1 for broader compatibility
::    build.bat /noavx2
::
::    :: Build a custom platform with a specific edition
::    build.bat /platform:my_embedded /toolchain:toolchains/my_tc.cmake /cmake:TargetEdition=241000
::
:: ============================================================================

:: --- Default values ---
set "SHARED_LIBS_VALUE=OFF"
set "TARGET_PLATFORM=windows"
set "TOOLCHAIN_FILE="
set "EXTRA_COMPILER_FLAGS="
set "CUSTOM_CMAKE_DEFS="

:: --- Pass 1: Determine Final SIMD State ---
:: We scan all arguments first to establish the definitive SIMD level.
:: This follows a strict hierarchy where more restrictive flags override less restrictive ones,
:: regardless of their order on the command line (e.g., /noavx2 will always beat /fma).
set "ALL_ARGS=%*"

:: Default state is AVX2 ON, FMA OFF
set "ENABLE_SSE41=ON"
set "ENABLE_AVX2=ON"
set "ENABLE_FMA=OFF"

echo "!ALL_ARGS!" | find /I "/nosse4.1" > nul
if errorlevel 1 (
    rem /nosse4.1 not found, check next level
    echo "!ALL_ARGS!" | find /I "/noavx2" > nul
    if errorlevel 1 (
        rem /noavx2 not found, check for fma
        echo "!ALL_ARGS!" | find /I "/fma" > nul
        if not errorlevel 1 (
            rem /fma was found, set state to AVX2+FMA
            set "ENABLE_SSE41=ON"
            set "ENABLE_AVX2=ON"
            set "ENABLE_FMA=ON"
        )
    ) else (
        rem /noavx2 was found, set state to SSE4.1 only
        set "ENABLE_SSE41=ON"
        set "ENABLE_AVX2=OFF"
        set "ENABLE_FMA=OFF"
    )
) else (
    rem /nosse4.1 was found, disable all SIMD
    set "ENABLE_SSE41=OFF"
    set "ENABLE_AVX2=OFF"
    set "ENABLE_FMA=OFF"
)


:: --- Pass 2: Parse All Arguments Robustly ---
:arg_loop
if "%~1"=="" goto :arg_loop_end

set "ARG_HANDLED="
set "CURRENT_ARG=%~1"

:: Use a FOR loop to robustly parse key:value arguments like /toolchain:"<path>"
for /f "tokens=1,* delims=:" %%G in ("!CURRENT_ARG!") do (
    if /I "%%G" == "/platform" (
        set "TARGET_PLATFORM=%%~H"
        set "ARG_HANDLED=1"
    )
    if /I "%%G" == "/toolchain" (
        set "TOOLCHAIN_FILE=%%~H"
        set "ARG_HANDLED=1"
    )
    if /I "%%G" == "/cflags" (
        set "EXTRA_COMPILER_FLAGS=%%~H"
        set "ARG_HANDLED=1"
    )
    if /I "%%G" == "/cmake" (
        set "CUSTOM_CMAKE_DEFS=!CUSTOM_CMAKE_DEFS! -D%%~H"
        set "ARG_HANDLED=1"
    )
)

:: Handle simple flag arguments if they weren't handled above
if not defined ARG_HANDLED (
    if /I "%~1" == "/static" (
        set "SHARED_LIBS_VALUE=OFF"
    ) else if /I "%~1" == "/shared" (
        set "SHARED_LIBS_VALUE=ON"
    ) else if /I "%~1" == "/nosse4.1" (
        rem Handled in Pass 1, do nothing here
    ) else if /I "%~1" == "/noavx2" (
        rem Handled in Pass 1, do nothing here
    ) else if /I "%~1" == "/fma" (
        rem Handled in Pass 1, do nothing here
    ) else (
        echo WARNING: Unknown argument "%~1". Ignoring.
    )
)

shift
goto :arg_loop
:arg_loop_end

:: --- Configure build based on parsed arguments ---
set "BUILD_DIR=build_!TARGET_PLATFORM!"
set "CMAKE_SIMD_ARGS=-DRNNOISE_ENABLE_SSE4_1=!ENABLE_SSE41! -DRNNOISE_ENABLE_AVX2=!ENABLE_AVX2! -DRNNOISE_ENABLE_FMA=!ENABLE_FMA!"
set "CMAKE_EXTRA_FLAGS_ARG="
if defined EXTRA_COMPILER_FLAGS (
    set "CMAKE_EXTRA_FLAGS_ARG=-DCMAKE_C_FLAGS_RELEASE="!EXTRA_COMPILER_FLAGS!""
)

if /I "!TARGET_PLATFORM!" == "windows" (
    :: This is a standard Windows build
    if defined TOOLCHAIN_FILE (
        echo ERROR: The /toolchain argument cannot be used with the default 'windows' platform.
        echo To use a toolchain, you must also specify a custom /platform:<name>.
        exit /b 1
    )
    set "CMAKE_ARGS=-A x64"
    set "BUILD_TARGET_NAME=Windows x64"
) else (
    :: This is a custom platform build
    if not defined TOOLCHAIN_FILE (
        echo ERROR: A /toolchain:<path> argument is required when specifying a custom platform.
        exit /b 1
    )
    if not exist "!TOOLCHAIN_FILE!" (
        echo ERROR: Toolchain file not found at the specified path:
        echo   "!TOOLCHAIN_FILE!"
        exit /b 1
    )
    set "CMAKE_ARGS=-DCMAKE_TOOLCHAIN_FILE="!TOOLCHAIN_FILE!""
    set "BUILD_TARGET_NAME=!TARGET_PLATFORM! (via Toolchain)"
)

echo Building for: !BUILD_TARGET_NAME!
if defined TOOLCHAIN_FILE ( echo   Toolchain: !TOOLCHAIN_FILE! )

set "BUILD_TYPE_NAME=static"
if /I "!SHARED_LIBS_VALUE!" == "ON" set "BUILD_TYPE_NAME=shared"
echo   Build type: !BUILD_TYPE_NAME!

set "SIMD_LEVEL=Generic"
if /I "!ENABLE_SSE41!" == "ON" set "SIMD_LEVEL=SSE4.1"
if /I "!ENABLE_AVX2!" == "ON" set "SIMD_LEVEL=AVX2"
if /I "!ENABLE_AVX2!" == "ON" if /I "!ENABLE_FMA!" == "ON" set "SIMD_LEVEL=AVX2 + FMA"
echo   SIMD Level: !SIMD_LEVEL!
if defined EXTRA_COMPILER_FLAGS ( echo   Extra Flags: !EXTRA_COMPILER_FLAGS! )
if defined CUSTOM_CMAKE_DEFS ( echo   Custom Defs:!CUSTOM_CMAKE_DEFS! )
echo.

if exist "!BUILD_DIR!" (
    echo --- Removing existing build directory: !BUILD_DIR!...
    rmdir /s /q "!BUILD_DIR!"
    if errorlevel 1 (
        echo ERROR: Failed to remove the build directory. It might be in use.
        exit /b 1
    )
)

echo --- Creating build directory: !BUILD_DIR!...
mkdir "!BUILD_DIR!"
if errorlevel 1 (
    echo ERROR: Failed to create the build directory.
    exit /b 1
)
cd "!BUILD_DIR!"

echo --- Configuring project with CMake...
cmake .. !CMAKE_ARGS! -DBUILD_SHARED_LIBS=!SHARED_LIBS_VALUE! !CMAKE_SIMD_ARGS! !CMAKE_EXTRA_FLAGS_ARG! !CUSTOM_CMAKE_DEFS!

if errorlevel 1 (
    echo.
    echo *** CMake configuration FAILED. Aborting script. ***
    exit /b %errorlevel%
)

echo --- Building project (Release configuration)...
cmake --build . --config Release

if errorlevel 1 (
    echo.
    echo *** Build FAILED. Aborting script. ***
    exit /b %errorlevel%
)

echo.
echo --- Build SUCCEEDED ---

cd ..
endlocal