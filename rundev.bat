@echo off
setlocal

rem ============================================================
rem  rundev.bat - build Debug x64 (with Tesseract) and run RapidOCRViewer
rem
rem  Builds Debug|x64 which now compiles with HAVE_TESSERACT
rem  (see vs2026\RapidOCRViewer.vcxproj, Debug|x64 PreprocessorDefinitions).
rem  After the build it copies the Tesseract/Leptonica runtime DLLs from
rem  redist\ next to the exe so the OCR engine can load when the
rem  ocr_engine.cpp code changes.
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

echo [1/3] Building Debug x64 (with HAVE_TESSERACT)...
"%MSBUILD%" "%REPO%vs2026\RapidOCRViewer.vcxproj" /p:Configuration=Debug /p:Platform=x64 /m /v:m
if errorlevel 1 (
    echo [ERROR] Build failed.
    exit /b 1
)

set "EXE=%REPO%vs2026\x64\Debug\RapidOCRViewer.exe"
if not exist "%EXE%" (
    echo [ERROR] Exe not found: %EXE%
    exit /b 1
)

echo [2/3] Copying Tesseract/Leptonica runtime DLLs next to exe...
set "OUTDIR=%REPO%vs2026\x64\Debug"
if exist "%REPO%redist\*.dll" (
    copy /Y "%REPO%redist\*.dll" "%OUTDIR%\" >nul
    echo       Copied redist DLLs to %OUTDIR%
) else (
    echo [WARN] redist\*.dll not found - OCR runtime DLLs will not be copied.
)

if not exist "%OUTDIR%\tessdata\vie.traineddata" (
    if exist "%REPO%tessdata\vie.traineddata" (
        mkdir "%OUTDIR%\tessdata" 2>nul
        copy /Y "%REPO%tessdata\vie.traineddata" "%OUTDIR%\tessdata\" >nul
        echo       Copied tessdata\vie.traineddata
    )
)

echo [3/3] Starting %EXE%
start "" "%EXE%"

endlocal
