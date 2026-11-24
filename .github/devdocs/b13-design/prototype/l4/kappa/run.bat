@echo off
rem L4 prototype on kappa (b13-design PLAN.md). Started as
rem   pixi run -e <native|msys> --clean-env cmd /c run.bat <cfg> <step>
rem so R's env is activated and nothing of the caller's PATH survives.
rem cfg N: the zig-built tools dir as R's build tools (R_CUSTOM_TOOLS_PATH);
rem cfg M: build 12 as shipped (r-zig-build-tools' MSYS2 set).
rem step: probe | install | bake
setlocal
set S=C:\Users\admin\rz-b13-design
set CFG=%1
set PATH=%CONDA_PREFIX%\Library\bin;%CONDA_PREFIX%;C:\Windows\System32;C:\Windows;C:\Windows\System32\Wbem
if "%CFG%"=="N" set R_CUSTOM_TOOLS_PATH=%S%\tools-N
if "%CFG%"=="N" set CONFIG_SHELL=sh
set ZIG_GLOBAL_CACHE_DIR=%S%\zcache
set TMPDIR=%S%\tmp
set TMP=%S%\tmp
set TEMP=%S%\tmp
set MAKEFLAGS=-j4
set R_LIBS_USER=%S%\nolib
if not exist %S%\tmp mkdir %S%\tmp
"%CONDA_PREFIX%\Library\lib\R\bin\x64\Rscript.exe" --vanilla %S%\test.R %CFG% %2 %3
