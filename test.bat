@echo off
setlocal enabledelayedexpansion
chcp 65001 >nul

for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).Name.Trim()"`) do set "CPU=%%i"
for /f "usebackq" %%i in (`powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).NumberOfLogicalProcessors"`) do set /a "THREADS=%%i"
for /f "usebackq delims=" %%i in (`powershell -NoProfile -Command "(Get-CimInstance Win32_VideoController | Sort-Object AdapterRAM -Descending | Select-Object -First 1).Name"`) do set "GPU=%%i"

:MENU
cls
echo [CPU]: %CPU% (%THREADS%T)
echo [GPU]: %GPU%
echo  G. GPU 渲染 ^| C. CPU 渲染 ^| E. 退出

set /p "MODE=选择模式: "

if /i "%MODE%"=="E" exit
if /i "%MODE%"=="G" (set "RUN=GPU" & set "MSK=FFFFFFFF" & goto FILES)
if /i "%MODE%"=="C" (set "RUN=CPU" & goto DO_CPU)
goto MENU

:DO_CPU
set /a T1=%THREADS%-1
set /p "R=核心范围 (0-%T1%): "
for /f "usebackq" %%a in (`powershell -NoProfile -Command "$r='%R%'.Split('-'); [long]$m=0; for($i=[int]$r[0]; $i -le [int]$r[1]; $i++){ $m += [math]::pow(2,$i) }; ('{0:X}' -f $m).Trim()"`) do set "MSK=%%a"
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
    "cuda\build\Release\gpu_render.exe" "%IR%" "%FULL_PATH%" "%CFG%"
) else (
    powershell -NoProfile -Command "$p = Start-Process cargo -ArgumentList 'run --release --bin raytracer -- --render-from-ir \"%IR%\" --cfg \"%CFG%\"' -PassThru -NoNewWindow; $p.ProcessorAffinity = [IntPtr]::new([Convert]::ToInt64('%MSK%', 16)); $p.WaitForExit()"
)

echo 完成: %FINAL_NAME%
explorer /select,"%FULL_PATH%"
pause
exit