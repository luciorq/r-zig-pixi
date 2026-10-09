@echo off
set W=C:\Users\admin\rz-pkgbuild
set PATH=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin;C:\Users\admin\.pixi\bin;%PATH%
set ZIG_BIN=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin\x86_64-w64-mingw32-zig.exe
set R_ZIG_EXTRA_ENV=C:\Users\admin\r-zig-pixi\.pixi\envs\default
set RZIG_TRACE=1
cd /d %W%
%ZIG_BIN% build --build-file %W%\proto\rpkg\build_t1.zig --cache-dir %W%\zcache --prefix %W%\out\quadprog-def -Dplan=%W%\plans\quadprog-def-win.zon -j4 --summary all > logs\zig-quadprog-def.log 2>&1
echo zig quadprog-def rc=%ERRORLEVEL%
%ZIG_BIN% build --build-file %W%\root-t2\build.zig --cache-dir %W%\zcache --prefix %W%\out\zighello-def -Dplan=%W%\plans\zighello-def-win.zon --summary all > logs\zig-zighello-def.log 2>&1
echo zig zighello-def rc=%ERRORLEVEL%
dir /b out\quadprog-def\libs out\zighello-def\libs
