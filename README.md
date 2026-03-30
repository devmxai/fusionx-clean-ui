# FusionX Clean UI

FusionX Clean UI is now the active Android-first editor shell and native engine
foundation for rebuilding FusionX from scratch in controlled phases.

The project no longer represents a pure mock UI baseline. The original Flutter
editor screen is already wired to a real Android native preview foundation, and
the repository is being evolved step by step toward a professional mobile video
editor.

## Current Status

Current milestone:

- `Beta 1`
- this version is considered a good Android-first baseline for continuing the
  engine build, even though some scrub edge cases and advanced editor features
  are still open
- the project is now past pure foundation work and can move into the next,
  larger engine phase from a usable baseline

Built so far:

- original FusionX editor UI remains the main product surface
- Flutter is used as the UI layer
- Android native playback foundation is wired behind the original UI
- Vulkan Phase 0 bootstrap is now wired into the Android native layer
- Vulkan Phase 1 preview session now renders directly to the app preview surface
- a real proxy conformer and dedicated proxy scrub session are now wired into
  the Android engine as the next scrub path
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
- Vulkan GPU compositor
- independent export pipeline
- iOS native engine later

Current implementation is in a controlled transition:

- the existing Android decoder preview path remains active for clip playback and
  exact seek
- a new Vulkan-native preview session now attaches to the real preview surface
  and renders native frames in idle mode
- live scrub is now being moved toward a dedicated proxy path:
  - source clip playback remains on the original decoder session
  - scrub can now prepare a separate low-resolution proxy clip in app cache
  - scrub is routed through a dedicated native scrub session when the proxy is
    ready
- the next step is validating whether the new proxy scrub lane materially
  improves device behavior, then deciding whether clip preview ownership should
  move deeper into the Vulkan renderer path

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
- build and prepare a dedicated scrub proxy clip in the Android engine

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
- playback preview vs scrub preview ownership
- native decoder seek/render behavior
- dedicated scrub pipeline behavior

Latest attempt in progress:

- stopped treating the current scrub/backend path as the long-term renderer
- added a native Vulkan bootstrap library under `android/app/src/main/cpp/`
- the Android engine now creates a real Vulkan preview session and attaches it
  to the playback surface before clip load
- the Android engine plugin still reports Vulkan runtime capabilities from
  native code on startup
- the decoder-based clip playback path remains the legacy runtime for loaded
  media, but idle preview ownership is now Vulkan-backed instead of
  diagnostics-only
- the timeline UI now follows the same live timeline-time notifier used by the
  preview metadata instead of waiting for full-screen rebuilds
- scrub release now stays in a guarded settle window until the handoff back to
  playback completes, so late engine position updates are less likely to pull
  the timeline backward
- the Android scrub session now drains before `endScrub`, `play`, `seek`, and
  `trim` hand control back to playback
- `endScrub` now receives the exact final timeline time from Flutter so the
  playback handoff no longer depends only on the last native transport time
  that happened to be committed during scrub
- the scrub cache path no longer round-trips frames through JPEG bytes; it now
  keeps a denser local bitmap cache around the active scrub region so nearby
  movement can be resolved with less decode churn
- Phase 2 has now started by retiring the active dual-surface scrub path from
  `FusionXEngineController`; active scrubbing stays on the same decoder preview
  surface while the real proxy scrub decoder is built next
- the active decoder scrub path now renders progressive intermediate frames
  while chasing the scrub target and uses a wider forward continuation window,
  which is meant to reduce the “first second only” smoothness collapse seen on
  device
- the active scrub decoder now waits for the preview surface to acknowledge
  newly posted frames before outrunning what the user can actually see on
  screen
- progressive scrub rendering no longer starts immediately from the sync-frame
  GOP head after a decoder re-prepare; it now gates progressive display closer
  to the requested target window to reduce repeated “start frame” behavior
- end-of-stream scrub fallback now lands on the last decoded frame instead of
  immediately re-preparing again when the target is near the clip tail
- the temporary `SurfaceTexture` frame listener introduced in the previous
  scrub pacing experiment has been removed because it interfered with Flutter's
  texture presentation and caused black preview playback on device
- the active decoder scrub path now uses a narrower target window and a shorter
  continuation span so it is less willing to show older chase frames that no
  longer match the current finger target
- timeline scrub positioning now uses an anchored finger reference instead of
  accumulated move deltas, which reduces pointer jitter and keeps the requested
  time more stable while dragging
- the decoder scrub continuation span has been widened again after device
  feedback showed collapse near the early GOP/keyframe boundary around the
  fourth second
- Android now builds a dedicated low-resolution scrub proxy clip in app cache
  through a helper conformer path and prepares a separate native scrub session
  for it
- the engine controller now routes scrub to that proxy session when it is
  ready, while keeping source playback and exact end-of-scrub resolve on the
  original playback decoder
- the scrub proxy integration required lifting Android `minSdkVersion` from 19
  to 21 so the current helper stack can build cleanly in this project

This is the current top blocking issue before moving forward to more advanced
editor behaviors.

## Beta 1 Notes

What `Beta 1` means right now:

- the original product UI is no longer a mock-only shell
- native playback and trim are working in the real editor surface
- real media browsing and insertion are working on device
- proxy-based scrub groundwork is now in place
- overall behavior is now good enough to preserve as the first beta baseline
  before moving to larger engine development phases

What `Beta 1` does not mean:

- scrub is not yet at final professional quality on every clip
- the engine is not feature-complete
- export, audio, multi-track, transitions, and effects are still future phases

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
