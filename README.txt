AmstradCPC6128 core
===================

original AmstradCPC464 core (all the hard work), written by Miguel Angel Rodriguez Jodar
enhanced by Microjack with 128kb update, and disk emulation reading / writing from SDcard.

Building
--------
This project depends on the following repo to be cloned at the same level as thie amstrad repo.
 - git@github.com:ZXMicroJack/ctrl-module.git - branch amstradcpc.

SDCard preparation
------------------
Create a subdirectory in the root folder of the SD card (FAT32 or FAT16) 'AMSTRAD'.  Into
which you should copy the files AMSDOS.ROM, BASIC1-1.ROM, and OS6128.ROM.

Keys
----
- F12 - disk menu
- Ctrl-Alt-Delete - reset machine
- Ctrl-Alt-Backspace - reset to BIOS
- END - greenscreen mono mode.
- Scroll Lock - toggle scan doubler on/off

Known issues
------------
- Only 512 byte sector disks supported
- copy protected disks not yet supported - WIP
- Hitting reset randomly moves the screen horizontally sometimes causing the scan lines
  to swap 123456->214365. Keep pressing reset fixes this.  This was a pre-existing issue
  not caused by ctrl-module.
- not 100% compatibility as yet
- scan doubler a little delicate with the mode-R screens

Disk image support
------------------
This supports:
- RAW format, 40 track, 9 sector, 512 byte sectors, and will assume a sequential sector numbering,
  starting from 0xc1.
- CPC Emu extended format, and standard CPC Emu format, limited to 512 byte sector block and no 
  copy protected images at present - WIP.  Maximum 80 tracks 10 sectors and up to 839.5k image size.
- Two disk drives.

SRAM Memory Map
---------------
64000 - OS6128
60000 - BASIC1-1
5C000 - AMSDOS
1C000 - RAM PAGE 7
18000 - RAM PAGE 6
14000 - RAM PAGE 5
10000 - RAM PAGE 4
0C000 - RAM PAGE 3
08000 - RAM PAGE 2
04000 - RAM PAGE 1
00000 - RAM PAGE 0

ROM
[20:19] = 00
[18] = 1
[17:14] = rom (page 7 if rom_page == 7 or 8 otherwise)
[13:0] = addr[13:0]

RAM
[20:18] = 000
[17:14] = ram_page[3:0]
[31:0] = addr[13:0]

ROMS loaded at 5c000, ending at 64000

Known non-working Games
-----------------------
- DDLE
- Golden Tail
- DeliriumTremens
- Pinball Dreams
- Prehistorik II
- R-Type
- Total Recall

Feedback
--------
zx.micro.jack@gmail.com

ChangeLog
---------
release r1 (candidate)
- ctrl-module to load disks
- booting AMSDOS.ROM from SDcard

release r4
- last known good for ZXUno

release r5
- first known good for ZXTres
