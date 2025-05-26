package main

import "core:fmt"
import "core:prof/spall"
import ray "vendor:raylib"
import clay "clay-odin"

Font_Inconsolata :: 0
Font_LiberationMono :: 1


ELEMENT_ID_NIL :: clay.ElementId{ 0, 0, 0, clay.String{true, 0, nil} }

Clay_Init :: proc(fonts: [^]ray.Font, screenWidth, screenHeight: i32)
{
  error_handler :: proc "c" (errorData: clay.ErrorData) {
    // see clay.ErrorData for more data
    ray.TraceLog(.ERROR, "%s", errorData.errorText.chars)
    //switch errorData.errorType {

    //}
  }

  min_memory_size := uint(clay.MinMemorySize())
  memory := make([^]u8, min_memory_size)
  arena: clay.Arena = clay.CreateArenaWithCapacityAndMemory(min_memory_size, memory)
  clay.Initialize(arena, { width = f32(screenWidth), height = f32(screenHeight) }, { handler = error_handler })

  clay.SetMeasureTextFunction(Raylib_MeasureText, fonts)
}

Raylib_MeasureText :: proc "c"(text: clay.StringSlice, config: ^clay.TextElementConfig, userData: rawptr) -> clay.Dimensions
{
  textSize : clay.Dimensions = ---

  maxTextWidth : f32 = 0.0
  lineTextWidth : f32 = 0.0

  textHeight := config.fontSize
  fonts := cast([^]ray.Font)userData
  fontToUse := fonts[config.fontId]
  // Font failed to load, likely the fonts are in the wrong place relative to the execution dir.
  // RayLib ships with a default font, so we can continue with that built in one.
  if fontToUse.glyphs == nil {
    fontToUse = ray.GetFontDefault();
  }

  scaleFactor := f32(config.fontSize)/f32(fontToUse.baseSize)

  byte_index : i32 = 0
  for byte_index < text.length {
    if text.chars[byte_index] == '\n' {
      maxTextWidth = max(maxTextWidth, lineTextWidth)
      lineTextWidth = 0
      byte_index += 1
      continue
    }

    codepoint_bytes : i32 = 0
    codepoint := ray.GetCodepoint(cstring(&text.chars[byte_index]), &codepoint_bytes)
    glyph_index := ray.GetGlyphIndex(fontToUse, codepoint)
    byte_index += codepoint_bytes

    if fontToUse.glyphs[glyph_index].advanceX != 0 { lineTextWidth += f32(fontToUse.glyphs[glyph_index].advanceX) }
    else { lineTextWidth += fontToUse.recs[glyph_index].width + f32(fontToUse.glyphs[glyph_index].offsetX) }
  }

  maxTextWidth = max(maxTextWidth, lineTextWidth)

  textSize.width = maxTextWidth * scaleFactor
  textSize.height = f32(textHeight)

  return textSize
}

UI_Prepare :: proc(app: ^AppData, input: ^Input)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)
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

  playlist := &app.playlist

  UI_mousePos := clay.Vector2{input.mousePos.x, input.mousePos.y}
  clay.SetPointerState(UI_mousePos, input.mouseLeftDown && !scrollbarData.mouseDown)
  clay.SetLayoutDimensions(clay.Dimensions{f32(app.screenWidth), f32(app.screenHeight)})
  if !input.mouseLeftDown { scrollbarData.mouseDown = false }

  if input.mouseLeftDown && !scrollbarData.mouseDown && clay.PointerOver(clay.ID("ScrollBar")) {
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
        scrollContainerData.scrollPosition.y = scrollbarData.positionOrigin.y + (scrollbarData.clickOrigin.y - input.mousePos.y) * ratio.y
      }
      if scrollContainerData.config.horizontal {
        scrollContainerData.scrollPosition.x = scrollbarData.positionOrigin.x + (scrollbarData.clickOrigin.x - input.mousePos.x) * ratio.x
      }
    }
  }

  playlist.activeSongChanged = false
  if input.mouseLeftDown {
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
    ChangeLoadedMusicStream(app, playlist.activeSongIdx)
  }

  SCROLL_INTENSITY :: 2
  clay.UpdateScrollContainers(true, clay.Vector2{input.mouseWheel.x, input.mouseWheel.y*SCROLL_INTENSITY}, input.deltaTime)
}

COLOR_ORANGE :: clay.Color{225, 138, 50, 255}
//COLOR_ORANGE :: clay.Color{10, 138, 50, 255}
COLOR_BLUE :: clay.Color{111, 173, 162, 255}
COLOR_LIGHT :: clay.Color{224, 215, 210, 255}
COLOR_DARKBLUE :: clay.Color{10, 86, 86, 255}
COLOR_RED :: clay.Color{168, 66, 28, 255}

