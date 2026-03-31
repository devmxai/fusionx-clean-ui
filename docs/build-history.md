# FusionX Build History

## Naming Rule

- APK naming format:
  - `Fusion X V<number> - <short-summary>.apk`
- Release shorthand format:
  - short codes only
  - example: `BF + EC + ANF`

## Releases

### V40

- APK name:
  - `Fusion X V40 - Reverse Scrub Recovery Rollback.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `RSR + LFB + ESH + RLS`
- Meaning:
  - `RSR` = reverse scrub recovery
  - `LFB` = live fallback restored
  - `ESH` = end-scrub handoff
  - `RLS` = release APK build
- Notes:
  - restored live scrub fallback to the playback decoder whenever the proxy
    scrub lane is not fully ready yet, which recovers the immediate preview
    path that `V39` removed too early
  - kept eager proxy preparation and pending-target replay so the proxy lane can
    still take ownership as soon as it becomes ready
  - restored a real in-flight scrub dispatch guard for the `endScrub` handoff
    so the final drag update is not lost before the committed exact seek
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileReleaseKotlin` passed
  - `flutter build apk --release --no-version-check` passed

### V39

- APK name:
  - `Fusion X V39 - Reverse Scrub Proxy Ownership.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `RSP + PRT + FPD + RLS`
- Meaning:
  - `RSP` = reverse scrub path
  - `PRT` = proxy readiness takeover
  - `FPD` = frame-paced direct dispatch
  - `RLS` = release APK build
- Notes:
  - live scrub no longer falls back to the source playback decoder while the
    proxy lane is preparing; scrub now stays on the proxy lane ownership path
    and replays the latest pending scrub target as soon as the proxy decoder is
    ready
  - proxy preparation now starts immediately after clip preparation instead of
    waiting behind the old delayed handoff window
  - Flutter scrub dispatch no longer serializes one native `scrubTo` at a time
    or drops small reverse movements behind frame-snapped delta gates during
    active drag
  - active scrub now sends raw timeline microseconds during drag, while exact
    snap/seek is still reserved for the committed handoff path
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileReleaseKotlin` passed
  - `flutter build apk --release --no-version-check` passed

### V38

- APK name:
  - `Fusion X V38 - First Frame Recovery and Surface Ownership.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `FFR + SFO + EDR + RLS`
- Meaning:
  - `FFR` = first-frame recovery
  - `SFO` = single surface ownership
  - `EDR` = error display recovery
  - `RLS` = release APK build
- Notes:
  - removed the runtime Vulkan idle preview session from the live playback
    surface so `MediaCodec` is again the sole producer for import, first-frame
    render, playback, and exact seek
  - hardened `MediaFormat` frame-rate parsing during `loadClip`, which avoids
    decoder-session startup failures on clips whose frame-rate metadata is
    stored as an integer instead of a float
  - the preview texture now mounts as soon as a clip is selected, and the
    preview overlay shows the real engine error message if first-frame render
    fails instead of staying on a generic `Loading first frame` message
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileReleaseKotlin` passed
  - `flutter build apk --release --no-version-check` passed

### V37

- APK name:
  - `Fusion X V37 - Import Recovery and Lazy Proxy Scrub.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `IRY + LPS + TFL + RLS`
- Meaning:
  - `IRY` = import recovery
  - `LPS` = lazy proxy scrub preparation
  - `TFL` = timeline filmstrip fallback cleanup
  - `RLS` = release APK build
- Notes:
  - proxy scrub no longer starts heavy proxy preparation during import/load; it
    now waits until the first real scrub request, which is meant to keep
    `loadClip -> first frame -> play` isolated from proxy failures and startup
    contention
  - the preview canvas no longer stretches the low-resolution device poster
    under the loading text, which removes the blurry poster-with-overlay
    regression introduced in `V36`
  - timeline clips no longer seed the video filmstrip from a single imported
    poster frame, and the artificial delay before filmstrip generation was
    removed so clips do not first appear as one repeated cover and only later
    turn into real frames
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `flutter build apk --release --no-version-check` passed

### V36

- APK name:
  - `Fusion X V36 - Import Preview and Filmstrip Warmup.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `IPW + PSE + FLM + RLS`
