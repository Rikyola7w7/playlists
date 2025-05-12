@echo off

set odinreleaseflags=-no-bounds-check -disable-assert -no-type-assert -o:speed

if not exist bin mkdir bin
pushd bin
odin build ../src -out:playlists.exe -debug -vet -vet-using-param -vet-style

playlists.exe "../lists/NCS.txt"
popd