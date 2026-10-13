@echo off
rem Builds launcher\SBCraft.exe (the Steam shortcut target) with MSVC.
setlocal
set HERE=%~dp0
if defined VCVARS goto havevc
rem No parentheses block here: the ")" in "Program Files (x86)" would end it. Git Bash also drops variables with
rem parentheses in their names, so ProgramFiles(x86) can be missing.
set "PF86=%ProgramFiles(x86)%"
if "%PF86%"=="" set "PF86=C:\Program Files (x86)"
pushd "%PF86%\Microsoft Visual Studio\Installer"
for /f "usebackq delims=" %%i in (`.\vswhere.exe -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VCVARS=%%i\VC\Auxiliary\Build\vcvars64.bat"
popd
:havevc
if not exist "%VCVARS%" echo No Visual Studio with the C++ x64 tools was found& exit /b 1
call "%VCVARS%" >nul || exit /b 1
if not exist "%HERE%obj" mkdir "%HERE%obj"
cl /nologo /O2 /EHsc /std:c++20 /MT /W3 /DUNICODE /D_UNICODE "%HERE%sbcraft_launcher.cpp" /Fo"%HERE%obj\\" /Fe"%HERE%SBCraft.exe" /link /SUBSYSTEM:WINDOWS user32.lib || exit /b 1
echo built %HERE%SBCraft.exe
