@echo off
setlocal

rem ============================================================
rem  build_installer.bat - build Release x64 (with Tesseract) and
rem  compile the NSIS installer (nsis\installer.nsi) into the repo
rem  root (RapidOCRViewer-<version>.<x64>.<lang>-Setup.exe).
rem
rem  Usage:  build_installer.bat [lang]
rem          lang = Chinese (default) | English
rem ============================================================

set "REPO=%~dp0"
set "LANG=%~1"
if "%LANG%"=="" set "LANG=Chinese"

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

rem --- locate makensis (NSIS) ---
set "MAKENSIS="
if exist "%ProgramFiles(x86)%\NSIS\makensis.exe" (
    set "MAKENSIS=%ProgramFiles(x86)%\NSIS\makensis.exe"
)
if not defined MAKENSIS (
    for /f "usebackq delims=" %%i in (`where makensis.exe 2^>nul`) do if not defined MAKENSIS set "MAKENSIS=%%i"
)
if not defined MAKENSIS (
    echo [ERROR] NSIS makensis.exe not found.
    echo         Install NSIS from https://nsis.sourceforge.io/Download and
    echo         either add it to PATH or install to Program Files^(x86^)\NSIS.
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

echo [2/4] Running installer build from nsis\ (makensis needs CWD there)...
pushd "%REPO%nsis"

echo [3/4] makensis /DVS_VERSION=vs2026 /DBUILD_CONFIG=Release /Dx64 /DLANG=%LANG% installer.nsi
"%MAKENSIS%" /DVS_VERSION=vs2026 /DBUILD_CONFIG=Release /Dx64 /DLANG=%LANG% installer.nsi
if errorlevel 1 (
    popd
    echo [ERROR] NSIS build failed.
    exit /b 1
)

rem installer.nsi emits the setup exe into the CWD (nsis\) - move it to repo root
for %%f in (RapidOCRViewer-*-Setup.exe) do (
    if exist "%%f" move /Y "%%f" "%REPO%\" >nul
)
popd

echo [4/4] Done. Installer written to repo root:
for %%f in ("%REPO%RapidOCRViewer-*-Setup.exe") do echo       %%~nxf

endlocal
