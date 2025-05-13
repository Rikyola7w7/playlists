package main

import "core:os"
import "core:fmt"
import "core:slice"
import "core:strings"
import "core:math/rand"
import "core:path/filepath"
import ray "vendor:raylib"
import clay "shared:clay-odin"

/* TODO:
[ ] Actual error messages
[ ] Improve parser to show errors
[ ] Different thing for active song and playing song, so I can check out info on a song that
    I'm not playing and if I go back to the playing song it doesn't start over
[ ] Automatic scroll down when getting to a song that is offscreen (maybe two before ?)
[x] Store the songs as []^SongData pointing to a []SongData array

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
*/

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

UI_Prepare :: proc(playlist: ^Playlist, mousePos, mouseWheel: ray.Vector2, screenWidth, screenHeight: i32, mouseDown: bool)
{
  @static UI_debug := false
  @static scrollbarData: struct {
    clickOrigin, positionOrigin: clay.Vector2,
    mouseDown: bool,
  }

  when ODIN_DEBUG {
    if ray.IsKeyPressed(.D) {
      UI_debug = !UI_debug
      clay.SetDebugModeEnabled(UI_debug)
      // TODO: When new odin bindings, use clay.IsDebugModeEnabled() to see if 'x' has been pressed
    }
  }

  UI_mousePos := clay.Vector2{mousePos.x, mousePos.y}
  clay.SetPointerState(UI_mousePos, mouseDown && !scrollbarData.mouseDown)
  clay.SetLayoutDimensions(clay.Dimensions{f32(screenWidth), f32(screenHeight)})
  if !mouseDown { scrollbarData.mouseDown = false }

  if mouseDown && !scrollbarData.mouseDown && clay.PointerOver(clay.ID("ScrollBar")) {
    scrollContainerData := clay.GetScrollContainerData(clay.ID("SongList"))
    scrollbarData.clickOrigin = UI_mousePos
    scrollbarData.positionOrigin = scrollContainerData.scrollPosition^
    scrollbarData.mouseDown = true
  } else if scrollbarData.mouseDown {
    scrollContainerData := clay.GetScrollContainerData(clay.ID("SongList"))
    if scrollContainerData.contentDimensions.height > 0 {
      ratio := clay.Vector2 {
        scrollContainerData.contentDimensions.width / scrollContainerData.scrollContainerDimensions.width,
        scrollContainerData.contentDimensions.height / scrollContainerData.scrollContainerDimensions.height,
      }
      if scrollContainerData.config.vertical {
        scrollContainerData.scrollPosition.y = scrollbarData.positionOrigin.y + (scrollbarData.clickOrigin.y - mousePos.y) * ratio.y
      }
      if scrollContainerData.config.horizontal {
        scrollContainerData.scrollPosition.x = scrollbarData.positionOrigin.x + (scrollbarData.clickOrigin.x - mousePos.x) * ratio.x
      }
    }
  }

  playlist.activeSongChanged = false

  if mouseDown {
    iniActive := playlist.activeSongIdx
    for songIdx := 0; songIdx < len(playlist.songs); songIdx += 1
    {
      if clay.PointerOver(clay.ID("song", u32(songIdx))) {
        playlist.activeSongIdx = songIdx
      }
    }
    if iniActive != playlist.activeSongIdx { playlist.activeSongChanged = true }
  }

  if playlist.activeSongChanged {
    //fmt.println("active song:", playlist.activeSong^)
    ChangeLoadedMusicStream(playlist, playlist.activeSongIdx)
  }

  SCROLL_INTENSITY :: 2
  clay.UpdateScrollContainers(true, clay.Vector2{mouseWheel.x, mouseWheel.y*SCROLL_INTENSITY}, ray.GetFrameTime())
}