- Meaning:
  - `IPW` = import preview warmup
  - `PSE` = poster-seeded editor preview
  - `FLM` = delayed filmstrip loading with sharper thumbnails
  - `RLS` = release APK build
- Notes:
  - scrub proxy preparation no longer starts at the exact same moment as the
    first playback load; it is deferred until the initial clip preparation has
    finished, which is meant to reduce import-time contention and help the
    first frame appear sooner on canvas
  - imported Android media thumbnails are now reused as immediate poster seeds
    for both the canvas and the timeline clip while the native preview and full
    filmstrip are still warming up
  - timeline filmstrip loading now waits briefly before generating thumbnails,
    and generated JPEG thumbnails use higher quality to reduce the blurry cover
    effect on the clip rectangle
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileReleaseKotlin` passed
  - `flutter build apk --release --no-version-check` passed

### V35

- APK name:
  - `Fusion X V35 - Frame Snapped Scrub Stability.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `FSS + FDM + LDH + RLS`
- Meaning:
  - `FSS` = frame-snapped scrub stability
  - `FDM` = frame-duration metadata
  - `LDH` = low-delta hysteresis
  - `RLS` = release APK build
- Notes:
  - source clips now publish `sourceFrameDurationUs` from Android decoder
    metadata, and the editor screen uses that to snap scrub targets to real
    frame boundaries instead of sending arbitrary sub-frame timeline times
  - Flutter scrub dispatch now ignores very small target deltas below roughly
    half a frame, which is meant to reduce visible oscillation when the finger
    moves very slowly between two adjacent frames
  - native transport duration payloads now include frame-rate-derived metadata
    so future preview/audio phases can stay aligned on real frame cadence
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:assembleRelease` passed
  - real-device validation is required to confirm whether the remaining slow
    scrub shimmer is materially reduced without making hand control feel heavy

### V34

- APK name:
  - `Fusion X V34 - Frame Paced Scrub Handoff.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `FPS + HOF + FGS + RLS`
- Meaning:
  - `FPS` = frame-paced scrub scheduling
  - `HOF` = handoff guard
  - `FGS` = Flutter gesture stabilization
  - `RLS` = release APK build
- Notes:
  - Flutter scrub dispatch is now frame-paced through `SchedulerBinding`
    instead of the previous chained loop, so Dart sends at most the latest
    scrub target per frame while Android remains the final coalescing owner
  - timeline handoff back from scrub to playback now keeps a dedicated pending
    state so engine `positionChanged` updates do not pull the playhead during
    the exact end-of-scrub resolve
  - horizontal scrub gesture lock now starts sooner for small precise drags
    and keeps the preview closer to the first meaningful finger movement
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:assembleRelease` passed
  - real-device validation is required to judge whether the remaining slight
    delay now feels materially smaller and whether scrub release looks cleaner
    on both short and long clips

### V33

- APK name:
  - `Fusion X V33 - Proxy Handoff Stabilization.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `PHS + NFB + ESH + RLS`
- Meaning:
  - `PHS` = proxy handoff stabilization
  - `NFB` = no fallback during proxy build
  - `ESH` = end-scrub handoff cleanup
  - `RLS` = release APK build
