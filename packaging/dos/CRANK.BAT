@ECHO OFF
REM Runs Cranked with the HDPMI32 DPMI host, which unloads itself when Cranked ends (a DPMI host that is
REM already running, as in a Windows DOS box, is used instead). Usage: CRANK game.zip [options]
HDPMI32.EXE > NUL
CRANKED.EXE %1 %2 %3 %4 %5 %6 %7 %8 %9
