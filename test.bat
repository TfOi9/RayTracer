@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

:MENU
cls
echo  G. GPU 渲染 ^| C. CPU 渲染 ^| E. 退出

set /p "MODE=选择模式: "

if /i "%MODE%"=="E" exit
if /i "%MODE%"=="G" (set "RUN=GPU" & goto FIND_GPU_EXE)
if /i "%MODE%"=="C" (set "RUN=CPU" & goto DO_CPU)
goto MENU

:DO_CPU
set "TS=%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%"
set "TS=%TS: =0%"
set "DEFAULT_NAME=render_%TS%.ppm"
set "OUT_DIR=%CD%\images"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"

set "FULL_PATH="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.SaveFileDialog; $f.Title='选择CPU渲染输出文件'; $f.Filter='PPM|*.ppm'; $f.InitialDirectory='%OUT_DIR%'; $f.FileName='%DEFAULT_NAME%'; if($f.ShowDialog() -eq 'OK'){$f.FileName}"`) do set "FULL_PATH=%%I"
if "%FULL_PATH%"=="" goto MENU

set /p "CPU_ARGS=输入 raytracer 参数 (例如 --scenario 9，直接回车用默认): "
if "%CPU_ARGS%"=="" (
    cargo run --release --bin raytracer > "%FULL_PATH%"
) else (
    cargo run --release --bin raytracer -- %CPU_ARGS% > "%FULL_PATH%"
)
echo 完成: %FULL_PATH%
explorer /select,"%FULL_PATH%"
pause
exit

:FIND_GPU_EXE
set "GPU_EXE="
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "$p = Get-ChildItem -Path 'cuda' -Filter 'gpu_render.exe' -File -Recurse -Depth 5 -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName; if($p){$p}"`) do set "GPU_EXE=%%i"
if not defined GPU_EXE (
    echo 未找到 gpu_render.exe（已在 cuda 目录下递归深度 5 搜索）。
    pause
    goto MENU
)
goto FILES

:FILES
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Title='选择场景 (.ir)'; $f.Filter='IR|*.ir'; if($f.ShowDialog() -eq 'OK'){$f.FileName}"`) do set "IR=%%I"
if "%IR%"=="" exit
for /f "usebackq delims=" %%I in (`powershell -NoProfile -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.OpenFileDialog; $f.Title='选择配置 (.cfg)'; $f.Filter='CFG|*.cfg'; if($f.ShowDialog() -eq 'OK'){$f.FileName}"`) do set "CFG=%%I"
if "%CFG%"=="" exit

set "TS=%DATE:~5,2%%DATE:~8,2%_%TIME:~0,2%%TIME:~3,2%"
set "TS=%TS: =0%"
set /p "CUSTOM_NAME=请输入输出文件名 (直接回车使用 render_%TS%): "
if "%CUSTOM_NAME%"=="" (set "FINAL_NAME=render_%TS%.ppm") else (set "FINAL_NAME=%CUSTOM_NAME%.ppm")

set "OUT_DIR=%CD%\images"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%"
set "FULL_PATH=%OUT_DIR%\%FINAL_NAME%"

if "%RUN%"=="GPU" (
    "%GPU_EXE%" "%IR%" "%FULL_PATH%" "%CFG%"
)

echo 完成: %FINAL_NAME%
explorer /select,"%FULL_PATH%"
pause
exit