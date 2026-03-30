# FusionX Engine Build Plan

Status: Active
Date: March 30, 2026

## Build Principle

Build the engine in hard gates.

Do not start a later stage before the current stage is verified on a real Android device.

## Stage 0: Clean Baseline

Goal:

- Flutter shell is stable
- layout errors are fixed
- contracts and repo structure are ready

Done when:

- `flutter analyze` passes
- `flutter test` passes
- engine docs and scaffolding exist in repo

## Stage 1: Android Preview Core

Goal:

- import one MP4 from UI
- attach native preview surface
- decode and display video
- play
- pause
- seek
- trim start and trim end

Done when:

- APK works on a physical Android device
- no transport freeze
- no decoder leaks in repeated open and close cycles
- trim affects preview range correctly

Validation:

- manual APK install
- play/pause loop test
- seek sweep test
- trim edge-case test

## Stage 2: Native Audio

Goal:

- Oboe playback path
- stable audio clock
- sync with preview path

Done when:

- audio starts cleanly
- seek lands at correct audible position
- pause and resume do not glitch badly

## Stage 3: Timeline Core V1

Goal:

- native-owned clip model
- undo
- redo
- serialization

Done when:

- UI no longer owns edit truth
- all stage 1 operations are command-driven

## Stage 4: Multi-Clip Single Track

Goal:

- insert multiple clips
- split
- move
- delete
- preview clip-to-clip continuity

Done when:

- no broken playhead transitions between adjacent clips
- edit commands remain deterministic

## Stage 5: Export V1

Goal:

- independent export snapshot
- H.264 first
- progress and cancellation

Done when:

- export works without depending on preview state
- output file is valid on-device

## Stage 6: Multi-Track And Basic Compositing

Goal:

- video and audio tracks
- basic stacking
- crop, fit, opacity

Done when:

- playback remains responsive
- compositor cost is measurable and bounded

## Stage 7: iOS Bring-Up

Goal:

- reuse contracts and shared core
- native iOS preview and transport

Done when:

- same contract surface works on iOS

## Execution Rules

- no effects before stable preview and transport
- no transitions before stable single-track editing
- no export before preview is proven
- no iOS before Android contracts are stable
- every sensitive stage requires a real APK test pass
