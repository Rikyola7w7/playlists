@echo off

set defs=-D_CRT_SECURE_NO_WARNINGS
set opts=%defs% -FC -GR- -EHa- -nologo -Zi -W4 -wd4129 -wd4200
set code=..\src

set odinreleaseflags=-no-bounds-check -disable-assert -no-type-assert -o:speed

IF NOT EXIST bin mkdir bin

pushd bin
::cl %opts% %code%\main.c -Feplaylists.exe /link -incremental:no -opt:ref
::gcc -Wall -Wextra %code%\main.c -o playlists.exe

odin build ../src -out:playlists.exe -debug -vet -vet-using-param -vet-style

playlists.exe "../lists/NCS.txt"
popd