:: ================================================================
::  BATCH SCRIPT FOR AUTOMATED PHOTOGRAMMETRY TRACKING WORKFLOW
::  v1.5 – Performance optimized + Resume từng bước
:: ================================================================
@echo off
setlocal EnableExtensions EnableDelayedExpansion

:: ---------- Resolve top-level folder (one up from this .bat) ----
pushd "%~dp0\.." >nul
set "TOP=%cd%"

:: ---------- Key paths -------------------------------------------
set "SFM_DIR=%TOP%\01 GLOMAP"
set "VIDEOS_DIR=%TOP%\02 VIDEOS"
set "FFMPEG_DIR=%TOP%\03 FFMPEG"
set "SCENES_DIR=%TOP%\04 SCENES"

:: ---------- Locate ffmpeg.exe -----------------------------------
if exist "%FFMPEG_DIR%\ffmpeg.exe" (
    set "FFMPEG=%FFMPEG_DIR%\ffmpeg.exe"
) else if exist "%FFMPEG_DIR%\bin\ffmpeg.exe" (
    set "FFMPEG=%FFMPEG_DIR%\bin\ffmpeg.exe"
) else (
    echo [ERROR] ffmpeg.exe not found inside "%FFMPEG_DIR%".
    popd & pause & goto :eof
)

:: ---------- Locate glomap.exe -----------------------------------
if exist "%SFM_DIR%\glomap.exe" (
    set "GLOMAP=%SFM_DIR%\glomap.exe"
) else if exist "%SFM_DIR%\bin\glomap.exe" (
    set "GLOMAP=%SFM_DIR%\bin\glomap.exe"
) else (
    echo [ERROR] glomap.exe not found inside "%SFM_DIR%".
    popd & pause & goto :eof
)

:: ---------- Locate colmap.exe -----------------------------------
if exist "%SFM_DIR%\colmap.exe" (
    set "COLMAP=%SFM_DIR%\colmap.exe"
) else if exist "%SFM_DIR%\bin\colmap.exe" (
    set "COLMAP=%SFM_DIR%\bin\colmap.exe"
) else (
    echo [ERROR] colmap.exe not found inside "%SFM_DIR%".
    popd & pause & goto :eof
)

:: ---------- Put binaries on PATH --------------------------------
set "PATH=%SFM_DIR%;%SFM_DIR%\bin;%PATH%"

:: ---------- Fix Qt platform plugin path (COLMAP 4.x) ------------
set "QT_QPA_PLATFORM_PLUGIN_PATH=%SFM_DIR%\plugins\platforms"

:: ---------- Ensure required folders exist -----------------------
if not exist "%VIDEOS_DIR%" (
    echo [ERROR] Input folder "%VIDEOS_DIR%" missing.
    popd & pause & goto :eof
)
if not exist "%SCENES_DIR%" mkdir "%SCENES_DIR%"

:: ---------- Count video files only (exclude non-video) ----------
set "TOTAL=0"
for %%V in ("%VIDEOS_DIR%\*.mp4" "%VIDEOS_DIR%\*.mov" "%VIDEOS_DIR%\*.avi" "%VIDEOS_DIR%\*.mkv" "%VIDEOS_DIR%\*.mxf") do (
    if exist "%%~fV" set /a TOTAL+=1
)
if "%TOTAL%"=="0" (
    echo [INFO] No video files found in "%VIDEOS_DIR%".
    popd & pause & goto :eof
)

echo ==============================================================
echo  Starting GLOMAP pipeline on %TOTAL% video(s) ...
echo ==============================================================

set /a IDX=0

for %%V in ("%VIDEOS_DIR%\*.mp4" "%VIDEOS_DIR%\*.mov" "%VIDEOS_DIR%\*.avi" "%VIDEOS_DIR%\*.mkv" "%VIDEOS_DIR%\*.mxf") do (
    if exist "%%~fV" (
        set /a IDX+=1
        call :PROCESS_VIDEO "%%~fV" !IDX! %TOTAL%
    )
)

echo --------------------------------------------------------------
echo  All jobs finished – results are in "%SCENES_DIR%".
echo --------------------------------------------------------------
popd
pause
goto :eof


