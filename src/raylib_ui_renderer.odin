package main

import "core:math"
import "base:runtime"
import ray "vendor:raylib"
import clay "clay-odin"

Raylib_camera: ray.Camera

temp_render_buffer: [^]u8
temp_render_buffer_len: int

Clay_Close :: #force_inline proc()
{
  if temp_render_buffer != nil do free(temp_render_buffer)
  temp_render_buffer_len = 0
}

// https://github.com/nicbarker/clay/blob/main/renderers/raylib/clay_renderer_raylib.c#L143
RayUIRender :: proc(renderCommands: ^clay.ClayArray(clay.RenderCommand), fonts: [^]ray.Font)
{
  CLAY_RECTANGLE_TO_RAYLIB_RECTANGLE :: #force_inline proc(rectangle: clay.BoundingBox) -> ray.Rectangle
  {
    return ray.Rectangle{ x = rectangle.x, y = rectangle.y, width = rectangle.width, height = rectangle.height }
  }

  CLAY_COLOR_TO_RAYLIB_COLOR :: #force_inline proc(color: clay.Color) -> ray.Color
  {
    return ray.Color{ u8(math.round(color.r)), u8(math.round(color.g)), u8(math.round(color.b)), u8(math.round(color.a)) }
  }

  CustomLayoutElementType :: enum {
    Model3D,
  }

  CustomLayoutElement_3DModel :: struct {
    model: ray.Model,
    scale: f32,
    position: ray.Vector3,
    rotation: ray.Matrix,
  }

  CustomLayoutElement :: struct {
    type: CustomLayoutElementType,
    customData: struct #raw_union {
      model: CustomLayoutElement_3DModel,
    },
  }

  GetScreenToWorldPointWithZDistance :: proc(position: ray.Vector2, camera: ray.Camera, screenWidth, screenHeight: int, zDistance: f32) -> ray.Ray
  {
    lightray: ray.Ray

    // Calculate normalized device coordinates
    // NOTE: y value is negative
    x := (2.0*position.x)/(f32(screenWidth) - 1.0)
    y := 1.0 - (2.0*position.y)/f32(screenHeight)
    z : f32 = 1.0

    deviceCoords := ray.Vector3{ x, y, z }

    // Calculate view matrix from camera look at
    matView := ray.MatrixLookAt(camera.position, camera.target, camera.up)

    matProj := ray.Matrix(1)

    if camera.projection == .PERSPECTIVE {
      // Calculate projection matrix from perspective
      matProj = ray.MatrixPerspective(camera.fovy*ray.DEG2RAD, f32(f64(screenWidth)/f64(screenHeight)), 0.01, zDistance)
    }
    else if camera.projection == .ORTHOGRAPHIC {
      aspect := f32(f64(screenWidth)/f64(screenHeight))
      top : f32 = camera.fovy/2.0
      right := top*aspect

      matProj = ray.MatrixOrtho(-right, right, -top, top, 0.01, 1000.0)
    }

    // Unproject far/near points
    nearPoint := ray.Vector3Unproject(ray.Vector3{deviceCoords.x, deviceCoords.y, 0.0}, matProj, matView)
    farPoint := ray.Vector3Unproject(ray.Vector3{deviceCoords.x, deviceCoords.y, 1.0}, matProj, matView)

    // Calculate normalized direction vector
    direction := ray.Vector3Normalize(farPoint - nearPoint)

    lightray.position = farPoint

    // Apply calculated vectors to ray
    lightray.direction = direction

    return lightray
  }


  for j : i32 = 0; j < renderCommands.length; j += 1
  {
    renderCommand := clay.RenderCommandArray_Get(renderCommands, j)
    boundingBox := renderCommand.boundingBox

    switch renderCommand.commandType
    {
      case .Text: {
        textData := &renderCommand.renderData.text
        fontToUse := fonts[textData.fontId]
        strlen := int(textData.stringContents.length + 1)

        // NOTE: temp_render_buffer_len isn't necessary here if I just use a []u8
        if strlen > temp_render_buffer_len {
          // Grow the temp buffer if we need a larger string
          if temp_render_buffer != nil { free(temp_render_buffer) }
          temp_render_buffer = make([^]u8, strlen)
          temp_render_buffer_len = strlen
        }

        // Raylib uses standard C strings so isn't compatible with cheap slices, we need to clone the string to append null terminator
        runtime.mem_copy_non_overlapping(temp_render_buffer, textData.stringContents.chars, int(textData.stringContents.length))
        temp_render_buffer[textData.stringContents.length] = 0
        ray.DrawTextEx(fontToUse, cstring(temp_render_buffer), ray.Vector2{boundingBox.x, boundingBox.y}, f32(textData.fontSize), f32(textData.letterSpacing), CLAY_COLOR_TO_RAYLIB_COLOR(textData.textColor))
      }

      case .Image: {
        imageTexture := (cast(^ray.Texture2D)renderCommand.renderData.image.imageData)^
        tintColor := renderCommand.renderData.image.backgroundColor
        if tintColor.r == 0 && tintColor.g == 0 && tintColor.b == 0 && tintColor.a == 0 {
          tintColor = clay.Color{255, 255, 255, 255}
        }
        ray.DrawTextureEx(imageTexture, ray.Vector2{boundingBox.x, boundingBox.y}, 0,
          boundingBox.width / f32(imageTexture.width), CLAY_COLOR_TO_RAYLIB_COLOR(tintColor))
      }

      case .ScissorStart: {
        ray.BeginScissorMode(i32(math.round(boundingBox.x)), i32(math.round(boundingBox.y)),
          i32(math.round(boundingBox.width)), i32(math.round(boundingBox.height)))
      }
      case .ScissorEnd: {
        ray.EndScissorMode()
      }

      case .Rectangle: {
        config := &renderCommand.renderData.rectangle
        if config.cornerRadius.topLeft > 0 {
          radius := (config.cornerRadius.topLeft*2)/f32(boundingBox.height if boundingBox.width > boundingBox.height else boundingBox.width)
          ray.DrawRectangleRounded(ray.Rectangle{boundingBox.x, boundingBox.y, boundingBox.width, boundingBox.height},
            radius, 8, CLAY_COLOR_TO_RAYLIB_COLOR(config.backgroundColor))
        }
        else {
          ray.DrawRectangle(i32(boundingBox.x), i32(boundingBox.y), i32(boundingBox.width), i32(boundingBox.height),
            CLAY_COLOR_TO_RAYLIB_COLOR(config.backgroundColor))
        }
      }

      case .Border: {
        config := &renderCommand.renderData.border
        // Left border
        if config.width.left > 0 {
          ray.DrawRectangle(i32(math.round(boundingBox.x)), i32(math.round(boundingBox.y + config.cornerRadius.topLeft)),
            i32(config.width.left), i32(math.round(boundingBox.height - config.cornerRadius.topLeft - config.cornerRadius.bottomLeft)),
            CLAY_COLOR_TO_RAYLIB_COLOR(config.color))
        }
        // Right border
        if config.width.right > 0 {
          ray.DrawRectangle(i32(math.round(boundingBox.x + boundingBox.width - f32(config.width.right))), i32(math.round(boundingBox.y + config.cornerRadius.topRight)),
            i32(config.width.right), i32(math.round(boundingBox.height - config.cornerRadius.topRight - config.cornerRadius.bottomRight)),
            CLAY_COLOR_TO_RAYLIB_COLOR(config.color))
        }
        // Top border
        if config.width.top > 0 {
          ray.DrawRectangle(i32(math.round(boundingBox.x + config.cornerRadius.topLeft)), i32(math.round(boundingBox.y)),
            i32(math.round(boundingBox.width - config.cornerRadius.topLeft - config.cornerRadius.topRight)), i32(config.width.top),
            CLAY_COLOR_TO_RAYLIB_COLOR(config.color))
        }
        // Bottom border
        if config.width.bottom > 0 {
          ray.DrawRectangle(i32(math.round(boundingBox.x + config.cornerRadius.bottomLeft)), i32(math.round(boundingBox.y + boundingBox.height - f32(config.width.bottom))),
            i32(math.round(boundingBox.width - config.cornerRadius.bottomLeft - config.cornerRadius.bottomRight)), i32(config.width.bottom),
            CLAY_COLOR_TO_RAYLIB_COLOR(config.color))
        }
        if config.cornerRadius.topLeft > 0 {
          ray.DrawRing(ray.Vector2{ math.round(boundingBox.x + config.cornerRadius.topLeft), math.round(boundingBox.y + config.cornerRadius.topLeft) },
            math.round(config.cornerRadius.topLeft - f32(config.width.top)), config.cornerRadius.topLeft, 180, 270, 10, CLAY_COLOR_TO_RAYLIB_COLOR(config.color));
        }
        if config.cornerRadius.topRight > 0 {
          ray.DrawRing(ray.Vector2{ math.round(boundingBox.x + boundingBox.width - config.cornerRadius.topRight), math.round(boundingBox.y + config.cornerRadius.topRight) },
            math.round(config.cornerRadius.topRight - f32(config.width.top)), config.cornerRadius.topRight, 270, 360, 10, CLAY_COLOR_TO_RAYLIB_COLOR(config.color));
        }
        if config.cornerRadius.bottomLeft > 0 {
          ray.DrawRing(ray.Vector2{ math.round(boundingBox.x + config.cornerRadius.bottomLeft), math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomLeft) },
            math.round(config.cornerRadius.bottomLeft - f32(config.width.top)), config.cornerRadius.bottomLeft, 90, 180, 10, CLAY_COLOR_TO_RAYLIB_COLOR(config.color));
        }
        if config.cornerRadius.bottomRight > 0 {
          ray.DrawRing(ray.Vector2{ math.round(boundingBox.x + boundingBox.width - config.cornerRadius.bottomRight), math.round(boundingBox.y + boundingBox.height - config.cornerRadius.bottomRight) },
            math.round(config.cornerRadius.bottomRight - f32(config.width.bottom)), config.cornerRadius.bottomRight, 0.1, 90, 10, CLAY_COLOR_TO_RAYLIB_COLOR(config.color));
        }
      }

      case .Custom: {
        config := &renderCommand.renderData.custom
        customElement := cast(^CustomLayoutElement)config.customData
        if customElement == nil { continue }
        switch customElement.type {
          case .Model3D: {
            rootBox := renderCommands.internalArray[0].boundingBox
            scaleValue : f32 = min(min(1, 786 / rootBox.height)*max(1, rootBox.width/1024), 1.5)
            positionRay := GetScreenToWorldPointWithZDistance(ray.Vector2{renderCommand.boundingBox.x + renderCommand.boundingBox.width/2,
                renderCommand.boundingBox.y + renderCommand.boundingBox.height/2 + 20},
              Raylib_camera, int(math.round(rootBox.width)), int(math.round(rootBox.height)), 140)
            ray.BeginMode3D(Raylib_camera)
              ray.DrawModel(customElement.customData.model.model, positionRay.position, customElement.customData.model.scale*scaleValue, ray.WHITE) // Draw 3d model with texture
            ray.EndMode3D()
          }
        }
      }

      case .None: { assert(false, "unreachable") }
    }
  }
}