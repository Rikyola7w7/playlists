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

/* TODO:
[ ] Actual error messages
[ ] Improve parser to show errors
[ ] Different thing for active song and playing song, so I can check out info on a song that
    I'm not playing and if I go back to the playing song it doesn't start over
[ ] Automatic scroll down when getting to a song that is offscreen (maybe two before ?)
[x] Store the songs as []^SongData pointing to a []SongData array
[x] Store a file for session data

UI:
[ ] UI for adding a song to the list
[ ] UI to show the amount of song left as a bar
[ ] UI to randomize list order (call the ShuffleSongs proc)
[ ] UI to sort list order by various properties (artist, alphabetical, ...)
[ ] UI to show the details of a song without playing it
[ ] UI for volume controls (slider + info)
[ ] UI rework

[ ] Probably no way to do it in raylib, but try to find out if I can keep the music playing while moving/resizing the window ?
[ ] Icon (winows only ?)

Performance:
[x] Spall measurements
[ ] Thread pool for thread work, will do when more work on threads is required
[ ] ChangeLoadedMusicStream in a different thread so it doesn't stall (it sometimes does for a more than a frame)
*/

spall_ctx: spall.Context
@(thread_local) spall_buffer: spall.Buffer

SongSourceType :: enum {
  None, /* no song source */
  File, /* song is stored locally */
  Link, /* need to look for the song online */
}

SongData :: struct {
  group, name, album: string,
  source: string,
  sourceType: SongSourceType,
}

Playlist :: struct {
  songData: [dynamic]SongData, // NOTE: Should keep original order
  songs: [dynamic]^SongData,
  name: string,
  activeSongIdx: int,
  activeSongChanged: bool,
}

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

// NOTE: I don't really need this function, it's mostly here so odin doesn't complain
//       about an unused import while I haven't used the shuffle anywhere
ShuffleSongs :: #force_inline proc(songs: []SongData)
{
  rand.shuffle(songs)
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

ParseSongs :: proc(data: []u8) -> [dynamic]SongData
{
  spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
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

Font_Inconsolata :: 0
Font_LiberationMono :: 1

music: ray.Music
musicLoaded: bool

ChangeLoadedMusicStream :: proc(playlist: ^Playlist, newIdx: int)
{
  spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
  if playlist.songs[playlist.activeSongIdx].source != "" {
    if musicLoaded {
      ray.UnloadMusicStream(music)
      musicLoaded = false
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
          music = ray.LoadMusicStream(filename)
          music.looping = false
          ray.PlayMusicStream(music)
          musicLoaded = true
        }
        else {
          b: strings.Builder = strings.builder_make_len_cap(0, 40, context.temp_allocator)
          filepath := fmt.sbprintf(&b, "../songs/%s", activeSong.source)
          if os.exists(filepath) {
            file, _ := strings.to_cstring(&b)
            music = ray.LoadMusicStream(file)
            music.looping = false
            ray.PlayMusicStream(music)
            musicLoaded = true
          }
          else {
            fmt.println("Could not find song")
          }
        }
      }
    }
  }
}

AppData :: struct {
  volume: f32,
  playlist: Playlist,
  spall_backing_buffer: []u8,
  screenWidth, screenHeight: i32,

  fonts: [2]ray.Font,
  playlistFileAbsPath: string,
}

DataFile :: struct {
  volume: f32,
  previousSongLen: int, // length of the string
  previousSong: [^]u8,
}
DATAFILE_NAME :: "prog.dat"

InitAll :: proc(app: ^AppData)
{
  // NOTE: Spall init
  spall_ctx = spall.context_create("trace.spall")
  app.spall_backing_buffer = make([]u8, spall.BUFFER_DEFAULT_SIZE)
  spall_buffer = spall.buffer_create(app.spall_backing_buffer, u32(sync.current_thread_id()))
  spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)

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
      listFile = strings.string_from_ptr(&data[offset_of(DataFile, previousSong)], 
          (cast(^int)&data[offset_of(DataFile, previousSongLen)])^)
    }
  }

  if listFile != "" {
    data, ok = os.read_entire_file(listFile)
    assert(ok)
  }
  else {
    fmt.printfln("Usage: %s playlist", os.args[0])
    os.exit(0)
  }
  songData := ParseSongs(data)
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

  InitRaylib(app)
  InitClay(app)
}

