# Native Engine Scaffold

This folder is the reserved home for the real FusionX engine.

## Intended layout

- `core/`: shared native authority for timeline, commands, and serialization
- `android/`: Android runtime, media, audio, GPU, and export implementation
- `ios/`: iOS runtime, media, audio, GPU, and export implementation

No runtime logic is committed here yet.

The first implementation gate is:

- single imported MP4
- native preview surface on Android
- play
- pause
- seek
- trim start and trim end
