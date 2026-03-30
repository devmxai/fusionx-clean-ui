# Vulkan Backend Pivot

## Goal

Replace the current Android preview/render backend with a Vulkan-native path
without throwing away the useful parts of the engine that still belong in the
future architecture.

## What We Keep

- Flutter UI shell
- engine contracts
- engine bridge
- transport / playback authority concepts
- Android media I/O building blocks:
  - `MediaExtractor`
  - `MediaCodec`
  - `MediaMuxer`

## What Becomes Legacy

- current decoder-driven preview renderer
- current scrub renderer path
- current `FusionXRenderTarget`-based visual backend

These remain only as a temporary runtime path until Vulkan replaces them.

## Phase 0

Phase 0 is intentionally narrow:

- add Android `externalNativeBuild`
- add a native C++ Vulkan bootstrap library
- load the library from Kotlin
- query Vulkan runtime availability from native code
- expose bootstrap diagnostics back through the existing engine plugin
- verify that Android debug and release builds still succeed

## Landed Pieces

- `android/app/src/main/cpp/CMakeLists.txt`
- `android/app/src/main/cpp/fusionx_vulkan/FusionXVulkanBootstrap.cpp`
- `android/app/src/main/cpp/fusionx_vulkan/FusionXVulkanJni.cpp`
- `android/app/src/main/kotlin/com/fusionx/fusionx_clean_ui/engine/FusionXVulkanBridge.kt`
- plugin startup payload now includes Vulkan capability data

## Next Phases

1. Phase 1:
   - create a real Vulkan renderer object
   - attach it to the app preview lifecycle
   - prove swapchain creation on the app surface
2. Phase 2:
   - wire decoded video frames into the Vulkan preview path
   - keep playback controls on the existing engine contracts
3. Phase 3:
   - move scrub preview authority into the Vulkan renderer path
   - retire the current legacy preview backend

## Important Constraint

Vulkan does not replace video decoding by itself.

The professional stack remains:

- media decode/encode via Android media APIs
- preview/compositor via Vulkan
- later, scrub proxy or intraframe preview paths for truly responsive editing

## Phase 1 Update

Phase 1 has now started:

- `FusionXVulkanRenderer` owns a real Vulkan swapchain path against the preview
  `Surface`
- `FusionXVulkanPreviewSession` attaches that renderer to the playback preview
  target before a clip is loaded
- the app can now draw a native idle frame through Vulkan on the real preview
  surface

This still does **not** move loaded-clip playback or scrub onto Vulkan yet.
Those remain on the legacy decoder path until Phase 2.
