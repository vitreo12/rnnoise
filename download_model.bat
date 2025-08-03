@echo off
setlocal

REM ### SCRIPT CONFIGURATION ###
REM This script will fail immediately if any command fails.

REM 1. Read the model version hash from the 'model_version' file.
IF NOT EXIST model_version (
    echo ERROR: The 'model_version' file was not found.
    exit /b 1
)
set /p hash=<model_version

REM 2. Set the full model filename.
set "model=rnnoise_data-%hash%.tar.gz"
echo Model file to check: %model%


REM 3. Check if the model archive already exists. If not, download it.
if not exist "%model%" (
    echo Downloading latest model...
    
    REM Check if curl is available (standard on Win10/11)
    where /q curl
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: 'curl.exe' not found in your PATH.
        echo Please install curl or ensure it's accessible to download the model.
        exit /b 1
    )
    
    REM Use curl to download the file. -L follows redirects, -o specifies output file.
    curl -L -o "%model%" "https://media.xiph.org/rnnoise/models/%model%"
    
    REM Check if the download was successful
    if %ERRORLEVEL% NEQ 0 (
        echo ERROR: Download failed. Please check your network connection.
        del "%model%" 2>nul
        exit /b 1
    )
) else (
    echo Model file already exists locally.
)


REM 4. Validate the checksum using the built-in certutil.
echo.
echo Validating checksum...

REM The 'hash' variable contains the expected checksum.
REM We will generate the checksum of the downloaded file and compare.
set "expected_checksum=%hash%"
set "actual_checksum="

REM Use certutil to get the SHA256 hash. The 'FOR /F' loop parses its output.
REM It skips the first line of output and grabs the second line, which is the hash.
for /f "skip=1 tokens=1" %%A in ('certutil -hashfile "%model%" SHA256') do (
    if not defined actual_checksum set "actual_checksum=%%A"
)

if not defined actual_checksum (
    echo ERROR: Could not generate checksum for %model%.
    exit /b 1
)

echo Expected: %expected_checksum%
echo Actual:   %actual_checksum%

REM Compare the checksums (case-insensitive comparison with /I)
if /i "%expected_checksum%" NEQ "%actual_checksum%" (
    echo.
    echo ERROR: Aborting due to mismatching checksums!
    echo This could be caused by a corrupted download of %model%.
    echo Consider deleting the local copy of "%model%" and running this script again.
    exit /b 1
) else (
    echo Checksums match.
)


REM 5. Extract the archive using tar.
echo.
echo Extracting archive...

REM Check if tar is available (standard on Win10/11)
where /q tar
if %ERRORLEVEL% NEQ 0 (
    echo ERROR: 'tar.exe' not found in your PATH.
    echo On Windows, you can install it via WSL or use a tool like 7-Zip.
    exit /b 1
)

REM -x = extract, -z = decompress gzip, -v = verbose, -f = from file
tar -xzvf "%model%"

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to extract the archive "%model%".
    exit /b 1
)

echo.
echo Script completed successfully.

endlocal
