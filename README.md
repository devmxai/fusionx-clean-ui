# FusionX Clean UI

FusionX Clean UI is the active Android-first editor shell and engine foundation
for rebuilding FusionX in controlled production phases.

This repository is no longer a mock UI experiment. The original Flutter editor
surface is wired to a real Android playback and scrub pipeline, and the current
goal is to grow that base into a professional mobile editor step by step.

## Current Status

Current milestone:

- `Beta 7`
- this beta preserves the stable `Beta 6` single-clip foundation and adds the
  first real engine-owned project model, project canvas authority, project-time
  playback resolution, and adjacent runtime handoff work
- first clip canvas locking, multi-clip append behavior, project-time clip
  resolution, and basic adjacent playback continuation are now wired into the
  native engine behind the original Flutter editor UI
- seam continuity has improved compared with the earlier `Beta 6` baseline, but
  `Phase 3` is still in progress and the handoff between clip 1 and clip 2 is
  not yet final professional-quality seamless playback
- the editor is now beyond a single-clip editing baseline and has entered the
  first real multi-clip engine migration stage

Built so far:

- the original FusionX editor UI remains the main product surface
- Flutter is still the UI layer
- Android native playback foundation is wired behind the original UI
- Vulkan bootstrap/runtime groundwork is present in the Android native layer
- a dedicated proxy conformer and proxy scrub session are wired into the
  Android engine
- real local video import works from device media storage
- the native preview surface is attached inside the original canvas
- real `play`, `pause`, `seek`, and `trim` work on device
- forward and reverse scrub work inside the real timeline
- inertial release after swipe is supported for timeline motion
- timeline pinch zoom is supported for coarse and fine navigation
- timeline split/cut is supported with seam marker and transition bridge mock
- selected split segments can be visually targeted and deleted in the basic
  two-half split flow
- filmstrip seeding and reuse now reduce black refresh and unnecessary rebuilds
  on import and after cut
- versioned APK workflow is in place
- build history is tracked in
  [docs/build-history.md](/Users/mx/Documents/New%20project/fusionx-clean-ui/docs/build-history.md)

## Execution Rules

These migration rules are mandatory for all future work:

- no patching outside the current phase just to appear faster
- no jumping to later phases before the current phase is device-verified
- no leaving a phase half-finished and then compensating from a later phase
- only fix regressions early when they directly break already-working behavior
- engine authority must keep moving downward into the native runtime; Flutter
  must not regain playback ownership
- after every completed phase:
  - run validation
  - build a `release APK`
  - open the APK in Finder for device testing

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

Current implementation:

- the Android decoder preview path still owns loaded-clip playback and exact
  seek
- Vulkan bootstrap/runtime capability probing remains wired into the native
  layer, but clip preview runtime ownership still sits with the decoder path
- live scrub is routed through a dedicated proxy path:
  - source clip playback remains on the main decoder session
  - scrub can prepare a separate low-resolution proxy clip in app cache
  - scrub can use a dedicated native scrub session when the proxy is ready
- the current scrub stack includes:
  - all-intra-oriented proxy generation
  - indexed proxy/source time mapping
  - direction-flip handling improvements in Flutter
  - reverse-start dead-zone reduction
  - end-of-scrub and playback handoff hardening
- the current timeline stack includes:
  - inertial release motion
  - pinch zoom
  - cut/split
  - split seam rendering
  - split selection highlighting
  - split filmstrip reuse from a shared reference strip

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
- scrub forward through the clip
- scrub backward through the clip
- change scrub direction without falling back to the earlier broken behavior
- release timeline drag with inertial glide
- zoom the timeline in and out with pinch
- cut the active video clip into two adjacent timeline segments
- render a seam marker and transition bridge mock at the cut point
- select the left or right split segment
- delete the selected segment in the current basic split workflow

## What Is Not Built Yet

Not implemented yet:

- audio engine
- export pipeline
- real transitions
- effects
- multi-track engine
- text engine
- lip sync engine
- iOS engine
- final shared native core
- image import into the playback engine
- generalized delete/edit operations for arbitrary multi-segment timelines

## Beta 7 Notes

What `Beta 7` means:

- the original product UI is still preserved as the only editor surface
- Android preview/playback/trim/import from `Beta 6` remain the protected
  baseline
- the engine now owns:
  - project canvas locking
  - project sync
  - project-time playback resolution
  - active clip runtime requests
  - first adjacent clip handoff path
- multi-clip import no longer behaves like a simple one-clip replace flow
- `Phase 3` has started real adjacent runtime work, but seamless clip-to-clip
  continuity is still not fully closed

Main technical highlights of this beta cycle:

- engine-owned project canvas and timeline project store were added
- project-time resolution now returns active clip, clip-local time, source
  offset, and adjacent clip information from native engine code
- adjacent runtime handoff moved out of pure UI orchestration and into the
  native playback path
- Flutter timeline state no longer rewrites multi-clip seam semantics from late
  runtime metadata events during handoff
- clip selection, preview ownership, and seam stabilization work were advanced
  without abandoning the original UI or the phase plan

## Known Limitations

Known issues in the current `Beta 6` baseline:

- the preview metadata column still overflows at the default narrow widget-test
  viewport; this is the current open review finding in
  [fusionx_clean_ui_screen.dart](/Users/mx/Documents/New%20project/fusionx-clean-ui/lib/features/editor/presentation/screens/fusionx_clean_ui_screen.dart)
- multi-clip seam continuity is improved but not finished yet; a visible handoff
  pause/lag can still appear between clip 1 and clip 2 while `Phase 3`
  continues
- scrub and play around the exact seam are better than the earliest `Phase 3`
  builds, but are not yet final production-grade behavior
- multi-segment delete is not generalized yet; the current delete flow is meant
  for the basic split workflow rather than a full nonlinear project model
- timeline polish can still improve for very fine micro-scrub feel and for
  larger future project complexity

## Next Phase

The next major work after this `Beta 7` snapshot is still to finish the current
runtime phase before any larger engine leap:

- finish `Phase 3` seam continuity and adjacent runtime stability
- complete `Phase 4` multi-clip scrub runtime
- then discuss deeper engine choices such as:
  - `C++` core migration
  - Vulkan compositor
  - possible BMF/BMFLite adoption
  - multi-layer and transitions

## Repository Notes

- release APK files are generated locally and versioned in the local workflow
  but are not part of the repository source history
- progress is documented incrementally under `docs/`
- the development approach is phase-based and device-verified

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
