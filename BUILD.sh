#!/bin/bash
# Hot reloading script mostly from: https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template/blob/main/build_hot_reload.sh
set -eu

odinreleaseflags="-no-bounds-check -disable-assert -no-type-assert -o:speed"

OUT_DIR=bin
DLL_DIR=$OUT_DIR/hotreload
EXE=viewer.bin

mkdir -p $OUT_DIR
mkdir -p $DLL_DIR

# root is a special command of the odin compiler that tells you where the Odin
# compiler is located.
ROOT=$(odin root)

# Figure out which DLL extension to use based on platform. Also copy the Linux
# so libs.
case $(uname) in
"Darwin")
    case $(uname -m) in
    "arm64") LIB_PATH="macos-arm64" ;;
    *)       LIB_PATH="macos" ;;
    esac

    DLL_EXT=".dylib"
    EXTRA_LINKER_FLAGS="-Wl,-rpath $ROOT/vendor/raylib/$LIB_PATH"
    ;;
*)
    DLL_EXT=".so"
    EXTRA_LINKER_FLAGS="'-Wl,-rpath=\$ORIGIN/linux'"

    # Copy the linux libraries into the project automatically.
    if [ ! -d "$DLL_DIR/linux" ]; then
        mkdir -p $DLL_DIR/linux
        cp -r $ROOT/vendor/raylib/linux/libraylib*.so* $DLL_DIR/linux
    fi
    ;;
esac

odin build src -extra-linker-flags:"$EXTRA_LINKER_FLAGS" -define:RAYLIB_SHARED=true -build-mode:dll -out:$OUT_DIR/app_tmp$DLL_EXT -vet -vet-using-param -vet-style -debug

# Need to use a temp file on Linux because it first writes an empty `app.so`,
# which the app will load before it is actually fully written.
mv $OUT_DIR/app_tmp$DLL_EXT $OUT_DIR/app$DLL_EXT

# If the executable is already running, then don't try to build and start it.
# -f is there to make sure we match against full name, including .bin
if pgrep -f $EXE > /dev/null; then
    exit 0
fi

odin build src/hot-reload -out:$EXE -vet -vet-using-param -vet-style -debug

if [ $# -ge 1 ] && [ $1 == "run" ]; then
    ./$EXE &
fi
