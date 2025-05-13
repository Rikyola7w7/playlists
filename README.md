## Playlists program

A program to show playlists and also to play them :)

The reason why I started making this is so I can actually store a list of songs in a place where youtube or spotify can't remove songs from, locally. I know removing songs is not necessarily because these places want to remove them, sometimes it's the creators themselves. However, I believe youtube/spotify should notify you of such changes in your playlists, and definitely not what they do: "Unavailable videos are hidden"

As a side note, I deleted most of the work done in this project by accident so a lot of it is going to be redone in the first commits and the program used to be more complete. Most importantly, *this isnt the final name for this T-T.*

WARNING: This software is unfinished and subject to change, until any releases are made in github, it will most likely not be stable

## Usage

(I know this is ugly, it is subject to change and will change)

An example playlist file is given in the lists folder: "NCS.txt"

windows: run `playlists.exe playlist_file`

### Dependencies
 - odin programming language: https://odin-lang.org/
 - raylib (vendored in odin): https://www.raylib.com/
 - clay layout library (get odin bindings): https://github.com/nicbarker/clay
 - spall profiler (in odin core library): https://github.com/colrdavidson/spall-web

### Building

Must have a custom raylib build with SUPPORT_CUSTOM_FRAME_CONTROL on, see [Custom Raylib Build](#custom-raylib-build)

windows: run `build.bat`

linux: soon

### Custom Raylib Build
Steps to build raylib with SUPPORT_CUSTOM_FRAME_CONTROL on:
1. Copy the whole vendor:raylib directory into shared:raylib-custom (new directory)
2. Download latest raylib release zip file (the first in the list): https://github.com/raysan5/raylib/releases
3. Unzip it somewhere
4. On windows: 
    1. Open cmd in the directory where you unzipped raylib
    2. Run `cmake -G "Visual Studio 17 2022" -DCUSTOMIZE_BUILD=On -DSUPPORT_CUSTOM_FRAME_CONTROL=On`
5. On linux: WARNING: Untested
    1. Open terminal in directory where you unzipped raylib
    2. Run `cmake -DCUSTOMIZE_BUILD=On -DSUPPORT_CUSTOM_FRAME_CONTROL=On`
6. Run `cmake --build .` or for a release build, run `cmake --build . --config release`
7. Overwrite files in shared:raylib-custom/your_operating_system with files in raylib/Release directory