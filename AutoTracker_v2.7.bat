:: ================================================================
::  BATCH SCRIPT FOR AUTOMATED PHOTOGRAMMETRY TRACKING WORKFLOW
::  v1.7 – Full setup wizard + Resume từng bước
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
set "SCRIPT_DIR=%TOP%\05 SCRIPT"
set "TUNE_CACHE=%SCRIPT_DIR%\device_tune.cfg"

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
if not exist "%SCRIPT_DIR%" mkdir "%SCRIPT_DIR%"

:: ---------- Load config or run setup wizard ---------------------
if exist "%TUNE_CACHE%" (
    for /f "usebackq tokens=1,2 delims==" %%A in ("%TUNE_CACHE%") do (
        if "%%A"=="USE_GPU"       set "OPT_GPU=%%B"
        if "%%A"=="THREADS"       set "OPT_THREADS=%%B"
        if "%%A"=="IMG_SIZE"      set "OPT_IMG_SIZE=%%B"
        if "%%A"=="JPEG_QUALITY"  set "OPT_JPEG=%%B"
        if "%%A"=="EXTRACT_FPS"   set "OPT_FPS=%%B"
        if "%%A"=="MAX_FEATURES"  set "OPT_FEATURES=%%B"
        if "%%A"=="OVERLAP"       set "OPT_OVERLAP=%%B"
    )
    :: Validate
    if "!OPT_GPU!"==""      goto :INVALID_CACHE
    if "!OPT_THREADS!"==""  goto :INVALID_CACHE
    if "!OPT_IMG_SIZE!"=="" goto :INVALID_CACHE
    echo.
    echo  [CONFIG] Loaded saved settings:
    echo           GPU=%OPT_GPU%  Threads=%OPT_THREADS%  ImgSize=%OPT_IMG_SIZE%
    echo           JPEG=%OPT_JPEG%  FPS=%OPT_FPS%  MaxFeatures=%OPT_FEATURES%  Overlap=%OPT_OVERLAP%
    echo.
    echo  Press R to reconfigure, or wait 5s to continue ...
    choice /c RX /n /t 5 /d X >nul
    if errorlevel 2 goto :PIPELINE
    if errorlevel 1 call :SETUP_WIZARD
    goto :PIPELINE
    :INVALID_CACHE
    echo [CONFIG] Saved config is invalid - running setup again ...
    del "%TUNE_CACHE%" >nul 2>&1
    call :SETUP_WIZARD
) else (
    call :SETUP_WIZARD
)

:PIPELINE
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
echo  GPU=%OPT_GPU%  Threads=%OPT_THREADS%  ImgSize=%OPT_IMG_SIZE%
echo  JPEG=%OPT_JPEG%  FPS=%OPT_FPS%  MaxFeatures=%OPT_FEATURES%  Overlap=%OPT_OVERLAP%
echo ==============================================================

set /a IDX=0

for %%V in ("%VIDEOS_DIR%\*.mp4" "%VIDEOS_DIR%\*.mov" "%VIDEOS_DIR%\*.avi" "%VIDEOS_DIR%\*.mkv" "%VIDEOS_DIR%\*.mxf") do (
    if exist "%%~fV" (
        set /a IDX+=1
        call :PROCESS_VIDEO "%%~fV" !IDX! %TOTAL%
    )
)

echo --------------------------------------------------------------
echo  All jobs finished - results are in "%SCENES_DIR%".
echo --------------------------------------------------------------
popd
pause
goto :eof


:: ================================================================
:SETUP_WIZARD
:: ================================================================
setlocal EnableDelayedExpansion
echo.
echo ================================================================
echo  SETUP - Only needed once, saved for future runs
echo  Press S on any question to skip and use the default value
echo ================================================================

:: ── PRESET ───────────────────────────────────────────────────────
echo.
echo  [1/8] Overall quality preset  (sets defaults for all options below)
echo        1 = Low     - fast, less accurate  (drone footage, rough scan)
echo        2 = Medium  - balanced             (recommended for most cases)
echo        3 = High    - slow, most accurate  (close-up, detailed object)
echo.
choice /c 123 /n /m "  Choose (1/2/3): "
if errorlevel 3 (
    set "W_GPU=1" & set "W_THREADS=8" & set "W_IMG=3200"
    set "W_JPEG=2" & set "W_FPS=all" & set "W_FEATURES=8192" & set "W_OVERLAP=20"
) else if errorlevel 2 (
    set "W_GPU=1" & set "W_THREADS=4" & set "W_IMG=2048"
    set "W_JPEG=4" & set "W_FPS=all" & set "W_FEATURES=4096" & set "W_OVERLAP=15"
) else (
    set "W_GPU=1" & set "W_THREADS=4" & set "W_IMG=1280"
    set "W_JPEG=6" & set "W_FPS=5" & set "W_FEATURES=2048" & set "W_OVERLAP=10"
)