InitRaylib :: proc(app: ^AppData)
{
  ray.SetTraceLogLevel(.WARNING)
  ray.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT}) // WINDOW_HIGHDPI
  app.screenWidth = 1000
  app.screenHeight = 800
  ray.InitWindow(app.screenWidth, app.screenHeight, "playlist viewer")
  ray.InitAudioDevice()
}

InitClay :: proc(app: ^AppData)
{
  app.fonts[Font_Inconsolata] = ray.LoadFontEx("../resources/Inconsolata-Regular.ttf", 48, nil, 400)
  ray.SetTextureFilter(app.fonts[Font_Inconsolata].texture, .BILINEAR)
  app.fonts[Font_LiberationMono] = ray.LoadFontEx("../resources/liberation-mono.ttf", 48, nil, 400)
  ray.SetTextureFilter(app.fonts[Font_LiberationMono].texture, .BILINEAR)
  Clay_Init(&app.fonts[0], app.screenWidth, app.screenHeight)
}

DeInitAll :: proc(app: ^AppData)
{
  Clay_Close()

  ray.CloseAudioDevice()
  ray.CloseWindow()
  
  playlistAbsPathData := transmute([]u8)app.playlistFileAbsPath
  dataFile: DataFile
  dataFile.volume = app.volume
  dataFile.previousSongLen = len(playlistAbsPathData)
  dF, err := os.open(DATAFILE_NAME, os.O_WRONLY)
  assert(err == nil)
  bytesWritten: int = ---
  bytesWritten, err = os.write(dF, slice.bytes_from_ptr(&dataFile, int(offset_of(DataFile, previousSong))))
  assert(err == nil && bytesWritten == int(offset_of(DataFile, previousSong)))
  bytesWritten, err = os.write(dF, playlistAbsPathData)

  delete(app.playlist.songs)
  delete(app.playlist.songData)

  // NOTE: Spall deInit
  spall.buffer_destroy(&spall_ctx, &spall_buffer)
  delete(app.spall_backing_buffer)
  spall.context_destroy(&spall_ctx)
}

main :: proc()
{
  app: AppData
  InitAll(&app)
  defer DeInitAll(&app)

  ray.SetTargetFPS(60)

  // volume 1 is way too high
  if app.volume == 0 { app.volume = 0.18 }

  ray.SetMasterVolume(app.volume)
  musicPause := false
  for !ray.WindowShouldClose() {
    spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, "update & render")
    spall._buffer_begin(&spall_ctx, &spall_buffer, "update")

    ray.UpdateMusicStream(music)

    deltaTime := ray.GetFrameTime()

    if !musicPause && musicLoaded && !ray.IsMusicStreamPlaying(music) {
      newIdx := (app.playlist.activeSongIdx + 1) % len(app.playlist.songs)
      app.playlist.activeSongIdx = newIdx
      ChangeLoadedMusicStream(&app.playlist, newIdx)
    }

    mousePos := ray.GetMousePosition()
    mouseLeftDown := ray.IsMouseButtonDown(.LEFT)
    mouseWheel : ray.Vector2 = ray.GetMouseWheelMoveV()
    app.screenWidth = ray.GetScreenWidth()
    app.screenHeight = ray.GetScreenHeight()

    if musicLoaded && (ray.IsKeyPressed(.P) || ray.IsKeyPressed(.SPACE)) {
      musicPause = !musicPause
      if musicPause { ray.PauseMusicStream(music) }
      else { ray.ResumeMusicStream(music) }
    }

    //timePlayed := ray.GetMusicTimePlayed(music)/ray.GetMusicTimeLength(music)
    //fmt.println(timePlayed)

    UI_Prepare(&app.playlist, mousePos, mouseWheel, app.screenWidth, app.screenHeight, mouseLeftDown, deltaTime)

    spall._buffer_end(&spall_ctx, &spall_buffer) // update
    spall._buffer_begin(&spall_ctx, &spall_buffer, "render")

    // Generate the auto layout for rendering
    //currentTime := ray.GetTime()
    UIRenderCommands := UI_Calculate(&app.playlist, mouseLeftDown)

    ray.BeginDrawing()
    ray.ClearBackground(ray.BLACK)

    RayUIRender(&UIRenderCommands, &app.fonts[0])

    ray.EndDrawing()

    spall._buffer_end(&spall_ctx, &spall_buffer) // render
  }
}