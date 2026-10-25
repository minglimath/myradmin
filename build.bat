@echo off
setlocal
set AUT2EXE=C:\Program Files (x86)\AutoIt3\Aut2Exe\Aut2exe.exe
set SRC=%~dp0AutoRadmin.au3
set OUT=%~dp0AutoRadmin.exe
set ICO=%~dp0icon.ico

"%AUT2EXE%" /in "%SRC%" /out "%OUT%" /icon "%ICO%" /x86 /comp 4
echo EXITCODE=%ERRORLEVEL%
if exist "%OUT%" (echo BUILT: %OUT%) else (echo BUILD FAILED)
endlocal
