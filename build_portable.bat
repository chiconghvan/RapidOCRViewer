@echo off
setlocal

rem ============================================================
rem  build_portable.bat - build Release x64 (with Tesseract) and
rem  package a portable (onedir) folder + zip in dist\
rem ============================================================

set "REPO=%~dp0"

rem --- locate MSBuild ---
set "MSBUILD="
if exist "%ProgramFiles(x86)%\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe" (
    set "MSBUILD=%ProgramFiles(x86)%\Microsoft Visual Studio\18\BuildTools\MSBuild\Current\Bin\amd64\MSBuild.exe"
)
if not defined MSBUILD (
    for /f "usebackq delims=" %%i in (`"%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe" -latest -products * -requires Microsoft.Component.MSBuild -find MSBuild\**\Bin\amd64\MSBuild.exe 2^>nul`) do set "MSBUILD=%%i"
)
if not defined MSBUILD (
    echo [ERROR] MSBuild not found. Install VS 2026 Build Tools.
    exit /b 1
)

echo [1/4] Building Release x64 (with HAVE_TESSERACT)...
"%MSBUILD%" "%REPO%vs2026\RapidOCRViewer.vcxproj" /p:Configuration=Release /p:Platform=x64 /m /v:m
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)

set "EXE=%REPO%vs2026\x64\Release\RapidOCRViewer.exe"
if not exist "%EXE%" (
    echo [ERROR] Exe not found: %EXE%
    exit /b 1
)

set "PORT=%REPO%dist\RapidOCRViewer-Portable"
set "OUT=%REPO%dist"
set "READMESAVED=%TEMP%\RapidOCRViewer-portable-readme"

rem --- preserve the two readme files (not tracked by git, only live in dist\) ---
if exist "%READMESAVED%" rmdir /S /Q "%READMESAVED%"
mkdir "%READMESAVED%" 2>nul
if exist "%PORT%\README_OCR.md"       copy /Y "%PORT%\README_OCR.md" "%READMESAVED%\" >nul
if exist "%PORT%\README_PORTABLE.txt" copy /Y "%PORT%\README_PORTABLE.txt" "%READMESAVED%\" >nul

echo [2/4] Creating portable folder...
if exist "%PORT%" rmdir /S /Q "%PORT%"
mkdir "%PORT%"
mkdir "%PORT%\tessdata"

copy /Y "%EXE%" "%PORT%\RapidOCRViewer.exe" >nul
copy /Y "%REPO%redist\*.dll" "%PORT%\" >nul
copy /Y "%REPO%tessdata\vie.traineddata" "%PORT%\tessdata\" >nul
copy /Y "%REPO%Changes.txt" "%PORT%\" >nul
copy /Y "%REPO%LICENSE" "%PORT%\LICENSE.txt" >nul

rem restore the readme files
if exist "%READMESAVED%\README_OCR.md"       copy /Y "%READMESAVED%\README_OCR.md" "%PORT%\" >nul
if exist "%READMESAVED%\README_PORTABLE.txt" copy /Y "%READMESAVED%\README_PORTABLE.txt" "%PORT%\" >nul

if not exist "%PORT%\README_OCR.md"       echo [WARN] README_OCR.md not found - skipped
if not exist "%PORT%\README_PORTABLE.txt" echo [WARN] README_PORTABLE.txt not found - skipped

echo [3/4] Zipping portable folder (flat, no base dir)...
powershell -NoProfile -Command "Add-Type -A System.IO.Compression.FileSystem; if (Test-Path '%OUT%\RapidOCRViewer-Portable.zip') { Remove-Item '%OUT%\RapidOCRViewer-Portable.zip' -Force }; [IO.Compression.ZipFile]::CreateFromDirectory('%PORT%', '%OUT%\RapidOCRViewer-Portable.zip', 'Optimal', $false)"
if errorlevel 1 (
    echo [ERROR] Zip failed.
    exit /b 1
)

echo [4/4] Done.
echo       Portable folder: %PORT%
echo       Zip archive:     %OUT%\RapidOCRViewer-Portable.zip

endlocal
