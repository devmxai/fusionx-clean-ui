# FusionX Clean UI

FusionX Clean UI is the active Android-first editor shell and engine foundation
for rebuilding FusionX in controlled production phases.

This repository is no longer a mock UI experiment. The original Flutter editor
surface is wired to a real Android playback and scrub pipeline, and the current
goal is to grow that base into a professional mobile editor step by step.

## Current Status

Current milestone:

- `Beta 6`
- this beta is the first timeline-editing handoff after the long
  preview/scrub stabilization cycle
- import, first-frame rendering, playback, seek, trim, bidirectional scrub,
  inertial timeline release, pinch zoom, cut, selection, and basic split-delete
  flow are now working inside the original product UI
- split timelines now keep their filmstrip populated more naturally by reusing
  the original strip as a shared reference instead of rebuilding both halves as
  brand-new strips after every cut
- the editor is now beyond “single clip playback demo” and has entered a
  practical editing-foundation stage

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

## Beta 6 Notes

What `Beta 6` means:

- the original product UI is still preserved as the only editor surface
- Android preview/playback/trim/import remain stable enough to keep building on
- the timeline is no longer limited to scrub only; it now has the first real
  editing tools and interactions
- split/cut behavior has become fast enough to use as a real editing action,
  not just a visual mock
- the repository now has a practical editing foundation for moving into the
  next product layers

Main technical highlights of this beta cycle:

- timeline inertial release was added and tuned to feel closer to mobile editor
  behavior
- timeline pinch zoom was added so the user can navigate by coarse seconds or
  finer frame-level precision
- split/cut was wired to the actual timeline model
- split seams and transition bridge placeholders were added
- selection highlighting and basic delete behavior were added for split
  segments
- import poster seeding reduced black placeholders on the timeline
- split filmstrip reuse now keeps the left and right halves visually populated
  by cropping a shared reference strip instead of regenerating both halves from
  scratch after every cut

## Known Limitations

Known issues in the current `Beta 6` baseline:

- the preview metadata column still overflows at the default narrow widget-test
  viewport; this is the current open review finding in
  [fusionx_clean_ui_screen.dart](/Users/mx/Documents/New%20project/fusionx-clean-ui/lib/features/editor/presentation/screens/fusionx_clean_ui_screen.dart)
- multi-segment delete is not generalized yet; the current delete flow is meant
  for the basic split workflow rather than a full nonlinear project model
- timeline polish can still improve for very fine micro-scrub feel and for
  larger future project complexity

## Next Phase

The next major phase after `Beta 6` should focus on broader editor depth rather
than re-solving the already-stabilized preview foundation:

- audio phase 0
- richer project and timeline structure
- generalized clip edit operations beyond a single split pair
- continued renderer and compositor evolution
- export and later advanced editor behaviors

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