:PROCESS_VIDEO
:: ----------------------------------------------------------------
::  %1 = full path to video   %2 = current index   %3 = total
:: ----------------------------------------------------------------
setlocal EnableDelayedExpansion

set "VIDEO=%~1"
set "NUM=%~2"
set "TOT=%~3"

for %%I in ("%VIDEO%") do (
    set "BASE=%%~nI"
    set "EXT=%%~xI"
)

echo.
echo [!NUM!/!TOT!] === Processing "!BASE!!EXT!" ===

:: -------- Directory layout for this scene -----------------------
set "SCENE=%SCENES_DIR%\!BASE!"
set "IMG_DIR=!SCENE!\images"
set "SPARSE_DIR=!SCENE!\sparse"
set "DB_PATH=!SCENE!\database.db"

if not exist "!SCENE!"      mkdir "!SCENE!"
if not exist "!IMG_DIR!"    mkdir "!IMG_DIR!"
if not exist "!SPARSE_DIR!" mkdir "!SPARSE_DIR!"

:: -------- 1) Extract frames -------------------------------------
if exist "!IMG_DIR!\frame_000001.jpg" (
    echo        [1/4] Skipping frame extraction – already done.
) else (
    echo        [1/4] Extracting frames ...
    "%FFMPEG%" -loglevel error -stats ^
        -i "!VIDEO!" ^
        -qscale:v 2 ^
        -threads 0 ^
        "!IMG_DIR!\frame_%%06d.jpg"
    if errorlevel 1 (
        echo        x FFmpeg failed – skipping "!BASE!".
        goto :END
    )
)

:: -------- 2) Feature extraction ---------------------------------
if exist "!SCENE!\done_features" (
    echo        [2/4] Skipping feature extraction – already done.
) else (
    echo        [2/4] COLMAP feature_extractor ...
    "%COLMAP%" feature_extractor ^
        --database_path "!DB_PATH!" ^
        --image_path    "!IMG_DIR!" ^
        --ImageReader.single_camera 1 ^
        --FeatureExtraction.use_gpu 1 ^
        --FeatureExtraction.max_image_size 2048 ^
        --FeatureExtraction.num_threads %NUMBER_OF_PROCESSORS%
    if errorlevel 1 (
        echo        x feature_extractor failed – skipping "!BASE!".
        goto :END
    )
    echo. > "!SCENE!\done_features"
)

:: -------- 3) Sequential matching --------------------------------
if exist "!SCENE!\done_matching" (
    echo        [3/4] Skipping sequential matching – already done.
) else (
    echo        [3/4] COLMAP sequential_matcher ...
    "%COLMAP%" sequential_matcher ^
        --database_path "!DB_PATH!" ^
        --SequentialMatching.overlap 15 ^
        --FeatureMatching.use_gpu 1 ^
        --FeatureMatching.num_threads %NUMBER_OF_PROCESSORS%
    if errorlevel 1 (
        echo        x sequential_matcher failed – skipping "!BASE!".
        goto :END
    )
    echo. > "!SCENE!\done_matching"
)

:: -------- 4) Sparse reconstruction ------------------------------
if exist "!SPARSE_DIR!\0\cameras.txt" (
    echo        [4/4] Skipping mapper – already reconstructed.
) else (
    echo        [4/4] GLOMAP mapper ...
    "%GLOMAP%" mapper ^
        --database_path "!DB_PATH!" ^
        --image_path    "!IMG_DIR!" ^
        --output_path   "!SPARSE_DIR!"
    if errorlevel 1 (
        echo        x glomap mapper failed – skipping "!BASE!".
        goto :END
    )
)

:: -------- Export TXT --------------------------------------------
if exist "!SPARSE_DIR!\0" (
    "%COLMAP%" model_converter ^
        --input_path  "!SPARSE_DIR!\0" ^
        --output_path "!SPARSE_DIR!\0" ^
        --output_type TXT >nul

    "%COLMAP%" model_converter ^
        --input_path  "!SPARSE_DIR!\0" ^
        --output_path "!SPARSE_DIR!" ^
        --output_type TXT >nul
)

echo        + Finished "!BASE!"  (!NUM!/!TOT!)

:END
endlocal & goto :eof