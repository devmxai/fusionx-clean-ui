# Dedicated Scrub Architecture

## Goal

Move live scrub out of the single playback decoder path so finger movement can
drive a dedicated preview pipeline without fighting normal playback state.

## Landed In V17

- `FusionXPreviewCoordinator`
  - owns two native preview targets
  - playback preview target
  - scrub preview target
- `FusionXDecoderSession`
  - remains the playback-focused session for:
    - load
    - play
    - pause
    - exact seek
    - trim
- `FusionXScrubSession`
  - owns a dedicated scrub executor
  - owns a dedicated scrub render target
  - updates transport position independently from playback rendering
- `FusionXEngineController`
  - routes commands between playback and scrub sessions
  - activates scrub preview only after the scrub lane has a real frame ready
  - commits the final scrub position back to playback on `endScrub`

## Refined In V19

- `FusionXScrubSession`
  - no longer treats live scrub as exact-source decode on every move
  - builds a native proxy cache of quantized preview buckets
  - prewarms buckets around the current source position first
  - extends warmup through the clip in the background
  - resolves the nearest ready proxy frame immediately during drag
- `FusionXPreviewCoordinator`
  - keeps playback visible until the scrub lane has a real frame to show
- `FusionXEngineController`
  - keeps playback session responsible for:
    - play
    - pause
    - exact seek
    - end-of-scrub exact resolve
  - keeps scrub session responsible for:
    - drag preview only

## Current Command Flow

- `beginScrub`
  - pause playback if needed
  - request an initial scrub frame
  - stay on playback preview until scrub has a real frame ready
- `scrubTo`
  - send the latest scrub target to `FusionXScrubSession`
  - resolve the nearest ready proxy bucket from native cache
- `endScrub`
  - flush pending scrub target
  - commit the final position back to playback
- `play`
  - switch preview lane back to playback
  - start playback session

## Why This Is Better

- scrub no longer shares the same preview producer as playback
- playback start is no longer forced to compete directly with live scrub preview
- the preview lane can be evolved later without changing Flutter UI contracts
- live drag preview no longer depends on exact-source decode for every finger
  move
- this creates a clean place for:
  - proxy media
  - intraframe scrub sources
  - future compositor ownership

## What Still Needs To Improve

- scrub proxy warmup still needs real-device validation on varied clips
- exact end-of-scrub resolve still depends on playback exact seek
- playback session is still implemented in the older `FusionXDecoderSession`
  class and should eventually be renamed to `FusionXPlaybackSession`
- full professional scrub behavior still requires:
  - stronger proxy or all-I scrub media generation if cached preview buckets are
    still not sufficient on hardware
  - dedicated exact resolve strategy
  - preview coordinator ownership over more than raw texture switching
