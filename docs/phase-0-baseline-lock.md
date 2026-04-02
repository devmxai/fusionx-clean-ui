# Phase 0 - Beta 6 Baseline Lock

`Phase 0` exists to protect the current `Beta 6` editing baseline before any
multi-clip or multi-layer engine migration begins.

## Goals

- keep the current single-clip import / first-frame / play / pause / seek /
  trim / scrub behavior intact
- close the open narrow-viewport layout regression so the baseline stays
  testable
- freeze the current decoder-owned playback path as the legacy runtime
- define the migration rule that all new playback authority must move into the
  engine, not into Flutter UI state

## Rules For The Next Phases

- Flutter remains the product UI only
- the current `FusionXDecoderSession` path remains the protected
  `single_clip_runtime`
- no multi-clip patching on top of `loadClip()` / single transport ownership
- no Vulkan-first shortcut before project-time authority exists
- every phase must end with:
  - `flutter analyze`
  - relevant tests
  - `release APK`
  - device verification before moving forward

## Planned Build Order

1. engine-owned project model and canvas authority
2. engine-owned project-time resolver
3. multi-clip hard-cut runtime with adjacent decoder ownership
4. multi-clip scrub runtime
5. C++ shared engine core
6. Vulkan compositor for multi-layer rendering
7. audio continuity, transitions, export

## What Phase 0 Changes

- responsive fallback layout for compact widget-test and split-screen viewports
- architecture lock documentation only

## What Phase 0 Does Not Change

- no runtime playback replacement
- no multi-clip logic yet
- no multi-layer compositor yet
- no transition engine yet
