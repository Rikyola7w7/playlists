package main

import "core:os"
import "core:fmt"
import "core:sync"
import "core:slice"
import "core:strings"
import "core:math/rand"
import "core:path/filepath"

import "core:prof/spall"
import ray "vendor:raylib"

SortSongData :: proc(songs: []SongData)
{
  groupLess :: proc(i, j: SongData) -> bool { return i.group < j.group }
  albumLess :: proc(i, j: SongData) -> bool { return i.album < j.album }
  nameLess  :: proc(i, j: SongData) -> bool { return i.name < j.name   }

  slice.sort_by(songs, groupLess)

  prev := songs[0]
  prevIdx := 0
  counter := 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prev.group {
      if i - prevIdx > 1 {
        slice.sort_by(songs[prevIdx:i], albumLess)
        counter += 1
      }
      prev = songs[i]
      prevIdx = i
    }
  }

  prev = songs[0]
  prevIdx = 0
  counter = 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prev.group || songs[i].album != prev.album {
      if i - prevIdx > 1 {
        slice.sort_by(songs[prevIdx:i], nameLess)
        counter += 1
      }
      prev = songs[i]
      prevIdx = i
    }
  }
}

CountSongs :: proc(songs: []SongData)
{
  prevGroup := songs[0].group
  prevIdx := 0
  for i := 0; i < len(songs); i += 1
  {
    if songs[i].group != prevGroup {
      fmt.printfln("%s: %d songs", prevGroup, i - prevIdx)
      prevGroup = songs[i].group
      prevIdx = i
    }
  }
  fmt.printfln("%s: %d songs", songs[len(songs)-1].group, len(songs) - prevIdx)
}

PrintSongs :: proc(songs: []SongData)
{
  for i := 0; i < len(songs); i += 1
  {
    s := songs[i]
    if s.album == "" {
      fmt.printfln("%s - %s", s.group, s.name)
    }
    else {
      fmt.printfln("%s - %s - %s", s.group, s.album, s.name)
    }
  }
}

