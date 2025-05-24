package main

import "core:prof/spall"
import ray "vendor:raylib"

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


AppData :: struct {
  spall_ctx: spall.Context,
  spall_buffer: spall.Buffer, // NOTE: This must be one per thread
  
  volume: f32,
  playlist: Playlist,
  spall_backing_buffer: []u8,
  screenWidth, screenHeight: i32,
  quit: bool,

  music: ray.Music,
  musicTimeLength: f32,
  musicTimePlayed: f32,
  musicLoaded: bool,
  musicPause: bool,

  fonts: [2]ray.Font,

  playlistFileAbsPath: string,
}

Input :: struct {
  deltaTime: f32,
  mouseWheel: [2]f32,
  mousePos: [2]f32,
  mouseLeftDown: bool,
}