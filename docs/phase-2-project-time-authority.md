# Phase 2 - Project Time Authority And Playback Resolver

`Phase 2` adds engine-owned project-time resolution without replacing playback
runtime ownership yet.

## Delivered In This Phase

- engine-side playback resolver at project timeline time
- resolved active clip / local clip time / source time snapshot
- resolved next adjacent clip snapshot
- Flutter bridge method for project-time playback resolution
- safe UI reconciliation hook that can recover selected clip from engine
  authority when project structure changes

## What This Phase Does

- establishes the engine as the source of truth for:
  - active clip at timeline time `T`
  - local clip time
  - source time
  - next adjacent clip
- prepares the exact authority needed for:
  - multi-clip hard-cut runtime
  - adjacent decoder prewarm
  - later multi-layer composition

## What This Phase Does Not Do

- no seamless clip-to-clip runtime handoff yet
- no decoder pool yet
- no multi-clip scrub runtime yet
- no C++/Vulkan cutover yet