echo.
echo  Advanced settings? Customize each option individually.
echo  (Press N or wait 5s to keep preset values)
echo.
choice /c YN /n /t 5 /d N /m "  Customize advanced settings? (Y/N): "
if errorlevel 2 goto :SAVE_WIZARD

:: ── GPU ──────────────────────────────────────────────────────────
echo.
echo  [2/8] GPU acceleration
echo        1 = Yes - use NVIDIA GPU (CUDA)
echo        2 = No  - CPU only
echo        S = Skip (keep preset: !W_GPU!)
echo.
choice /c 12S /n /m "  Choose (1/2/S): "
if errorlevel 3 (rem keep) else if errorlevel 2 (set "W_GPU=0") else (set "W_GPU=1")

:: ── THREADS ──────────────────────────────────────────────────────
echo.
echo  [3/8] CPU threads
echo        (Task Manager ^> Performance ^> CPU ^> Logical processors)
echo        1 =  4 threads   (^<8  logical processors)
echo        2 =  8 threads   (8-12 logical processors)
echo        3 = 16 threads   (16+ logical processors)
echo        S = Skip (keep preset: !W_THREADS!)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (rem keep) else if errorlevel 3 (set "W_THREADS=16") else if errorlevel 2 (set "W_THREADS=8") else (set "W_THREADS=4")

:: ── IMAGE SIZE ───────────────────────────────────────────────────
echo.
echo  [4/8] Max image size for feature extraction
echo        1 = 1280  (fastest)
echo        2 = 2048  (balanced)
echo        3 = 3200  (most detail)
echo        S = Skip (keep preset: !W_IMG!)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (rem keep) else if errorlevel 3 (set "W_IMG=3200") else if errorlevel 2 (set "W_IMG=2048") else (set "W_IMG=1280")

:: ── JPEG QUALITY ─────────────────────────────────────────────────
echo.
echo  [5/8] JPEG quality when extracting frames from video
echo        1 = 2  (best quality, largest files)
echo        2 = 4  (good quality, medium files)
echo        3 = 6  (smaller files, some compression)
echo        S = Skip (keep preset: !W_JPEG!)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (rem keep) else if errorlevel 3 (set "W_JPEG=6") else if errorlevel 2 (set "W_JPEG=4") else (set "W_JPEG=2")

:: ── EXTRACT FPS ──────────────────────────────────────────────────
echo.
echo  [6/8] Frame extraction rate
echo        1 = All frames  (most overlap, slowest, largest disk usage)
echo        2 = 10 fps      (good for slow movement)
echo        3 =  5 fps      (good for fast drone footage)
echo        4 =  2 fps      (very sparse, fastest)
echo        S = Skip (keep preset: !W_FPS!)
echo.
choice /c 1234S /n /m "  Choose (1/2/3/4/S): "
if errorlevel 5 (rem keep) else if errorlevel 4 (set "W_FPS=2") else if errorlevel 3 (set "W_FPS=5") else if errorlevel 2 (set "W_FPS=10") else (set "W_FPS=all")

:: ── MAX FEATURES ─────────────────────────────────────────────────
echo.
echo  [7/8] Max features per image (more = slower but more accurate)
echo        1 = 2048   (fast, enough for simple scenes)
echo        2 = 4096   (balanced)
echo        3 = 8192   (most accurate, slowest)
echo        S = Skip (keep preset: !W_FEATURES!)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (rem keep) else if errorlevel 3 (set "W_FEATURES=8192") else if errorlevel 2 (set "W_FEATURES=4096") else (set "W_FEATURES=2048")

:: ── MATCHING OVERLAP ─────────────────────────────────────────────
echo.
echo  [8/8] Sequential matching overlap (how many neighboring frames to match)
echo        1 = 10   (fast, works for steady footage)
echo        2 = 15   (balanced)
echo        3 = 20   (slower, better for fast movement or low fps)
echo        S = Skip (keep preset: !W_OVERLAP!)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (rem keep) else if errorlevel 3 (set "W_OVERLAP=20") else if errorlevel 2 (set "W_OVERLAP=15") else (set "W_OVERLAP=10")

