@echo off
setlocal

:: ============================================================================
::  CMake Build Script for Windows
:: ============================================================================
::  Usage:
::    build.bat [option]
::
::  Options:
::    /static   (Default) Build static libraries (.lib). Sets BUILD_SHARED_LIBS=OFF.
::    /shared   Build shared libraries (DLLs). Sets BUILD_SHARED_LIBS=ON.
::
:: ============================================================================

set "SHARED_LIBS_VALUE=OFF"

if /I "%~1" == "/static" set "SHARED_LIBS_VALUE=OFF"
if /I "%~1" == "/shared" set "SHARED_LIBS_VALUE=ON"

echo Building with BUILD_SHARED_LIBS=%SHARED_LIBS_VALUE%
echo.

if exist build_windows (
    echo --- Removing existing build directory...
    rmdir /s /q build_windows
    if errorlevel 1 (
        echo ERROR: Failed to remove the build directory. It might be in use by another program.
        exit /b 1
    )
)

echo --- Creating build directory...
mkdir build_windows
if errorlevel 1 (
    echo ERROR: Failed to create the build directory.
    exit /b 1
)
cd build_windows

echo --- Configuring project with CMake...
cmake .. -A x64 -DBUILD_SHARED_LIBS=%SHARED_LIBS_VALUE%

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
