package hotreload

import "core:os"
import "core:fmt"
import "core:dynlib"

DLL_NAME :: "app." + dynlib.LIBRARY_FILE_EXTENSION

App :: struct {
  InitAll: proc() -> (rawptr, rawptr),
  DeInitAll: proc(rawptr),
  MainLoop: proc(rawptr, rawptr) -> bool,
}

LoadDllProcs :: proc() -> (app: App, ok: bool) {
  library: dynlib.Library
  library, ok = dynlib.load_library(DLL_NAME)
  if !ok {
    fmt.eprintfln("Could not load " + DLL_NAME + ": %s", dynlib.last_error())
    return
  }

  symbol: rawptr
  symbol, ok = dynlib.symbol_address(library, "InitAll")
  if !ok {
    fmt.eprintfln("Could not load InitAll from " + DLL_NAME + ": %s", dynlib.last_error())
    return
  }
  app.InitAll = cast(proc() -> (rawptr, rawptr))symbol

  symbol, ok = dynlib.symbol_address(library, "DeInitAll")
  if !ok {
    fmt.eprintfln("Could not load DeInitAll from " + DLL_NAME + ": %s", dynlib.last_error())
    return
  }
  app.DeInitAll = cast(proc(rawptr))symbol

  symbol, ok = dynlib.symbol_address(library, "MainLoop")
  if !ok {
    fmt.eprintfln("Could not load MainLoop from " + DLL_NAME + ": %s", dynlib.last_error())
    return
  }
  app.MainLoop = cast(proc(rawptr, rawptr) -> bool)symbol
  return
}

main :: proc() {
  app, ok := LoadDllProcs()
  if !ok {
    os.exit(1)
  }

  rawApp, rawInput := app.InitAll()
  defer app.DeInitAll(rawApp)

  appFileTime, err := os.last_write_time_by_name(DLL_NAME)
  if err != nil {
    fmt.eprintfln("Could not read " + DLL_NAME + " file time: %v", err)
    return
  }
  fmt.println("file time:", appFileTime)

  quit := false
  for !quit {
    quit = app.MainLoop(rawApp, rawInput)
  }
}