ParseSingleSong :: proc(text: ^string) -> (SongData, bool)
{
  TrimQuotesAndCommaIfPresent :: #force_inline proc(text: string) -> string
  {
    // accept no comma
    if text[len(text)-1] == ',' {
      return text[1:len(text) - 2]
    }
    else {
      return text[1:len(text) - 1]
    }
  }

  song: SongData
  nok := false
  foundEnd := false
  for line in strings.split_lines_iterator(text)
  {
    if strings.has_prefix(line, "}") {
      foundEnd = true
      break
    }

    trimmedLine := strings.trim_space(line)
    if strings.has_prefix(trimmedLine, "group:") {
      trimmedLine = strings.trim_space(trimmedLine[len("group:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.group = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "song:") {
      trimmedLine = strings.trim_space(trimmedLine[len("song:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.name = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "source:") {
      trimmedLine = strings.trim_space(trimmedLine[len("source:"):])
      trimmedLine = TrimQuotesAndCommaIfPresent(trimmedLine)
      song.source = trimmedLine
    }
    else if strings.has_prefix(trimmedLine, "sourceType:") {
      trimmedLine = strings.trim_space(trimmedLine[len("sourceType:"):])
      if trimmedLine[len(trimmedLine)-1] == ',' {
        trimmedLine = trimmedLine[:len(trimmedLine)-1]
      }
      if trimmedLine == "File" { song.sourceType = .File }
      else if trimmedLine == "Link" { song.sourceType = .Link }
      else {
        // TODO: better error msg
        fmt.println("Unknown source type")
        nok = true
      }
    }
  }
  // TODO: error msg (not found end)
  nok = nok || !foundEnd
  return song, !nok
}

ParseSongs :: proc(app: ^AppData, data: []u8) -> [dynamic]SongData
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  songs: [dynamic]SongData

  source := string(data)

  startList := false
  for line in strings.split_lines_iterator(&source)
  {
    if strings.has_prefix(line, "main list:") {
      assert(!startList)
      startList = true
      continue
    }
    if line == "" do startList = false
    if !startList do continue

    if !strings.has_prefix(line, "{") {
      // TODO: better error msg
      fmt.println("parse error")
      break
    }
    song, ok := ParseSingleSong(&source)
    if !ok {
      // TODO: better error msg
      fmt.println("parse error")
      break
    }
    //fmt.printfln("[\n  group: \"%s\"\n  song: \"%s\"\n  source: \"%s\"\n  sourceType: %v\n]", song.group, song.name, song.source, song.sourceType)
    append(&songs, song)
  }

  return songs
}

ParseSongs_v1 :: proc(data: []u8) -> [dynamic]SongData
{
  songs: [dynamic]SongData

  source := string(data)

  startList := false
  for line in strings.split_lines_iterator(&source)
  {
    if strings.has_prefix(line, "main list:") {
      assert(!startList)
      startList = true
      continue
    }
    if line == "" do startList = false
    if !startList do continue

    songName, sep, album, group: string
    songName, sep, album = strings.partition(line, " - ")
    album, sep, group = strings.partition(album, " - ")
    if group == "" {
      group = album
      album = ""
    }

    //fmt.printfln("%s - %s - %s", group, album, songName)

    song : SongData = {
      name = songName,
      group = group,
      album = album,
    }
    fmt.printfln("%c\n  group: \"%s\"\n  song: \"%s\"\n},", '{', song.group, song.name)
    append(&songs, song)
  }

  // PrintSongs(songs[:])
  // CountSongs(songs[:])

  return songs
}

ChangeLoadedMusicStream :: proc(app: ^AppData, newIdx: int)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
  
  playlist := &app.playlist
  if playlist.songs[playlist.activeSongIdx].source != "" {
    if app.musicLoaded {
      ray.UnloadMusicStream(app.music)
      app.musicLoaded = false
    }

    activeSong := playlist.songs[newIdx]
    switch activeSong.sourceType {
      case .None: assert(false, "unreachable")
      case .Link: {
        assert(false, "unimplemented")
      }
      case .File: {
        if os.exists(activeSong.source) {
          filename := strings.clone_to_cstring(activeSong.source, context.temp_allocator)
          app.music = ray.LoadMusicStream(filename)
          app.music.looping = false
          ray.PlayMusicStream(app.music)
          app.musicLoaded = true
        }
        else {
          b: strings.Builder = strings.builder_make_len_cap(0, 40, context.temp_allocator)
          filepath := fmt.sbprintf(&b, "../songs/%s", activeSong.source)
          if os.exists(filepath) {
            file, _ := strings.to_cstring(&b)
            app.music = ray.LoadMusicStream(file)
            app.music.looping = false
            ray.PlayMusicStream(app.music)
            app.musicLoaded = true
          }
          else {
            fmt.println("Could not find song")
          }
        }
      }
    }

    // NOTE: Gather 'static' data from app.music here
    app.musicTimeLength = ray.GetMusicTimeLength(app.music)
    app.musicTimePlayed = 0.0
  }
}

DataFile :: struct #packed {
  volume: f32,
  previousSongLen: i32, // length of the string
  previousSong: [^]u8,
}
DATAFILE_NAME :: "prog.dat"

InitRaylib :: proc(app: ^AppData)
{
  ray.SetTraceLogLevel(.WARNING)
  ray.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT, .WINDOW_ALWAYS_RUN}) // WINDOW_HIGHDPI
  app.screenWidth = 1000
  app.screenHeight = 800
  ray.InitWindow(app.screenWidth, app.screenHeight, "playlist viewer")
}

InitClay :: proc(app: ^AppData)
{
  app.fonts[Font_Inconsolata] = ray.LoadFontEx("../resources/Inconsolata-Regular.ttf", 48, nil, 400)
  ray.SetTextureFilter(app.fonts[Font_Inconsolata].texture, .BILINEAR)
  app.fonts[Font_LiberationMono] = ray.LoadFontEx("../resources/liberation-mono.ttf", 48, nil, 400)
  ray.SetTextureFilter(app.fonts[Font_LiberationMono].texture, .BILINEAR)
  Clay_Init(&app.fonts[0], app.screenWidth, app.screenHeight)
}

@export
InitAll :: proc(rawApp: rawptr, rawInput: rawptr)
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput

  app.spall_ctx = spall.context_create("trace.spall")
  app.spall_backing_buffer = make([]u8, spall.BUFFER_DEFAULT_SIZE)
  app.spall_buffer = spall.buffer_create(app.spall_backing_buffer, u32(sync.current_thread_id()))
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  listFile := os.args[1] if len(os.args) > 1 else ""

  ok: bool
  data: []u8
  if os.exists(DATAFILE_NAME) {
    data, ok = os.read_entire_file(DATAFILE_NAME)
    assert(ok)

    volume := (cast(^f32)&data[offset_of(DataFile, volume)])^
    app.volume = clamp(volume, 0.0, 0.4)
    // NOTE: If I want to delete the data from the file, clone the string here.
    if listFile == "" {
      startStr := &data[8]
      strLen := int((cast(^i32)&data[4])^)
      listFile = strings.string_from_ptr(startStr, strLen)
    }
  }

  songData: [dynamic]SongData
  if listFile != "" {
    if os.is_dir(listFile) {
      fileInfos: []os.File_Info
      songDir, err := os.open(listFile)
      assert(err == nil, "Could not open directory")
      // TODO: Read more than the max count of files when exceeded?
      fileInfos, err = os.read_dir(songDir, 128) // 128 files max
      assert(err == nil)
      for fi in fileInfos {
        ext := filepath.ext(fi.name)
        if len(ext) > 1 { ext = ext[1:] }
        if !fi.is_dir && (ext == "mp3" || ext == "ogg" || ext == "qoa" || ext == "xm" || ext == "mod" || ext == "wav") {
          song := SongData{
            group = "",
            name = filepath.short_stem(fi.name),
            album = "",
            source = fi.fullpath,
            sourceType = .File,
          }
          append(&songData, song)
        }
      }
    }
    else {
      data, ok = os.read_entire_file(listFile)
      assert(ok)
      songData = ParseSongs(app, data)
    }
  }
  else {
    fmt.printfln("Usage: %s playlist", os.args[0])
    os.exit(0)
  }
  
  songs := make([dynamic]^SongData, len(songData), len(songData))
  for i := 0; i < len(songData); i += 1 { songs[i] = &songData[i] }
  app.playlist = Playlist{
    songData = songData,
    songs = songs,
    name = filepath.short_stem(listFile),
    activeSongIdx = -1,
  }
  app.playlistFileAbsPath = listFile
  if !filepath.is_abs(listFile) { app.playlistFileAbsPath, _ = filepath.abs(listFile) }

  // volume 1 is way too high
  if app.volume == 0 { app.volume = 0.18 }

  InitRaylib(app)
  InitPartial(rawApp, rawInput)

  // NOTE: Starting up audio takes very long so I do a 'fake' ui first
  {
    Render(app, input)
    ray.InitAudioDevice()
  }

  ray.SetTargetFPS(60)
  ray.SetMasterVolume(app.volume)

  return
}

