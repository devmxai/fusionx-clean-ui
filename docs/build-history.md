# FusionX Build History

## Naming Rule

- APK naming format:
  - `Fusion X V<number> - <short-summary>.apk`
- Release shorthand format:
  - short codes only
  - example: `BF + EC + ANF`

## Releases

### V9

- APK name:
  - `Fusion X V9 - Live Scrub Overlay Preview.apk`
- Shorthand:
  - `LSO + SFE + RLS`
- Meaning:
  - `LSO` = live scrub overlay
  - `SFE` = scrub frame events
  - `RLS` = release APK build
- Notes:
  - scrub frames are now emitted from native as image bytes during finger movement
  - the editor preview shows those scrub frames in a dedicated overlay above the native texture while scrubbing is active
  - the overlay clears automatically once the final seek resolves or playback resumes
  - release APK built successfully

### V8

- APK name:
  - `Fusion X V8 - Native Scrub Surface Preview.apk`
- Shorthand:
  - `NSP + FDR + RLS`
- Meaning:
  - `NSP` = native scrub preview
  - `FDR` = direct frame rendering
  - `RLS` = release APK build
- Notes:
  - interactive scrub now uses a dedicated native preview path instead of relying on the normal decoder seek loop
  - scrub frames are extracted from the clip source and drawn directly into the existing preview surface during finger movement
  - play and final seek remain on the decoder pipeline, while scrub uses its own fast catch-up path
  - release APK built successfully

### V7

- APK name:
  - `Fusion X V7 - Playback Fix and Tighter Scrub.apk`
- Shorthand:
  - `PFX + TSC + RLS`
- Meaning:
  - `PFX` = playback regression fix
  - `TSC` = tighter scrub catch-up
  - `RLS` = release APK build
- Notes:
  - fixed the regression where play could pause almost immediately after starting
  - timeline sync jumps are no longer treated as real user scrubbing events
  - interactive scrub now bypasses the normal UI throttle and drops stale decoder targets so preview catches up to the latest finger position faster
  - release APK built successfully

### V6

- APK name:
  - `Fusion X V6 - Faster Media and Live Scrub.apk`
- Shorthand:
  - `MWU + LSC + RLS`
- Meaning:
  - `MWU` = media warmup
  - `LSC` = live scrub preview
  - `RLS` = release APK build
- Notes:
  - video and image library access now warms up in the background when media permission is already available
  - Android media queries and thumbnail loading now run off the main thread for a faster add-sheet experience
  - timeline dragging now uses a dedicated native scrub path so preview frames update during movement instead of only after release
  - the final seek still resolves precisely when the scrub gesture ends to keep the transport state accurate
  - release APK built successfully

### V5

- APK name:
  - `Fusion X V5 - Device Media Browser.apk`
- Shorthand:
  - `MDB + SEL + RLS`
- Meaning:
  - `MDB` = device media browser
  - `SEL` = select-then-import flow
  - `RLS` = release APK build
- Notes:
  - replaced the add-sheet import tile flow with a device media grid powered by Android MediaStore
  - bottom sheet now shows only Video and Image tabs with a fixed horizontal layout
  - selection now happens inside the grid and import is confirmed from the bottom action button
  - video import is active in this phase, while image browsing is visible but import remains deferred
  - release APK built successfully

### V4

- APK name:
  - `Fusion X V4 - Original UI Integration.apk`
- Shorthand:
  - `OUI + MTS + RLS`
- Meaning:
  - `OUI` = original UI integration
  - `MTS` = media tabs sheet
  - `RLS` = release APK build
- Notes:
  - merged the native single-clip playback foundation into the original editor screen
  - removed the product dependency on the temporary workspace tabs flow
  - play, seek, and trim now run from the original toolbar and timeline
  - the add flow now opens a tabbed media sheet and imports real videos into the same UI
  - release APK built successfully

### V3

- APK name:
  - `Fusion X V3 - Trim Fix and Clarity.apk`
- Shorthand:
  - `TRM + UXC + RLS`
- Meaning:
  - `TRM` = native trim playback fix
  - `UXC` = trim clarity in the playback UI
  - `RLS` = release APK build
- Notes:
  - trim now jumps playback to the selected in-point immediately
  - playback ignores decoded frames before the trim start and completes at the trim window end
  - playback UI now shows source time, clip time, first-frame readiness, and active trim guidance
  - release APK built successfully

### V2

- APK name:
  - `Fusion X V2 - Playback UI and Picker.apk`
- Shorthand:
  - `WS + PUI + PKR + RLS`
- Meaning:
  - `WS` = workspace switcher
  - `PUI` = phase 1 playback UI
  - `PKR` = Android picker bridge
  - `RLS` = release APK build
- Notes:
  - added Engine V1 workspace screen beside the original shell
  - added Flutter playback controls for load, play, pause, seek, and trim
  - added Android video picker path through `ACTION_OPEN_DOCUMENT`
  - added content-uri support in the decoder session
  - built release APK successfully

### V1

- APK name:
  - `Fusion X V1 - Native Single-Clip Foundation.apk`
- Shorthand:
  - `BF + EC + ANF`
- Meaning:
  - `BF` = baseline UI fix
  - `EC` = engine contracts v1
  - `ANF` = Android native foundation
- Notes:
  - responsive preview baseline fixed
  - Flutter bridge contracts tightened for Phase 1
  - Android native playback foundation scaffold added
  - debug APK built successfully