- Notes:
  - `FusionXScrubSession` now keeps the latest scrub target while the proxy is
    still preparing and dispatches it as soon as the proxy session becomes
    ready, instead of immediately falling back to exact-source scrub on the
    playback decoder
  - proxy decoder sessions now use scrub-specific continuation settings so the
    proxy lane can re-prepare sooner and render progressively over a wider
    target window than the source playback decoder
  - Flutter no longer sends an extra final `scrubTo` before `endScrub`; the
    final exact target is now committed directly through `endScrub`, which
    should reduce the extra motion after lifting the finger
  - the timeline gesture lock threshold was reduced so horizontal scrub starts
    more readily during precise hand movements
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:assembleRelease` passed
  - real-device validation is required to judge whether the remaining slight
    latency and end-of-scrub drift were reduced materially on short and long
    clips

### V32

- APK name:
  - `Fusion X V32 - Duration Aware Proxy Preview.apk`
- Milestone label:
  - `FusionX-Beta2`
- Shorthand:
  - `DAP + DIF + STM + RLS`
- Meaning:
  - `DAP` = duration-aware proxy mapping
  - `DIF` = dense iframe proxy
  - `STM` = source-to-media time mapping
  - `RLS` = release APK build
- Notes:
  - added `FusionXMediaTimeMapper` so proxy scrub no longer assumes proxy
    timestamps exactly match source timestamps; proxy playback can now map
    between source time and proxy media time using measured clip durations
  - `FusionXProxyConformer` now generates a more scrub-friendly proxy profile:
    lower preview resolution, tighter H.264 keyframe cadence, and a new proxy
    schema version so older softer proxies are not reused
  - proxy metadata now stores both source and proxy durations and passes them
    into the native scrub session
  - proxy decoder sessions no longer resize the shared preview surface down to
    proxy resolution, which should reduce unnecessary quality collapse while
    scrubbing
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileDebugKotlin` passed
  - release APK build verification is included with this version
  - real-device validation is still required to judge whether short-clip tail
    lag and end-of-clip proportional scrub behavior improved materially
  - this version continues the post-`Beta 1` preview-pipeline hardening phase
    and is focused on scrub correctness rather than adding editor features

### V31

- APK name:
  - `Fusion X V31 - Proxy Scrub Foundation.apk`
- Milestone label:
  - `Beta 1`
- Shorthand:
  - `PSF + M3H + SDK21 + RLS`
- Meaning:
  - `PSF` = proxy scrub foundation
  - `M3H` = Media3 helper conformer
  - `SDK21` = Android minSdk raised to 21
  - `RLS` = release APK build
- Notes:
  - added `FusionXProxyConformer` to generate a low-resolution H.264 proxy clip
    in app cache for scrub, instead of relying only on exact-source decode
    from the original compressed clip
  - rewired `FusionXScrubSession` to prepare a dedicated native proxy scrub
    lane backed by `FusionXDecoderSession`, while source playback and exact
    end-of-scrub resolve stay on the original playback session
  - `FusionXEngineController` now routes `scrubTo` to the proxy lane when it
    is ready and falls back to the old decoder scrub path only if the proxy is
    not prepared yet
  - raised Android `minSdkVersion` to 21 because the current helper conformer
    stack requires it in this project
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - `./gradlew --no-daemon app:compileDebugKotlin` passed
  - `./gradlew --no-daemon app:assembleRelease --stacktrace` passed
  - real-device validation is still required to judge whether the new proxy
    scrub lane materially improves live scrub smoothness and proportionality
    under the finger
  - this version is now treated as the first good beta baseline for continuing
    the engine roadmap

### V30

- APK name:
  - `Fusion X V30 - Anchored Scrub Stability.apk`
- Shorthand:
  - `ASB + GOP + RLS`
- Meaning:
  - `ASB` = anchored scrub behavior
  - `GOP` = wider GOP continuation handling
  - `RLS` = release APK build
- Notes:
  - timeline scrubbing now uses an anchored pointer position instead of
    accumulating per-move deltas, which makes the scrub path steadier under the
    finger
  - the decoder scrub continuation window was widened again so scrubbing can
    continue farther through the same compressed segment instead of collapsing
    near the early keyframe/GOP boundary
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - release APK built successfully via `./gradlew --no-daemon app:assembleRelease`

### V29

- APK name:
  - `Fusion X V29 - Target Locked Scrub Tracking.apk`
- Shorthand:
  - `TLS + NAR + RLS`
- Meaning:
  - `TLS` = target-locked scrub
  - `NAR` = narrower active render window
  - `RLS` = release APK build
- Notes:
  - the active decoder scrub path now renders progressive frames only when they
    are close to the current target instead of showing older chase frames from
    farther back in the GOP
  - the forward continuation window was reduced so larger scrubs re-prepare
    sooner instead of dragging stale decoder state too far forward
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - release APK built successfully via `./gradlew --no-daemon app:assembleRelease`