// clay.SizingGrow({})
sizingGrow0 :: clay.SizingAxis{type = .Grow}

SliderDeclaration :: struct {
  id: clay.ElementId,
  width: clay.SizingAxis,
  min, max: f32,
  value: ^f32,
}

GeneralSlider :: proc(app: ^AppData, input: ^Input, sliderDeclaration: SliderDeclaration, loc := #caller_location)
{
  fmt.assertf(sliderDeclaration.value != nil, "nil for value attribute isn't allowed, called from: %v", loc)
  fmt.assertf(sliderDeclaration.id.id != 0, "uninitialized id attribute isn't allowed, called from: %v", loc)
  if clay.UI()({id = sliderDeclaration.id, layout = {sizing = {sliderDeclaration.width, clay.SizingFixed(30)}, childAlignment = {.Center, .Center}}}) {
    dotSize: f32 = 24
    dotRadius: f32 = 12
    percentage := sliderDeclaration.value^/sliderDeclaration.max
    sliderData := clay.GetElementData(sliderDeclaration.id)
    if clay.Hovered() {
      if input.mouseLeftDown { app.sliderSelected = sliderDeclaration.id }
    }
    if app.sliderSelected.id == sliderDeclaration.id.id && app.sliderSelected.offset == sliderDeclaration.id.offset {
      percentage = (input.mousePos.x - sliderData.boundingBox.x) / sliderData.boundingBox.width
      percentage = clamp(percentage, 0.0, 1.0)
      sliderDeclaration.value^ = percentage*sliderDeclaration.max
      if input.mouseLeftReleased { app.sliderSelected = ELEMENT_ID_NIL }
    }

    // NOTE: border attribute is calculated one frame after if I understand correctly, so it's better to use another ui element for the border
    if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFixed(16)}}, cornerRadius = clay.CornerRadiusAll(4), backgroundColor = COLOR_LIGHT}) {}
    if clay.UI()({floating = {attachTo = .Parent, offset = {percentage*sliderData.boundingBox.width - dotSize/2, 0}, attachment = {.LeftCenter, .LeftCenter}}, layout = {sizing = {clay.SizingFixed(dotSize), clay.SizingFixed(dotSize)}, childAlignment = {.Center, .Center}}, /*border = {width = clay.BorderOutside(4), color = {40, 40, 40, 255}},*/ cornerRadius = clay.CornerRadiusAll(dotRadius), backgroundColor = {40, 40, 40, 255}}) {
      if clay.UI()({layout = {sizing = {clay.SizingFixed(20), clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(dotRadius), backgroundColor = COLOR_RED}) {}
    }
  }
}

// NOTE: This one has a slightly different behaviour
SongSlider :: proc(app: ^AppData, input: ^Input, id: clay.ElementId)
{
  if clay.UI()({id = id, layout = {sizing = {sizingGrow0, clay.SizingFixed(30)}, childAlignment = {.Center, .Center}}}) {
    dotSize: f32 = 24
    percentage := app.musicTimePlayed/app.musicTimeLength
    sliderData := clay.GetElementData(id)
    if clay.Hovered() {
      if input.mouseLeftDown { app.sliderSelected = id }
    }
    if app.sliderSelected.id == id.id {
      percentage = (input.mousePos.x - sliderData.boundingBox.x) / sliderData.boundingBox.width
      percentage = clamp(percentage, 0.0, 1.0)
      if input.mouseLeftReleased {
        ray.SeekMusicStream(app.music, percentage*app.musicTimeLength)
        app.sliderSelected = ELEMENT_ID_NIL
      }
    }
    app.musicSliderValue = percentage*app.musicTimeLength

    if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(1), backgroundColor = COLOR_DARKBLUE}) {}
    if clay.UI()({floating = {attachTo = .Parent, offset = {percentage*sliderData.boundingBox.width - dotSize/2, 0}, attachment = {.LeftCenter, .LeftCenter}}, layout = {sizing = {clay.SizingFixed(dotSize), clay.SizingFixed(dotSize)}, childAlignment = {.Center, .Center}}, /*border = {width = clay.BorderOutside(4), color = {40, 40, 40, 255}},*/ cornerRadius = clay.CornerRadiusAll(2), backgroundColor = {40, 40, 40, 255}}) {
      if clay.UI()({layout = {sizing = {clay.SizingFixed(20), clay.SizingFixed(20)}}, cornerRadius = clay.CornerRadiusAll(2), backgroundColor = COLOR_RED}) {}
    }
  }
}

