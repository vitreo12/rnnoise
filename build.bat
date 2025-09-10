@echo off
setlocal enabledelayedexpansion

:: ============================================================================
::  CMake Build Script for Windows and Cross-Compilation
:: ============================================================================
::  Usage:
::    build.bat [options...]
::
::  By default, this script builds for Windows x64 with SSE4.1 as the
::  maximum optimization level for wide compatibility.
::
::  Build Options:
::    /static               (Default) Build static libraries (.lib).
::    /shared               Build shared libraries (DLLs).
::
::  SIMD Options (for x86/x64 builds):
::    /avx2                 Enable AVX2 optimizations (implies SSE4.1).
::    /fma                  Enable FMA and AVX2 optimizations (implies both).
::    /nosse4.1             Disable all SIMD optimizations for maximum portability.
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
::
::  Examples:
::    :: Build for Windows with SSE4.1 (default)
::    build.bat
::
::    :: Build with AVX2 and FMA for a modern CPU
::    build.bat /fma
::
:: ============================================================================

:: --- Default values ---
set "SHARED_LIBS_VALUE=OFF"
set "TARGET_PLATFORM=windows"
set "TOOLCHAIN_FILE="
set "ENABLE_SSE41=ON"
set "ENABLE_AVX2=OFF"
set "ENABLE_FMA=OFF"
set "EXTRA_COMPILER_FLAGS="

:: --- Parse command line arguments ---
:arg_loop
if "%~1"=="" goto :arg_loop_end

set "ARG_HANDLED="
set "CURRENT_ARG=%~1"

:: Use a FOR loop to robustly parse key:value arguments like /toolchain:<path>
:: This correctly handles quotes around the value part.
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
)

:: Handle simple flag arguments if they weren't handled above
if not defined ARG_HANDLED (
    if /I "%~1" == "/static" (
        set "SHARED_LIBS_VALUE=OFF"
    ) else if /I "%~1" == "/shared" (
        set "SHARED_LIBS_VALUE=ON"
    ) else if /I "%~1" == "/nosse4.1" (
        set "ENABLE_SSE41=OFF"
        set "ENABLE_AVX2=OFF"
        set "ENABLE_FMA=OFF"
    ) else if /I "%~1" == "/avx2" (
        set "ENABLE_AVX2=ON"
    ) else if /I "%~1" == "/fma" (
        set "ENABLE_AVX2=ON"
        set "ENABLE_FMA=ON"
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
cmake .. !CMAKE_ARGS! -DBUILD_SHARED_LIBS=!SHARED_LIBS_VALUE! !CMAKE_SIMD_ARGS! !CMAKE_EXTRA_FLAGS_ARG!

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