### V28

- APK name:
  - `Fusion X V28 - Flutter Texture Ownership Fix.apk`
- Shorthand:
  - `TEX + RGR + RLS`
- Meaning:
  - `TEX` = texture ownership restored
  - `RGR` = render regression rollback
  - `RLS` = release APK build
- Notes:
  - removed the custom `SurfaceTexture` frame listener that was interfering with
    Flutter texture presentation and causing black preview playback
  - restored Flutter ownership of the preview texture while keeping the newer
    decoder scrub gating logic in place
  - `flutter analyze --no-version-check` passed
  - `flutter test --no-version-check` passed
  - release APK built successfully via `./gradlew --no-daemon app:assembleRelease`

### V27

- APK name:
  - `Fusion X V27 - Surface Sync Scrub Pacing.apk`
- Shorthand:
  - `SFS + TGP + RLS`
- Meaning:
  - `SFS` = surface frame synchronization
  - `TGP` = target-gated progressive scrub
  - `RLS` = release APK build
- Notes:
  - the decoder scrub path now waits for the preview surface to acknowledge a
    new frame before racing ahead to the next progressive output
  - progressive scrub rendering no longer starts immediately from the GOP sync
    frame after a decoder re-prepare; it stays focused near the requested
    target window instead
  - scrub fallback near end-of-stream now lands on the last decoded frame
    instead of immediately re-preparing the decoder again
  - `flutter analyze` passed
  - `flutter test --no-version-check` passed
  - release APK built successfully via `./gradlew --no-daemon app:assembleRelease`

### V26

- APK name:
  - `Fusion X V26 - Progressive Decoder Scrub.apk`
- Shorthand:
  - `PDS + CFW + RLS`
- Meaning:
  - `PDS` = progressive decoder scrub
  - `CFW` = continuation forward window
  - `RLS` = release APK build
- Notes:
  - the decoder scrub path no longer waits only for the final target frame
    before showing movement; it can now render progressive intermediate frames
    while chasing the scrub target on the same preview surface
  - increased the forward continuation window from `0.75s` to `3.0s` so
    longer forward drags do not collapse into constant `seek + flush` as
    quickly as before
  - this specifically targets the behavior where the first small part of the
    video scrubbed smoothly but movement froze after roughly the first second
  - `flutter analyze` passed
  - `flutter test` passed
  - `flutter build apk --release` passed
  - real-device validation is required to confirm whether scrub now keeps
    moving past the first second instead of freezing after the initial window

### V25

- APK name:
  - `Fusion X V25 - Phase 2 Single Surface Foundation.apk`
- Shorthand:
  - `P2S + SSD + RLS`
- Meaning:
  - `P2S` = phase 2 start
  - `SSD` = single-surface decoder
  - `RLS` = release APK build
- Notes:
  - retired the active dual-surface scrub path from `FusionXEngineController`
    so scrubbing now stays on the same preview surface instead of switching to
    a separate scrub texture
  - active scrub commands now route through the decoder session's scrub path,
    which becomes the temporary Phase 2 single-surface foundation while the
    proxy scrub decoder is built next
  - `FusionXPreviewCoordinator` is now effectively single-surface in the active
    runtime, which removes preview texture switching from the visible scrub
    path
  - added decoder-side `stopAndDrainScrub()` so playback handoff can flush the
    decoder scrub queue before `play`, `seek`, and `endScrub`
  - `flutter analyze` passed
  - `flutter test` passed
  - `flutter build apk --release` passed
  - real-device validation is required to compare this single-surface
    foundation against the broken retriever/scrub-texture path it replaces

### V24

- APK name:
  - `Fusion X V24 - Dense Bitmap Scrub Cache.apk`
- Shorthand:
  - `DBC + LSW + RLS`
- Meaning:
  - `DBC` = dense bitmap cache
  - `LSW` = local scrub window
  - `RLS` = release APK build
