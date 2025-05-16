package main

import "core:fmt"
import "core:prof/spall"
import ray "vendor:raylib"
import clay "clay-odin"

UI_Prepare :: proc(playlist: ^Playlist, mousePos, mouseWheel: ray.Vector2, screenWidth, screenHeight: i32, mouseDown: bool, deltaTime: f32)
{
  spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
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
  clay.UpdateScrollContainers(true, clay.Vector2{mouseWheel.x, mouseWheel.y*SCROLL_INTENSITY}, deltaTime)
}

UI_Calculate :: proc(playlist: ^Playlist, mouseDown: bool) -> clay.ClayArray(clay.RenderCommand)
{
  spall.SCOPED_EVENT(&spall_ctx, &spall_buffer, #procedure)
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