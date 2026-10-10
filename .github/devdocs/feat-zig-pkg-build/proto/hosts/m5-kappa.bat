@echo off
set R=C:\Users\admin\r-zig-pixi\dist\R-4.6.1-slim-zig\Library\lib\R
set W=C:\Users\admin\rz-m5
set ENV=C:\Users\admin\r-zig-pixi\.pixi\envs\default
set PATH=%ENV%\Library\bin;C:\Users\admin\.pixi\bin;%PATH%
set ZIG_BIN=%ENV%\Library\bin\x86_64-w64-mingw32-zig.exe
set R_ZIG_EXTRA_ENV=%ENV%
set R_MAKEVARS_USER=C:\nonexistent
set RZIG_TRACE=1
cd /d %W%
rmdir /s /q lib-zig lib-make lib-t2 lib-nomake logs neg3 zighello nomake-bin 2>nul
mkdir lib-zig lib-make lib-t2 lib-nomake logs
echo == host
ver
%ZIG_BIN% version
%R%\bin\x64\Rscript.exe -e "cat(R.version.string, R.version$platform, '\n')"
echo == tree
dir /b %R%\bin\toolchain
dir /b %R%\share\zig\rpkg
call :one cli
call :one digest
call :one quadprog
call :one Rcpp
echo == parity (objdump exports, imports, rzig argv)
%R%\bin\x64\Rscript.exe %W%\m5-kappa.R
echo == smoke zig
%R%\bin\x64\Rscript.exe %W%\smoke.R C:/Users/admin/rz-m5/lib-zig
echo smoke zig rc=%ERRORLEVEL%
echo == smoke make
%R%\bin\x64\Rscript.exe %W%\smoke.R C:/Users/admin/rz-m5/lib-make
echo smoke make rc=%ERRORLEVEL%
echo == tier 2: zighello from its directory %TIME%
xcopy /e /i /q C:\Users\admin\r-zig-pixi\.github\devdocs\feat-zig-pkg-build\proto\zighello zighello >nul
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-t2 zighello > logs\zighello.log 2>&1
echo zighello rc=%ERRORLEVEL% %TIME%
findstr /r /c:"tier" /c:"using zig" /c:"\*\* testing" logs\zighello.log
dir /b /a zighello\src
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-t2 zighello > logs\zighello2.log 2>&1
echo zighello again rc=%ERRORLEVEL% %TIME%
%R%\bin\x64\Rscript.exe %W%\t2.R C:/Users/admin/rz-m5/lib-t2
echo zighello load rc=%ERRORLEVEL%
%R%\bin\x64\Rscript.exe -e "W <- 'C:/Users/admin/rz-m5'; source(file.path(W, 'm5-kappa.R'), echo = FALSE)" > nul 2>&1
echo == tier 3 (configure.win) falls through to make
mkdir neg3
tar -xzf pkgs\cli.tar.gz -C neg3
%R%\bin\x64\Rscript.exe -e "writeLines(c('#!/bin/sh', 'exit 0'), 'neg3/cli/configure.win')"
%R%\bin\x64\Rcmd.exe INSTALL --no-test-load -l %W%\lib-make neg3\cli > logs\neg3.log 2>&1
echo neg3 rc=%ERRORLEVEL%
findstr /c:"needs make" /c:"rzig build:" logs\neg3.log
findstr /r /c:"^make" /c:"make\[" logs\neg3.log | find /c /v ""
echo == R_ZIG_PKG_BUILDER=zig on a tier-3 package
set R_ZIG_PKG_BUILDER=zig
%R%\bin\x64\Rcmd.exe INSTALL --no-test-load -l %W%\lib-make neg3\cli > logs\neg3-zig.log 2>&1
echo rc=%ERRORLEVEL%
findstr /c:"ERROR" /c:"needs make" logs\neg3-zig.log
set R_ZIG_PKG_BUILDER=
echo == no make or sh on PATH (System32 + a copy of flang; zig through ZIG_BIN)
mkdir nomake-bin
copy /y %ENV%\Library\bin\flang.exe nomake-bin\ >nul
copy /y %ENV%\Library\bin\flang-new.exe nomake-bin\ >nul
copy /y %ENV%\Library\bin\flang.cfg nomake-bin\ >nul
copy /y %ENV%\Library\bin\flang-compile.cfg nomake-bin\ >nul
dir /b nomake-bin
set OLDPATH=%PATH%
set PATH=%W%\nomake-bin;C:\Windows\System32
where make sh 2>nul
echo where rc=%ERRORLEVEL% (1 = neither found)
%R%\bin\x64\Rcmd.exe INSTALL --no-test-load -l %W%\lib-nomake pkgs\quadprog.tar.gz > logs\nomake.log 2>&1
echo quadprog no-make rc=%ERRORLEVEL%
findstr /c:"ERROR" /c:"not found" /c:"tier" /c:"using" logs\nomake.log
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-nomake pkgs\cli.tar.gz > logs\nomake-cli.log 2>&1
echo cli no-make (with test load) rc=%ERRORLEVEL%
findstr /c:"ERROR" /c:"not found" logs\nomake-cli.log
set PATH=%OLDPATH%
echo == cache
dir %LOCALAPPDATA%\r-zig 2>nul | findstr /i "dir"
echo EXIT=done
goto :eof

:one
echo == %1 zig %TIME%
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-zig pkgs\%1.tar.gz > logs\%1-zig.log 2>&1
echo %1 zig rc=%ERRORLEVEL% %TIME%
findstr /r /c:"tier [12]" logs\%1-zig.log
findstr /r /c:"^using .* compiler" logs\%1-zig.log | find /c /v ""
findstr /r /c:"^make" /c:"make\[" logs\%1-zig.log | find /c /v ""
echo == %1 make %TIME%
set R_ZIG_PKG_BUILDER=make
%R%\bin\x64\Rcmd.exe INSTALL -l %W%\lib-make pkgs\%1.tar.gz > logs\%1-make.log 2>&1
echo %1 make rc=%ERRORLEVEL% %TIME%
set R_ZIG_PKG_BUILDER=
exit /b