- Notes:
  - replaced the scrub session's JPEG byte cache with an in-memory bitmap cache
    so scrub no longer compresses and decodes preview frames during movement
  - scrub cache density is now local and much tighter around the finger target
    instead of using a coarser cache spread across the whole clip
  - priority warmup now follows the active scrub neighborhood rather than a
    broad sequential sweep, which should make nearby forward/backward movement
    more responsive
  - scrub proxy frames are normalized once and retained in a lighter in-memory
    config instead of being round-tripped through JPEG
  - `flutter analyze` passed
  - `flutter test` passed
  - `flutter build apk --release` passed
  - real-device validation is required to measure whether preview motion now
    feels materially closer to proportional jog/shuttle behavior

### V23

- APK name:
  - `Fusion X V23 - Explicit Scrub Commit Handoff.apk`
- Shorthand:
  - `SCH + ECS + RLS`
- Meaning:
  - `SCH` = scrub commit handoff
  - `ECS` = explicit commit source
  - `RLS` = release APK build
- Notes:
  - `endScrub` now commits the exact final timeline time coming from Flutter
    instead of relying on whatever time the native transport last held
  - the Android engine now tracks the latest requested scrub time and clears it
    explicitly when control returns to playback
  - this targets the case where scrub work is drained or cancelled before the
    last requested position is fully reflected in transport state, which can
    show up as jump-back or unstable final positioning
  - `flutter analyze` passed
  - `flutter test` passed
  - `flutter build apk --release` passed
  - real-device validation is required to confirm whether the final scrub
    commit and timeline stability are now materially better

### V22

- APK name:
  - `Fusion X V22 - Timeline Ownership Stabilization.apk`
- Shorthand:
  - `TOS + SHB + RLS`
- Meaning:
  - `TOS` = timeline ownership stabilization
  - `SHB` = scrub handoff barrier
  - `RLS` = release APK build
- Notes:
  - moved the timeline panel off screen rebuild timing and onto the same live
    timeline time notifier used by the preview HUD
  - local drag time now remains the authoritative visual time until scrub
    commit finishes, instead of falling back early to a stale external time
  - added a scrub-settle guard in the Flutter screen so delayed engine position
    events do not yank the timeline backward during the release/commit window
  - added `stopAndDrain()` to the Android scrub session and now stop scrub work
    before handing control back to playback for `endScrub`, `play`, `seek`,
    and `trim`
  - `flutter analyze` passed
  - `flutter test` passed
  - `flutter build apk --release` completed and produced a new release APK
  - real-device validation is required to confirm whether the unstable
    timeline/time snap-back is resolved on hardware

### V21

- APK name:
  - `Fusion X V21 - Vulkan Preview Session.apk`
- Shorthand:
  - `VKS + SUR + RLS`
- Meaning:
  - `VKS` = Vulkan preview session
  - `SUR` = real surface attachment
  - `RLS` = release APK build
- Notes:
  - added a real Vulkan renderer with swapchain creation against the app preview
    `Surface`
  - added `FusionXVulkanPreviewSession` so the engine can attach Vulkan to the
    playback preview target before a clip is loaded
  - Vulkan is no longer diagnostics-only; it now renders an actual idle frame
    into the product preview surface
  - loaded clip playback and scrub still remain on the legacy decoder path in
    this phase
  - `flutter analyze` passed
  - `flutter test` passed
  - `./gradlew --no-daemon app:assembleDebug` passed
  - `./gradlew --no-daemon app:assembleRelease` passed

### V20

- APK name:
  - `Fusion X V20 - Vulkan Phase 0 Bootstrap.apk`
- Shorthand:
  - `VK0 + JNI + RLS`
- Meaning:
  - `VK0` = Vulkan Phase 0
  - `JNI` = native bridge bootstrap
  - `RLS` = release APK build
- Notes:
  - added Android `externalNativeBuild` and a native C++ Vulkan bootstrap
    library
  - the Android engine plugin now queries Vulkan runtime capabilities from
    native code on startup
  - pinned the Android app to the locally available NDK `27.1.12297006` so the
    new native pipeline builds consistently on this machine
  - the current decoder preview backend remains active temporarily, but is now
    officially treated as the legacy path while Vulkan becomes the target
    renderer
  - `flutter analyze` passed
  - `flutter test` passed
  - `./gradlew --no-daemon app:assembleDebug` passed
  - `./gradlew --no-daemon app:assembleRelease` passed

