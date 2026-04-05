:: ================================================================
::  BATCH SCRIPT FOR AUTOMATED PHOTOGRAMMETRY TRACKING WORKFLOW
::  v1.6 – Manual setup wizard + Resume từng bước
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
        if "%%A"=="THREADS"  set "OPT_THREADS=%%B"
        if "%%A"=="IMG_SIZE" set "OPT_IMG_SIZE=%%B"
        if "%%A"=="USE_GPU"  set "OPT_GPU=%%B"
    )
    :: Validate - nếu rỗng thì xóa cache và chạy lại wizard
    if "!OPT_THREADS!"=="" goto :INVALID_CACHE
    if "!OPT_IMG_SIZE!"=="" goto :INVALID_CACHE
    if "!OPT_GPU!"=="" goto :INVALID_CACHE
    echo [CONFIG] Loaded: threads=!OPT_THREADS! img_size=!OPT_IMG_SIZE! gpu=!OPT_GPU!
    echo [CONFIG] Press R to reconfigure, or wait 5s to continue ...
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
echo  Config: threads=%OPT_THREADS%  img_size=%OPT_IMG_SIZE%  gpu=%OPT_GPU%
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
:: Ask user for 3 settings, save to cache
:: ================================================================
setlocal EnableDelayedExpansion
echo.
echo ============================================================
echo  SETUP - Only needed once, saved for future runs
echo ============================================================

:: -- GPU --
echo.
echo  [1/3] Do you have an NVIDIA GPU (CUDA)?
echo        1 = Yes (use GPU - faster)
echo        2 = No  (use CPU only)
echo.
choice /c 12 /n /m "  Choose (1/2): "
if errorlevel 2 (set "W_GPU=0") else (set "W_GPU=1")

:: -- Threads --
echo.
echo  [2/3] How many logical processors does your CPU have?
echo        (Open Task Manager ^> Performance ^> CPU ^> Logical processors)
echo        1 = 4 threads   (older machine, ^< 8 logical processors)
echo        2 = 8 threads   (mid-range, 8-12 logical processors)
echo        3 = 16 threads  (high-end, 16+ logical processors)
echo        S = Skip, use default (4 threads)
echo.
choice /c 123S /n /m "  Choose (1/2/3/S): "
if errorlevel 4 (set "W_THREADS=4") else if errorlevel 3 (set "W_THREADS=16") else if errorlevel 2 (set "W_THREADS=8") else (set "W_THREADS=4")

:: -- Image size --
echo.
echo  [3/3] Image processing quality (affects speed and accuracy):
echo        1 = 2048  (faster, good enough for most videos)
echo        2 = 3200  (slower, more detail)
echo        S = Skip, use default (2048)
echo.
choice /c 12S /n /m "  Choose (1/2/S): "
if errorlevel 3 (set "W_IMG=2048") else if errorlevel 2 (set "W_IMG=3200") else (set "W_IMG=2048")

:: Save config
(
    echo THREADS=!W_THREADS!
    echo IMG_SIZE=!W_IMG!
    echo USE_GPU=!W_GPU!
) > "%TUNE_CACHE%"

echo.
echo  [OK] Saved: threads=!W_THREADS! img_size=!W_IMG! gpu=!W_GPU!
echo ============================================================
echo.

endlocal & set "OPT_THREADS=%W_THREADS%" & set "OPT_IMG_SIZE=%W_IMG%" & set "OPT_GPU=%W_GPU%"
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
    "%FFMPEG%" -loglevel error -stats ^
        -i "!VIDEO!" ^
        -qscale:v 2 ^
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
        --FeatureExtraction.num_threads %OPT_THREADS%
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
        --SequentialMatching.overlap 15 ^
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