UI_Calculate :: proc(app: ^AppData, input: ^Input) -> clay.ClayArray(clay.RenderCommand)
{
  spall.SCOPED_EVENT(&app.spall_ctx, &app.spall_buffer, #procedure)

  CLAY_BORDER_OUTSIDE :: #force_inline proc(widthValue: u16) -> clay.BorderWidth
  {
    return clay.BorderWidth{widthValue, widthValue, widthValue, widthValue, 0}
  }

  GetElementId :: #force_inline proc(id: string) -> clay.ElementId
  {
    return clay.GetElementId(clay.MakeString(id))
  }

  playlist := &app.playlist

  clay.BeginLayout()

  if clay.UI()({id = clay.ID("OuterContainer"), layout = {sizing = {sizingGrow0, sizingGrow0}, padding = clay.PaddingAll(16), childGap = 16}, backgroundColor = {250,250,255,255}}) {
    if clay.UI()({id = clay.ID("SideBar"), layout = {layoutDirection = .TopToBottom,
      sizing = {width = clay.SizingFixed(300), height = sizingGrow0}, padding = {0, 0, 0, 16}, childGap = 16}, backgroundColor = COLOR_LIGHT})
    {
      if clay.UI()({id = clay.ID("Playlist"), layout = {layoutDirection = .TopToBottom, padding = {16,16,16,16}, sizing = {sizingGrow0, sizingGrow0}}, backgroundColor = COLOR_ORANGE}) {
        clay.TextDynamic(playlist.name, clay.TextConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
        songCountText := fmt.tprintf("%d songs", len(playlist.songs))
        clay.TextDynamic(songCountText, clay.TextConfig({fontSize = 12, textColor = {0, 0, 0, 255}}))
      }

      if clay.UI()({id = clay.ID("SongList"),
        layout = {layoutDirection = .TopToBottom, padding = {16, 24, 0, 0}, childGap = 6, sizing = {width = sizingGrow0}},
        clip = {vertical = true, childOffset = clay.GetScrollOffset()}})
      {
        for songIdx := 0; songIdx < len(playlist.songs); songIdx += 1
        {
          song := playlist.songs[songIdx]
          if clay.UI()({id = clay.ID("song", u32(songIdx)),
            layout = {sizing = {clay.SizingGrow({}), clay.SizingGrow({})}, padding = {16,16,16,16}},
            backgroundColor = clay.Hovered() ? (input.mouseLeftDown ? {176, 90, 34, 255} : {200, 110, 40, 255}) : COLOR_ORANGE}) {
            clay.TextDynamic(song.name, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
          }
        }
      }
    }

    if clay.UI()({id = clay.ID("ActiveSongContainer"), layout = {layoutDirection = .TopToBottom, sizing = {sizingGrow0, sizingGrow0}, padding = {16, 16, 16, 16}, childGap = 16}, backgroundColor = COLOR_LIGHT}) {
      if playlist.activeSongIdx != -1 {
        activeSong := playlist.songs[playlist.activeSongIdx]
        clay.TextDynamic(activeSong.name, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        clay.TextDynamic(activeSong.group, clay.TextConfig({fontSize = 16, textColor = {0, 0, 0, 255}}))
        if app.musicLoaded {
          if clay.UI()({id = clay.ID("MusicInfo"), layout = {layoutDirection = .TopToBottom, sizing = {sizingGrow0, sizingGrow0}, padding = {16, 16, 16, 16}, childGap = 8}, backgroundColor = COLOR_ORANGE}) {
            musicLenSecs := int(app.musicTimeLength)
            musicLenMins := musicLenSecs/60
            musicLenSecs %= 60
            musicPlayedSecs := int(app.musicSliderValue)
            musicPlayedMins := musicPlayedSecs/60
            musicPlayedSecs %= 60
            // NOTE: IMPORTANT: I don't like how this looks, I will for sure do another pass on the ui
            musicText := fmt.tprintf("%2d:%2d/%2d:%2d", musicPlayedMins, musicPlayedSecs, musicLenMins, musicLenSecs)
            clay.TextDynamic(musicText, clay.TextConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))

            if clay.UI()({layout = {sizing = {sizingGrow0, clay.SizingFit({})}, padding = {4, 4, 0, 0}}}) {
              SongSlider(app, input, clay.ID("SongProgressSlider"))
            }

            if clay.UI()({layout = {layoutDirection = .TopToBottom, sizing = {sizingGrow0, sizingGrow0}, childAlignment = {.Right, .Bottom}}}) {
              GeneralSlider(app, input, {id = clay.ID("volumeSlider"), width = clay.SizingPercent(0.4), max = 1.0, value = &app.volume})
              clay.TextDynamic(fmt.tprintf("volume: %3.1f%%", 100.0*app.volume), clay.TextConfig({fontSize = 14, textColor = {0, 0, 0, 255}}))
            }
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