@export
InitPartial :: proc(rawApp: rawptr, rawInput: rawptr)
{
  // Here, startup anything that needs to be restarted each time a new dll comes
  app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  InitClay(app)
}

@export
DeInitPartial :: proc(rawApp: rawptr, rawInput: rawptr)
{
  // Here, close anything that needs to be restarted each time a new dll comes
  //app := cast(^AppData)rawApp
  //input := cast(^Input)rawInput

  Clay_Close()
}

@export
DeInitAll :: proc(rawApp: rawptr, rawInput: rawptr)
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput
  DeInitPartial(rawApp, rawInput)

  for &f in app.fonts { ray.UnloadFont(f) }
  ray.CloseAudioDevice()
  ray.CloseWindow()

  {
    playlistAbsPathData := transmute([]u8)app.playlistFileAbsPath
    dataFile: DataFile
    dataFile.volume = app.volume
    dataFile.previousSongLen = i32(len(playlistAbsPathData))
    dF, err := os.open(DATAFILE_NAME, os.O_TRUNC | os.O_CREATE)
    fmt.assertf(err == nil, "Could not open file: %s: %v", DATAFILE_NAME, err)
    bytesWritten: int = ---
    bytesWritten, err = os.write_ptr(dF, &app.volume, size_of(app.volume))
    assert(err == nil)
    bytesWritten, err = os.write_ptr(dF, &dataFile.previousSongLen, size_of(dataFile.previousSongLen))
    assert(err == nil)
    //bytesWritten, err = os.write(dF, slice.bytes_from_ptr(&dataFile, int(offset_of(DataFile, previousSongLen))))
    //assert(err == nil && bytesWritten == int(offset_of(DataFile, previousSongLen)))
    bytesWritten, err = os.write(dF, playlistAbsPathData)
    assert(err == nil && bytesWritten == len(playlistAbsPathData)*size_of(playlistAbsPathData[0]))
    os.close(dF)
  }

  // NOTE: Spall deInit
  spall.buffer_destroy(&app.spall_ctx, &app.spall_buffer)
  delete(app.spall_backing_buffer)
  spall.context_destroy(&app.spall_ctx)

  delete(app.playlist.songs)
  delete(app.playlist.songData)
  free(app)
  free(input)
}

@export MemorySize :: proc() -> (int, int) { return size_of(AppData), size_of(Input) }

NextSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
  app.playlist.activeSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)
}

