@echo off
set R=C:\Users\admin\r-zig-pixi\dist\R-4.6.1-slim-zig\Library\lib\R
set W=C:\Users\admin\rz-pkgbuild
set PATH=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin;C:\Users\admin\.pixi\bin;%PATH%
set ZIG_BIN=C:\Users\admin\r-zig-pixi\.pixi\envs\default\Library\bin\x86_64-w64-mingw32-zig.exe
set R_ZIG_EXTRA_ENV=C:\Users\admin\r-zig-pixi\.pixi\envs\default
set RZIG_TRACE=1
cd /d %W%
rmdir /s /q zcache out lib-zig lib-t2 root-t2-x zighello-nosrc quadprog-nosrc 2>nul
mkdir out lib-zig lib-t2 2>nul
echo == zig cli cold %TIME%
%ZIG_BIN% build --build-file %W%\proto\rpkg\build_t1.zig --cache-dir %W%\zcache --prefix %W%\out\cli -Dplan=%W%\plans\cli-win.zon -j4 --summary all > logs\zig-cli.log 2>&1
echo zig cli rc=%ERRORLEVEL% %TIME%
%ZIG_BIN% build --build-file %W%\proto\rpkg\build_t1.zig --cache-dir %W%\zcache --prefix %W%\out\cli -Dplan=%W%\plans\cli-win.zon -j4 --summary all > logs\zig-cli-warm.log 2>&1
echo zig cli warm rc=%ERRORLEVEL% %TIME%
%ZIG_BIN% build --build-file %W%\proto\rpkg\build_t1.zig --cache-dir %W%\zcache --prefix %W%\out\quadprog -Dplan=%W%\plans\quadprog-win.zon -j4 --summary all > logs\zig-quadprog.log 2>&1
echo zig quadprog rc=%ERRORLEVEL% %TIME%
dir /b out\cli\libs out\quadprog\libs
echo == smoke
xcopy /e /i /q lib-make\cli lib-zig\cli >nul
copy /y out\cli\libs\cli.dll lib-zig\cli\libs\x64\cli.dll >nul
xcopy /e /i /q src\quadprog quadprog-nosrc >nul
rmdir /s /q quadprog-nosrc\src
%R%\bin\x64\Rcmd.exe INSTALL --no-test-load -l %W%\lib-zig quadprog-nosrc > logs\install-quadprog-nosrc.log 2>&1
echo install quadprog R-only rc=%ERRORLEVEL%
mkdir lib-zig\quadprog\libs\x64 2>nul
copy /y out\quadprog\libs\quadprog.dll lib-zig\quadprog\libs\x64\quadprog.dll >nul
echo -- lib-make
%R%\bin\x64\Rscript.exe smoke-win.R C:/Users/admin/rz-pkgbuild/lib-make
echo rc=%ERRORLEVEL%
echo -- lib-zig
%R%\bin\x64\Rscript.exe smoke-win.R C:/Users/admin/rz-pkgbuild/lib-zig
echo rc=%ERRORLEVEL%
echo == tier 2 zighello %TIME%
%ZIG_BIN% build --build-file %W%\root-t2\build.zig --cache-dir %W%\zcache --prefix %W%\out\zighello -Dplan=%W%\plans\zighello-win.zon -j4 --summary all > logs\zig-zighello.log 2>&1
echo zig zighello rc=%ERRORLEVEL% %TIME%
%ZIG_BIN% build --build-file %W%\root-t2\build.zig --cache-dir %W%\zcache --prefix %W%\out\zighello -Dplan=%W%\plans\zighello-win.zon -j4 --summary all > logs\zig-zighello2.log 2>&1
echo zig zighello again rc=%ERRORLEVEL% %TIME%
dir /b out\zighello\libs
xcopy /e /i /q proto\zighello zighello-nosrc >nul
rmdir /s /q zighello-nosrc\src
%R%\bin\x64\Rcmd.exe INSTALL --no-test-load -l %W%\lib-t2 zighello-nosrc > logs\install-zighello.log 2>&1
echo install zighello R-only rc=%ERRORLEVEL%
mkdir lib-t2\zighello\libs\x64 2>nul
copy /y out\zighello\libs\zighello.dll lib-t2\zighello\libs\x64\zighello.dll >nul
%R%\bin\x64\Rscript.exe t2.R C:/Users/admin/rz-pkgbuild/lib-t2
echo zighello rc=%ERRORLEVEL%
echo == done %TIME%