:SAVE_WIZARD
(
    echo USE_GPU=!W_GPU!
    echo THREADS=!W_THREADS!
    echo IMG_SIZE=!W_IMG!
    echo JPEG_QUALITY=!W_JPEG!
    echo EXTRACT_FPS=!W_FPS!
    echo MAX_FEATURES=!W_FEATURES!
    echo OVERLAP=!W_OVERLAP!
) > "%TUNE_CACHE%"

echo.
echo  [OK] Settings saved:
echo       GPU=!W_GPU!  Threads=!W_THREADS!  ImgSize=!W_IMG!
echo       JPEG=!W_JPEG!  FPS=!W_FPS!  MaxFeatures=!W_FEATURES!  Overlap=!W_OVERLAP!
echo.

endlocal & set "OPT_GPU=%W_GPU%" & set "OPT_THREADS=%W_THREADS%" & set "OPT_IMG_SIZE=%W_IMG%" & set "OPT_JPEG=%W_JPEG%" & set "OPT_FPS=%W_FPS%" & set "OPT_FEATURES=%W_FEATURES%" & set "OPT_OVERLAP=%W_OVERLAP%"
goto :eof


:: ================================================================
:PROCESS_VIDEO
:: %1 = full path to video   %2 = current index   %3 = total
:: ================================================================
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
    echo        [1/4] Skipping frame extraction - already done.
) else (
    echo        [1/4] Extracting frames ...

    :: Build FPS filter arg
    set "FPS_ARG="
    if not "%OPT_FPS%"=="all" set "FPS_ARG=-vf fps=%OPT_FPS%"

    "%FFMPEG%" -loglevel error -stats ^
        -i "!VIDEO!" ^
        !FPS_ARG! ^
        -qscale:v %OPT_JPEG% ^
        -threads 0 ^
        "!IMG_DIR!\frame_%%06d.jpg"
    if errorlevel 1 (
        echo        x FFmpeg failed - skipping "!BASE!".
        goto :END
    )
)

:: -------- 2) Feature extraction ---------------------------------
if exist "!SCENE!\done_features" (
    echo        [2/4] Skipping feature extraction - already done.
) else (
    echo        [2/4] COLMAP feature_extractor ...
    "%COLMAP%" feature_extractor ^
        --database_path "!DB_PATH!" ^
        --image_path    "!IMG_DIR!" ^
        --ImageReader.single_camera 1 ^
        --FeatureExtraction.use_gpu %OPT_GPU% ^
        --FeatureExtraction.max_image_size %OPT_IMG_SIZE% ^
        --FeatureExtraction.num_threads %OPT_THREADS% ^
        --SiftExtraction.max_num_features %OPT_FEATURES%
    if errorlevel 1 (
        echo        x feature_extractor failed - skipping "!BASE!".
        goto :END
    )
    echo. > "!SCENE!\done_features"
)

:: -------- 3) Sequential matching --------------------------------
if exist "!SCENE!\done_matching" (
    echo        [3/4] Skipping sequential matching - already done.
) else (
    echo        [3/4] COLMAP sequential_matcher ...
    "%COLMAP%" sequential_matcher ^
        --database_path "!DB_PATH!" ^
        --SequentialMatching.overlap %OPT_OVERLAP% ^
        --FeatureMatching.use_gpu %OPT_GPU% ^
        --FeatureMatching.num_threads %OPT_THREADS%
    if errorlevel 1 (
        echo        x sequential_matcher failed - skipping "!BASE!".
        goto :END
    )
    echo. > "!SCENE!\done_matching"
)

:: -------- 4) Sparse reconstruction ------------------------------
if exist "!SPARSE_DIR!\0\cameras.txt" (
    echo        [4/4] Skipping mapper - already reconstructed.
) else (
    echo        [4/4] GLOMAP mapper ...
    "%GLOMAP%" mapper ^
        --database_path "!DB_PATH!" ^
        --image_path    "!IMG_DIR!" ^
        --output_path   "!SPARSE_DIR!"
    if errorlevel 1 (
        echo        x glomap mapper failed - skipping "!BASE!".
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
