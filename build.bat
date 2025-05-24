@echo off

set odinreleaseflags=-no-bounds-check -disable-assert -no-type-assert -o:speed

if not exist bin mkdir bin
pushd bin
odin build ../src/hot-reload -out:playlists.exe -debug -vet -vet-using-param -vet-style
if %errorlevel% neq 0 (
  exit /b 1
)
odin build ../src -build-mode:dll -out:app.dll -debug -vet -vet-using-param -vet-style
if %errorlevel% neq 0 (
  exit /b 1
)

::playlists.exe "../lists/NCS.txt"
playlists.exe "../songs"
popd