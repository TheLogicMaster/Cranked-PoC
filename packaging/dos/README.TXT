Cranked Proof of Concept for DOS
================================

An emulator for Playdate games, built for 32-bit protected mode DOS (DJGPP).
This is the Proof of Concept build: see https://github.com/TheLogicMaster/Cranked-PoC

What it needs
-------------
- A Pentium or later with a math coprocessor (any Pentium has one), and
  32 MB of memory or more. Games run in an ARM interpreter: C games are slow
  on anything but a fast machine, Lua games less so.
- A VGA. With a VESA BIOS that has the 800x600 16-color mode, the screen is
  shown at twice its size; otherwise at its own size in 640x480.
- Optional: a Sound Blaster 16 (or compatible), named by the BLASTER variable
  (for example SET BLASTER=A220 I5 D1 H5 T6; the A, I and H values are used),
  and a mouse driver (CTMOUSE) for turning the crank with the mouse.
- Long file name support (DOSLFN on FreeDOS and MS-DOS 6, built into Windows
  9x and DOSBox) is recommended: games' save data go into folders named after
  the games' bundle IDs, which are longer than 8.3 names.
- A DPMI host. HDPMI32.EXE (from the HX DOS extender, freeware) is included;
  CRANK.BAT starts it and then Cranked. CWSDPMI works too. In a Windows DOS
  box, Windows is the DPMI host.

Running
-------
    CRANK game.zip [options]

The game is a zipped .pdx bundle (or a .pdx folder, where long file names are
available). Options:

    -1              640x480 at the screen's own size
    -q              no sound
    -t <seconds>    stop after this much game time
    -shot <file>    write the last frame to a BMP file when the game ends
    -c <0-5>        the screen's colors: 0 Playdate, 1 bright room, 2 paper,
                    3 Game Boy, 4 amber, 5 high contrast
    -b              blend each frame with the one before, so pixels a game
                    flickers to make grey are shown grey

Keys
----
    Arrows or keypad    d-pad
    Z or A              B button
    X or S              A button
    Enter               Menu button
    Comma, period       turn the crank (the mouse turns it too)
    C                   dock or undock the crank
    P                   pause
    F2                  the next colors
    F3                  frame blending on or off
    F5                  restart the game
    F12                 save a screenshot, CRANKnnn.BMP
    Esc                 quit

Save data are kept in APPDATA\ in the current folder.

Playdate is a trademark of Panic Inc. This project is not affiliated with Panic.
