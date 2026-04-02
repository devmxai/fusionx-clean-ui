# Phase 1 - Engine Project Model And Canvas Authority

`Phase 1` moves the project model itself into the engine before any playback
runtime replacement starts.

## Delivered In This Phase

- engine-side timeline project store on Android
- engine-side project canvas authority
- Flutter -> engine project sync bridge
- engine-returned project canvas snapshot
- append-preserving timeline state on import
- no playback runtime replacement yet

## What This Phase Must Guarantee

- the first visual clip locks the project canvas
- importing later visual clips does not redefine the canvas
- the UI timeline can append additional clips without rebuilding back to a
  one-clip list on metadata events
- Flutter remains a sender of project state and a receiver of canvas authority

## What Still Waits For Later Phases

- project-time playback resolver
- multi-clip hard-cut runtime
- multi-clip scrub runtime
- C++ shared authority core
- Vulkan compositor
- multi-layer render graph