UI_Calculate :: proc(playlist: ^Playlist, mouseDown: bool) -> clay.ClayArray(clay.RenderCommand)
{
  COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
  COLOR_BLUE :: clay.Color{111, 173, 162, 255}
  COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
  COLOR_RED :: clay.Color{168, 66, 28, 255}

  CLAY_BORDER_OUTSIDE :: #force_inline proc(widthValue: u16) -> clay.BorderWidth
  {
    return clay.BorderWidth{widthValue, widthValue, widthValue, widthValue, 0}
  }

  GetElementId :: #force_inline proc(id: string) -> clay.ElementId
  {
    return clay.GetElementId(clay.MakeString(id))
  }

  sizingGrow0 := clay.SizingGrow({})

  clay.BeginLayout()

  if clay.UI()({id = clay.ID("OuterContainer"), layout = {sizing = {sizingGrow0, sizingGrow0}, padding = clay.PaddingAll(16), childGap = 16}, backgroundColor = {250,250,255,255}}) {
    if clay.UI()({id = clay.ID("SideBar"), layout = {layoutDirection = .TopToBottom,
      sizing = {width = clay.SizingFixed(300), height = sizingGrow0}, padding = {0, 0, 0, 16}, childGap = 16}, backgroundColor = COLOR_LIGHT})
    {
      if clay.UI()({id = clay.ID("Playlist"), layout = {layoutDirection = .TopToBottom, padding = {16,16,16,16}, sizing = {sizingGrow0, sizingGrow0}}, backgroundColor = COLOR_ORANGE}) {
        clay.Text(playlist.name, clay.TextConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
        songCountText := fmt.tprintf("%d songs", len(playlist.songs))
        clay.Text(songCountText, clay.TextConfig({fontSize = 12, textColor = {0, 0, 0, 255}}))
      }

      if clay.UI()({id = clay.ID("SongList"),
        layout = {layoutDirection = .TopToBottom, padding = {16, 24, 0, 0}, childGap = 6, sizing = {width = sizingGrow0}},
        scroll = {vertical = true}})
      {
        for songIdx := 0; songIdx < len(playlist.songs); songIdx += 1
        {
          song := playlist.songs[songIdx]
          if clay.UI()({id = clay.ID("song", u32(songIdx)),
            layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, padding = {16,16,16,16}},
            backgroundColor = clay.Hovered() ? (mouseDown ? {176, 90, 34, 255} : {200, 110, 40, 255}) : COLOR_ORANGE}) {
            clay.Text(song.name, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
          }
        }
      }

      //if clay.UI()({id = clay.ID("MainContent"), layout = {sizing = {sizingGrow0, sizingGrow0}}, backgroundColor = COLOR_LIGHT}) {}
    }

    if playlist.activeSongIdx != -1 {
      activeSong := playlist.songs[playlist.activeSongIdx]
      if clay.UI()({id = clay.ID("ActiveSongContainer"), layout = {layoutDirection = .TopToBottom, sizing = {sizingGrow0, sizingGrow0}, padding = {16, 16, 16, 16}, childGap = 16}, backgroundColor = COLOR_LIGHT}) {
        clay.Text(activeSong.name, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        clay.Text(activeSong.group, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        if musicLoaded {
          if clay.UI()({id = clay.ID("MusicInfo"), layout = {sizing = {sizingGrow0, sizingGrow0}, padding = {16, 16, 16, 16}}, backgroundColor = COLOR_ORANGE}) {
            musicLenSecs := int(ray.GetMusicTimeLength(music))
            musicLenMins := musicLenSecs/60
            musicLenSecs %= 60
            musicPlayedSecs := int(ray.GetMusicTimePlayed(music))
            musicPlayedMins := musicPlayedSecs/60
            musicPlayedSecs %= 60
            musicText := fmt.tprintf("song length: %2d:%2d\tplayed: %2d:%2d", musicLenMins, musicLenSecs, musicPlayedMins, musicPlayedSecs)
            clay.Text(musicText, clay.TextConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
          }
        }
      }
    }
  }

  scrollData := clay.GetScrollContainerData(GetElementId("SongList"))
  if scrollData.found {
    if clay.UI()({id = clay.ID("ScrollBar"), floating = {attachTo = .ElementWithId,
      offset = {0, -(scrollData.scrollPosition.y/scrollData.contentDimensions.height) * scrollData.scrollContainerDimensions.height},
      zIndex = 1, parentId = GetElementId("SongList").id, attachment = {element = .RightTop, parent = .RightTop}}})
    {
      if clay.UI()({id = clay.ID("ScrollBarButton"),
        layout = {sizing = {clay.SizingFixed(12), clay.SizingFixed((scrollData.scrollContainerDimensions.height/scrollData.contentDimensions.height)*scrollData.scrollContainerDimensions.height)}},
        backgroundColor = clay.PointerOver(clay.ID("ScrollBar")) ? {100, 100, 140, 150} : {120, 120, 160, 150},
        cornerRadius = clay.CornerRadiusAll(6)}) {}
    }
  }

  return clay.EndLayout()
}

InitAll :: proc() -> Playlist
{
  ok: bool
  data: []u8
  if len(os.args) > 1 {
    data, ok = os.read_entire_file(os.args[1])
    assert(ok)
  }
  else {
    fmt.printfln("Usage: %s playlist", os.args[0])
    os.exit(0)
  }
  songData := ParseSongs(data)
  songs := make([dynamic]^SongData, len(songData), len(songData))
  for i := 0; i < len(songData); i += 1 { songs[i] = &songData[i] }
  playlist := Playlist{
    songData = songData,
    songs = songs,
    name = filepath.short_stem(os.args[1]),
    activeSongIdx = -1,
  }

  return playlist
}

main :: proc()
{
  playlist := InitAll()

  ray.SetTraceLogLevel(.WARNING)
  ray.SetConfigFlags({.VSYNC_HINT, .WINDOW_RESIZABLE, .WINDOW_HIGHDPI, .MSAA_4X_HINT}) // WINDOW_HIGHDPI
  screenWidth : i32 = 1000
  screenHeight : i32 = 800
  ray.InitWindow(screenWidth, screenHeight, "playlist viewer")
  defer ray.CloseWindow()
  ray.InitAudioDevice()
  defer ray.CloseAudioDevice()

  defer Clay_Close()
  fonts : [2]ray.Font = ---
  fonts[Font_Inconsolata] = ray.LoadFontEx("../resources/Inconsolata-Regular.ttf", 48, nil, 400)
  ray.SetTextureFilter(fonts[Font_Inconsolata].texture, .BILINEAR)
  fonts[Font_LiberationMono] = ray.LoadFontEx("../resources/liberation-mono.ttf", 48, nil, 400)
  ray.SetTextureFilter(fonts[Font_LiberationMono].texture, .BILINEAR)
  Clay_Init(&fonts[0], screenWidth, screenHeight)

  ray.SetTargetFPS(60)

  musicPause := false
  for !ray.WindowShouldClose() {
    ray.UpdateMusicStream(music)

    // TODO: Is this check good enough?
    if !musicPause && musicLoaded && !ray.IsMusicStreamPlaying(music) {
      newIdx := (playlist.activeSongIdx + 1) % len(playlist.songs)
      playlist.activeSongIdx = newIdx
      ChangeLoadedMusicStream(&playlist, newIdx)
    }

    mousePos := ray.GetMousePosition()
    mouseLeftDown := ray.IsMouseButtonDown(.LEFT)
    mouseWheel : ray.Vector2 = ray.GetMouseWheelMoveV()
    screenWidth = ray.GetScreenWidth()
    screenHeight = ray.GetScreenHeight()

    if musicLoaded && (ray.IsKeyPressed(.P) || ray.IsKeyPressed(.SPACE)) {
      musicPause = !musicPause

      if musicPause { ray.PauseMusicStream(music) }
      else { ray.ResumeMusicStream(music) }
    }

    //timePlayed := ray.GetMusicTimePlayed(music)/ray.GetMusicTimeLength(music)
    //fmt.println(timePlayed)

    UI_Prepare(&playlist, mousePos, mouseWheel, screenWidth, screenHeight, mouseLeftDown)

    // Generate the auto layout for rendering
    //currentTime := ray.GetTime()
    UIRenderCommands := UI_Calculate(&playlist, mouseLeftDown)

    ray.BeginDrawing()
    ray.ClearBackground(ray.BLACK)

    RayUIRender(&UIRenderCommands, &fonts[0])

    free_all(context.temp_allocator)

    ray.EndDrawing()
  }

  delete(playlist.songs)
  delete(playlist.songData)
}