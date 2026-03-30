# FusionX Clean UI

FusionX Clean UI is now the active Android-first editor shell and native engine
foundation for rebuilding FusionX from scratch in controlled phases.

The project no longer represents a pure mock UI baseline. The original Flutter
editor screen is already wired to a real Android native preview foundation, and
the repository is being evolved step by step toward a professional mobile video
editor.

## Current Status

Built so far:

- original FusionX editor UI remains the main product surface
- Flutter is used as the UI layer
- Android native playback foundation is wired behind the original UI
- real local video import works from device media storage
- native preview surface is attached inside the original canvas
- real `play`, `pause`, `seek`, and `trim` work on device
- device media bottom sheet is connected to Android media browsing for:
  - `Video`
  - `Image` browsing
- versioned release APK workflow is in place
- build history is tracked in [docs/build-history.md](docs/build-history.md)

## Architecture Direction

Target architecture:

- Flutter UI only
- shared engine contracts and timeline authority
- Android native engine with `Kotlin + C++`
- Android media stack based on:
  - `MediaExtractor`
  - `MediaCodec`
  - `MediaMuxer`
  - `Oboe`
- GPU compositor
- independent export pipeline
- iOS native engine later

Current implementation is still in the early Android playback foundation phase.

## What Works Right Now

Inside the original editor UI:

- attach native preview surface
- import a real local video clip
- show first frame
- play clip
- pause clip
- seek clip
- trim start and trim end
- browse local device videos from the bottom sheet

## What Is Not Built Yet

Not implemented yet:

- audio engine
- export pipeline
- effects
- transitions
- multi-track engine
- text engine
- lip sync engine
- iOS engine
- final shared native core
- image import into the playback engine

## Current Open Problem

The main unresolved issue right now is:

- timeline live scrub preview is still not truly frame-synchronous with finger
  movement on a real Android device

Current observed behavior:

- dragging right or left updates timeline position
- the preview does not consistently reflect the frame at the exact same moment
  as the finger movement
- on device, preview behavior can still appear delayed or update only after the
  finger is released

This issue is currently being investigated across:

- timeline gesture dispatch
- Flutter to native scrub command flow
- native scrub frame generation
- preview texture and overlay synchronization

This is the current top blocking issue before moving forward to more advanced
editor behaviors.

## Repository Notes

- release APK files are generated locally and versioned in the local workflow
  but are not part of the repository source history
- progress is documented incrementally under `docs/`
- the current development approach is phase-based and device-verified

## Run

```bash
flutter pub get
flutter run
```

## Validation

Common checks used during development:

```bash
flutter analyze
flutter test
flutter build apk --release
```
