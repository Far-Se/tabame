@echo off
REM Generates build\clangd\compile_commands.json for clangd (the Zed/VS Code
REM C++ language server). The normal `flutter build windows` uses CMake's
REM Visual Studio generator, which cannot emit a compile database, so clangd
REM otherwise can't find the Flutter headers / MSVC STL and floods every .cpp
REM with bogus errors. This configures a throwaway side build with Ninja just
REM to produce the compile database (it does not actually build anything).
REM
REM Re-run this after adding new source files or plugins. Run it from anywhere;
REM paths are resolved relative to this script's location (%~dp0 = tool\).
setlocal
set "REPO=%~dp0.."
call "E:\Program Files\Visual Studio\VC\Auxiliary\Build\vcvars64.bat"
set "PATH=%PATH%;E:\Program Files\Visual Studio\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
cmake -S "%REPO%\windows" -B "%REPO%\build\clangd" -G Ninja -DCMAKE_EXPORT_COMPILE_COMMANDS=ON -DCMAKE_BUILD_TYPE=Debug
endlocal