### V19

- APK name:
  - `Fusion X V19 - Scrub Proxy Architecture.apk`
- Shorthand:
  - `SPA + PWC + RLS`
- Meaning:
  - `SPA` = scrub proxy architecture
  - `PWC` = proxy warm cache
  - `RLS` = release APK build
- Notes:
  - kept the dedicated playback/scrub split from V17, but replaced the visible
    live scrub implementation with a proxy-backed scrub session
  - scrub now prewarms quantized preview buckets around the current source
    position and keeps extending that cache in the background
  - drag preview resolves the nearest ready proxy frame from native cache
    instead of trying to build a fresh visible frame on every move
  - playback and final exact resolve remain on the playback decoder session,
    which keeps scrub preview and exact playback responsibilities separate
  - release APK built successfully
  - exact device validation is required to confirm whether this closes the
    remaining lag during bidirectional scrub on hardware

### V18

- APK name:
  - `Fusion X V18 - Scrub Target Regression Fix.apk`
- Shorthand:
  - `STR + DPG + RLS`
- Meaning:
  - `STR` = scrub target regression
  - `DPG` = delayed preview gating
  - `RLS` = release APK build
- Notes:
  - fixed the dedicated scrub regression where scrub preview could switch to a separate target before the first scrub frame was ready
  - scrub preview now keeps playback visible until a real scrub frame has been rendered
  - scrub target sizing now follows the clip display geometry instead of staying on the initial default buffer
  - added rotation-aware scrub bitmap normalization to reduce the letterboxing/smaller-frame issue seen in V17
  - release APK built successfully
  - device validation is required to measure whether the V17 regression is resolved and whether scrub latency improved materially

### V17

- APK name:
  - `Fusion X V17 - Dedicated Scrub Architecture.apk`
- Shorthand:
  - `DSA + SPC + RLS`
- Meaning:
  - `DSA` = dedicated scrub architecture
  - `SPC` = split preview coordination
  - `RLS` = release APK build
- Notes:
  - landed the first split between playback preview and scrub preview inside the Android engine
  - added a native preview coordinator with separate playback and scrub render targets
  - added explicit `beginScrub` and `endScrub` commands so scrub lifecycle is no longer inferred only from repeated `scrubTo`
  - scrub preview now runs through a dedicated scrub session instead of sharing the playback-visible preview lane directly
  - release APK built successfully
  - device validation is required to measure whether the new architecture improves bidirectional scrub behavior materially

### V16

- APK name:
  - `Fusion X V16 - Bidirectional Scrub Target Fix.apk`
- Shorthand:
  - `BST + SCC + RLS`
- Meaning:
  - `BST` = bidirectional scrub targets
  - `SCC` = scrub command coalescing
  - `RLS` = release APK build
- Notes:
  - removed the backward scrub tolerance in the decoder scrub path so reversing direction no longer reuses a later already-decoded frame during tiny backward moves
  - the Flutter screen now coalesces `scrubTo` commands and keeps only the newest pending scrub target instead of flooding the Android main thread with stale method-channel calls
  - `play` now waits for pending scrub dispatches to drain before sending the playback command, which should reduce lag caused by old scrub messages still queued ahead of `play`
  - release APK built successfully
  - device validation is required to measure how much this improves forward/backward touch tracking and play-start response on hardware

### V15

- APK name:
  - `Fusion X V15 - Continuous Decoder Scrub.apk`
- Shorthand:
  - `CDS + DCR + RLS`
- Meaning:
  - `CDS` = continuous decoder scrub
  - `DCR` = decoder continuation resume
  - `RLS` = release APK build
- Notes:
  - scrub no longer treats every move as an isolated exact seek; it now keeps decoding forward within the same stream when the finger movement stays within a continuation window
  - stale scrub targets can now trigger a reprepare only when the movement goes backward or jumps far enough forward, instead of forcing a full seek/flush for every small move
  - decoder continuation state is now reused so `play` can start from the currently rendered frame without always rebuilding decoder state first
  - release APK built successfully
  - device validation is required to measure whether scrub latency and play-start latency improved materially on hardware