PrevSong :: proc(app: ^AppData) {
  newIdx := (app.playlist.activeSongIdx - 1) %% len(app.playlist.songs)
  app.playlist.activeSongIdx = newIdx
  ChangeLoadedMusicStream(app, newIdx)
}

Update :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  ray.UpdateMusicStream(app.music)

  // If the song finished, go to the next
  if !app.musicPause && app.musicLoaded && !ray.IsMusicStreamPlaying(app.music) {
    NextSong(app)
  }

  // volume
  if ray.IsKeyPressed(.UP) {
    app.volume = min(app.volume + 0.05, 1.0)
    ray.SetMasterVolume(app.volume)
  }
  if ray.IsKeyPressed(.DOWN) {
    app.volume = max(app.volume - 0.05, 0.0)
    ray.SetMasterVolume(app.volume)
  }

  // song control
  app.musicTimePlayed = ray.GetMusicTimePlayed(app.music)
  if ray.IsKeyPressed(.RIGHT) {
    app.musicTimePlayed = min(app.musicTimePlayed + 5.0, app.musicTimeLength)
    ray.SeekMusicStream(app.music, app.musicTimePlayed)
  } else if ray.IsKeyPressed(.LEFT) {
    app.musicTimePlayed = max(app.musicTimePlayed - 5.0, 0.0)
    ray.SeekMusicStream(app.music, app.musicTimePlayed)
  }
  if ray.IsKeyPressed(.L) {
    app.musicTimePlayed = min(app.musicTimePlayed + 10.0, app.musicTimeLength)
    ray.SeekMusicStream(app.music, app.musicTimePlayed)
  } else if ray.IsKeyPressed(.J) {
    app.musicTimePlayed = max(app.musicTimePlayed - 10.0, 0.0)
    ray.SeekMusicStream(app.music, app.musicTimePlayed)
  }

  if ray.IsKeyPressed(.END) || ray.IsKeyPressed(.KP_1) {
    NextSong(app)
  } else if ray.IsKeyPressed(.HOME) || ray.IsKeyPressed(.KP_7) {
    if app.musicTimePlayed < 12.0 {
      PrevSong(app)
    } else {
      ray.SeekMusicStream(app.music, 0.0)
      app.musicTimePlayed = 0.0
    }
  }
  
  // NOTE: Randomize song order
  if ray.IsKeyPressed(.R) {
    app.playlist.activeSongIdx = 0
    app.musicPause = false
    rand.shuffle(app.playlist.songs[:])
    ChangeLoadedMusicStream(app, 0)
  }

  input.deltaTime = ray.GetFrameTime()
  input.mousePos = ray.GetMousePosition()
  input.mouseLeftDown = ray.IsMouseButtonDown(.LEFT)
  input.mouseLeftReleased = ray.IsMouseButtonReleased(.LEFT)
  input.mouseWheel = ray.GetMouseWheelMoveV()
  app.screenWidth = ray.GetScreenWidth()
  app.screenHeight = ray.GetScreenHeight()

  if app.musicLoaded && (ray.IsKeyPressed(.K) || ray.IsKeyPressed(.SPACE)) {
    app.musicPause = !app.musicPause
    if app.musicPause { ray.PauseMusicStream(app.music) }
    else { ray.ResumeMusicStream(app.music) }
  }

  //timePlayed := ray.GetMusicTimePlayed(music)/ray.GetMusicTimeLength(music)
  //fmt.println(timePlayed)

  UI_Prepare(app, input)
}

Render :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  // Generate the auto layout for rendering
  //currentTime := ray.GetTime()
  UIRenderCommands := UI_Calculate(app, input)

  ray.BeginDrawing()
  ray.ClearBackground(ray.BLACK)

  RayUIRender(&UIRenderCommands, &app.fonts[0])

  ray.EndDrawing()
}

@export
MainLoop :: proc(rawApp: rawptr, rawInput: rawptr) -> bool
{
  app := cast(^AppData)rawApp
  input := cast(^Input)rawInput
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, "update & render")

  free_all(context.temp_allocator)

  shouldQuit := ray.WindowShouldClose()
  if ray.IsWindowMinimized() {
    // TODO: Also decrease fps?
    ray.UpdateMusicStream(app.music)
    if !app.musicPause && app.musicLoaded && !ray.IsMusicStreamPlaying(app.music) {
      newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
      app.playlist.activeSongIdx = newIdx
      ChangeLoadedMusicStream(app, newIdx)
    }
    ray.BeginDrawing(); ray.EndDrawing() // end frame
  }
  else {
    Update(app, input)
    Render(app, input)
  }
  return shouldQuit
}