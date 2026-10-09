@echo off
set R=C:\Users\admin\r-zig-pixi\dist\R-4.6.1-slim-zig\Library\lib\R
set W=C:\Users\admin\rz-pkgbuild
set PATH=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin;C:\Users\admin\.pixi\bin;%PATH%
set ZIG_BIN=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin\x86_64-w64-mingw32-zig.exe
set R_ZIG_EXTRA_ENV=C:\Users\admin\r-zig-pixi\.pixi\envs\default
set RZIG_TRACE=1
cd /d %W%
mkdir src lib-make lib-zig lib-t2 out logs plans 2>nul
tar -xzf cli.tar.gz -C src
tar -xzf quadprog.tar.gz -C src
echo %TIME% start cli
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-make src\cli > logs\make-cli.log 2>&1
echo make cli rc=%ERRORLEVEL% %TIME%
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-make src\quadprog > logs\make-quadprog.log 2>&1
echo make quadprog rc=%ERRORLEVEL% %TIME%
dir /b lib-make\cli\libs lib-make\quadprog\libs