### V14

- APK name:
  - `Fusion X V14 - Unified Decoder Scrub Path.apk`
- Shorthand:
  - `UDS + UTX + RLS`
- Meaning:
  - `UDS` = unified decoder scrub
  - `UTX` = unified texture path
  - `RLS` = release APK build
- Notes:
  - removed the `MediaMetadataRetriever -> Bitmap -> lockCanvas()` scrub path from the active engine
  - live scrub now reuses the native decoder and the same preview texture instead of a separate CPU-rendered preview path
  - the Flutter scrub overlay/cache path was removed so the preview stays on one visual pipeline only
  - scrub requests now coalesce on the decoder executor and update native transport state without pushing a Flutter event on every scrub frame
  - decoder configuration now opts into Android low-latency mode where supported
  - release APK built successfully
  - device validation is required to confirm whether this closes the real-time scrub issue on hardware

### V13

- APK name:
  - `Fusion X V13 - Isolated Scrub Preview Updates.apk`
- Shorthand:
  - `ISP + TDP + RLS`
- Meaning:
  - `ISP` = isolated scrub preview
  - `TDP` = timeline direct path
  - `RLS` = release APK build
- Notes:
  - scrub preview updates now bypass full-screen `setState` and update through dedicated notifiers
  - the preview overlay is no longer gated by parent widget rebuilds during drag
  - timeline scrub dispatch now takes the direct path before epsilon filtering so tiny finger moves are not dropped while scrubbing
  - the timeline clock display now follows internal scrub time during active drag
  - release APK built successfully
  - device validation is required to confirm whether the preview now tracks the finger in real time

### V12

- APK name:
  - `Fusion X V12 - Playback Clock and Scrub Warmup.apk`
- Shorthand:
  - `PCK + SWP + RLS`
- Meaning:
  - `PCK` = playback clock
  - `SWP` = scrub warmup priority
  - `RLS` = release APK build
- Notes:
  - fixed the playback clock so the transport anchor starts from the first decoded output frame instead of assuming zero startup latency
  - this removes the initial burst/catch-up behavior that could make the first moments of playback look too fast
  - scrub cache generation now starts earlier and can complete even while playback is active
  - Android media warmup now runs on background-priority worker threads to reduce contention with UI and playback
  - if scrub cache finishes while the finger is still down, the preview overlay now appears immediately without waiting for another gesture step
  - release APK built successfully
  - device validation is still required for the live scrub issue

### V11

- APK name:
  - `Fusion X V11 - Proxy Scrub Cache Overlay.apk`
- Shorthand:
  - `PSC + ESR + RLS`
- Meaning:
  - `PSC` = proxy scrub cache
  - `ESR` = exact seek on release
  - `RLS` = release APK build
- Notes:
  - live scrub no longer depends on native per-drag frame extraction
  - timeline dragging now uses a prebuilt preview cache inside Flutter for immediate proxy-frame display
  - exact native `seekTo` is committed only after the user lifts the finger
  - delayed native scrub rendering path was removed from the active gesture flow
  - scrub cache warmup is delayed and canceled before playback start to reduce first-play lag
  - release APK built successfully
  - device validation is required to confirm whether live preview now tracks the finger directly

### V10

- APK name:
  - `Fusion X V10 - Native Scrub Cache Surface.apk`
- Shorthand:
  - `NSC + NTS + RLS`
- Meaning:
  - `NSC` = native scrub cache
  - `NTS` = native texture surface
  - `RLS` = release APK build
- Notes:
  - removed the live scrub overlay path that depended on JPEG bytes and `Image.memory` in Flutter
  - scrub preview now renders directly into the existing native texture surface during drag
  - added a low-resolution native scrub cache that warms in the background after clip load
  - when the cache is not ready yet, scrub still falls back to direct native frame extraction on the same surface path
  - release APK built successfully
  - device validation is still required to confirm that finger movement and preview are now visually synchronized

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
