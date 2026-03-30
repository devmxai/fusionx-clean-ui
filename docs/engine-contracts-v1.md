# FusionX Engine Contracts V1

Status: Active
Date: March 30, 2026
Phase: Native Single-Clip Playback Foundation

## Scope

This contract covers Phase 1 only:

- single local video clip
- native Android preview target
- first frame render
- play
- pause
- seek
- trim start
- trim end

This contract does not include:

- audio
- export
- transitions
- effects
- multi-track
- iOS runtime

## Core Rules

1. Flutter sends commands only.
2. Android native owns playback state.
3. Native transport owns playhead and trim window.
4. `Surface` is a render target only.
5. Phase 1 must not use `MediaPlayer` or `ExoPlayer`.

## Time Rules

- internal time unit: `Long`
- canonical precision: microseconds
- exposed time domains:
  - `sourceTimeUs`
  - `clipLocalTimeUs`
  - `timelineTimeUs`

## Commands V1

- `attachRenderTarget`
- `detachRenderTarget`
- `loadClip`
- `play`
- `pause`
- `seekTo`
- `setTrim`
- `dispose`

## Command Payloads

### `attachRenderTarget`

```json
{
  "width": 720,
  "height": 1280
}
```

### `loadClip`

```json
{
  "path": "/absolute/path/file.mp4"
}
```

### `seekTo`

```json
{
  "timelineTimeUs": 2400000
}
```

### `setTrim`

```json
{
  "trimStartUs": 500000,
  "trimEndUs": 6500000
}
```

## Events V1

- `ready`
- `durationResolved`
- `positionChanged`
- `playbackStateChanged`
- `firstFrameRendered`
- `trimChanged`
- `error`

## Event Payload Notes

### `durationResolved`

```json
{
  "sourceDurationUs": 8000000,
  "trimStartUs": 0,
  "trimEndUs": 8000000,
  "clipDurationUs": 8000000,
  "timelineDurationUs": 8000000
}
```

### `positionChanged`

```json
{
  "sourceTimeUs": 1200000,
  "clipLocalTimeUs": 1200000,
  "timelineTimeUs": 1200000
}
```

### `playbackStateChanged`

```json
{
  "state": "playing"
}
```

## Phase 1 Acceptance Gate

Phase 1 is not complete until the APK proves all of these on a real Android device:

- a single local MP4 can be loaded
- first frame appears reliably
- no black surface after load
- play works
- pause works
- seek works
- trim updates playback bounds immediately
- repeated play and pause does not freeze
- repeated seek does not crash
- no ANR during manual verification

## Out Of Scope Until The Gate Passes

- audio path
- waveform generation
- thumbnail system
- transitions
- effects
- export
- multi-track logic
- iOS implementation
