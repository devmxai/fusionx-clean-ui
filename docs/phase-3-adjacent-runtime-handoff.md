# Phase 3 - Adjacent Runtime Handoff

`Phase 3` is the first runtime phase that consumes engine-owned project-time
authority to continue playback from one clip into the next.

## Delivered In This Phase

- project-time aware transport offset
- engine-owned active clip runtime request
- runtime activation for resolved clip windows
- adjacent clip continuation on end-of-clip completion
- active clip change event from engine to Flutter UI
- Flutter timeline anchoring now preserves global project time when clip-local
  duration and trim events arrive from a newly activated clip
- scrub session reload now follows the active clip path instead of remaining
  attached to the first imported clip
- decoder playback completion now finalizes through one shared end-of-clip path,
  including the silent `INFO_TRY_AGAIN_LATER` exhaustion case that previously
  stopped at the seam without invoking handoff
- end-of-scrub now resolves the target clip by project time instead of seeking
  inside whichever clip was active before the scrub started
- playback handoff now continues inline inside the active decoder session rather
  than round-tripping through a delayed controller reactivation
- same-clip scrub release no longer re-emits trim reset events; this preserves
  the released playhead position instead of snapping the preview back to zero
- duration and trim events now carry global `timelineTimeUs`, so cross-clip
  scrubbing no longer has to guess the target timeline position from clip-local
  offsets alone
- playback render target resizing is now held stable across clip changes, which
  reduces black flicker during adjacent hard-cut handoff
- reverse scrub now uses a small preroll window to reduce the harsh reprepare
  feel when dragging back across frames
- Flutter selection state is now separated from engine-active runtime state, so
  playback and handoff can update the active clip without stealing timeline
  selection from the user
- clip-window activation no longer re-announces a fresh clip load from source
  zero before the target trim window is applied, which removes one of the main
  causes of the playhead flashing to clip start during cross-clip scrub release
- cross-clip scrub now resolves and activates the target clip as soon as the
  playhead crosses the seam, instead of waiting for scrub release before moving
  runtime ownership to the adjacent clip
- the preview now keeps showing the previously rendered clip aspect until the
  first frame of the new active clip actually arrives, preventing the last frame
  of clip 1 from being reshaped into clip 2's aspect ratio during handoff
- timeline clip selection is now user-owned only; playback and handoff no
  longer auto-select clips or toggle tool availability just because runtime
  active ownership moved to the adjacent clip
- preview frame chrome is reduced so the visible canvas is closer to the actual
  project area instead of looking like a heavily inset rounded card
- scrub proxy decoder sessions no longer publish global `playing/paused/error`
  state into the shared transport, so seam-area proxy failures cannot flip the
  main playback session into `error` or override its transport state
- timeline clip gaps are now rendered as truly contiguous for normal adjacent
  clips, so the visible timeline geometry no longer inserts a fake seam region
  that the playhead can enter while time mapping still assumes continuous media
- Flutter seam anchoring now matches engine half-open interval semantics
  (`[start, end)`), removing one exact-boundary mismatch where the UI still
  treated the previous clip as active while the engine had already resolved the
  next clip
- multi-clip runtime metadata events no longer resync the whole project model
  back into the engine during playback handoff, which avoids moving the seam
  under the playhead while adjacent clip activation is already in progress
- controller command routing now compares project-time requests against the clip
  path actually loaded inside the active decoder session, not just the
  optimistic active-request state that gets announced earlier in handoff
- exact seam scrub/seek positions are now normalized away from the raw clip
  boundary, so the playhead does not remain parked on the ambiguous shared edge
  between clip 1 end and clip 2 start
- Flutter play toggles now wait for scrub handoff completion as well as scrub
  settling before sending a fresh `play` command into the runtime
- timeline offset handoff is now applied from inside the decoder activation
  task itself, reducing the transient `new offset + old clip window` mismatch
  during cross-clip activation
- controller-side active clip ownership is now committed only after the decoder
  confirms clip-window activation, instead of being announced optimistically
  before the target clip is actually ready
- Flutter now keeps timeline scrub handoff pending until a real activation
  acknowledgment returns from runtime events, which reduces the first-play race
  after cross-clip scrub and handoff
- seam-exact split resolution now uses the same normalized timeline position as
  scrub/playback, so the seam no longer looks like a tool-dead zone just
  because the playhead sits on the shared boundary
- preview asset switching is now applied immediately when the decoder-confirmed
  `activeClipChanged` event arrives; this avoids waiting for a first-frame event
  that may already have fired earlier in the activation path, which previously
  left the preview using the wrong clip aspect at the seam

## What This Phase Solves

- the engine can continue from clip 1 into clip 2 using project-time authority
- timeline time no longer resets back to clip-local zero when the active clip
  changes
- the UI can follow active clip ownership from engine events instead of
  guessing from local state
- playhead clamping now respects full multi-clip project duration instead of
  collapsing back to the current clip trim window
- timeline selection no longer has to bounce between clip 1 and clip 2 just
  because runtime ownership changes during playback or scrub
- cross-clip handoff and end-of-scrub no longer need to emit an interim
  `duration/position` reset from the beginning of the newly loaded clip before
  the final target frame is rendered
- seam-area scrubbing can now switch runtime ownership at the moment the scrub
  crosses into the adjacent clip, which improves preview correctness around the
  boundary instead of freezing on the previous clip until release
- preview aspect changes no longer race ahead of the real rendered frame during
  adjacent clip activation, which reduces the visible "size flash" at the seam
- toolbar selection affordances now stay tied to manual clip selection instead
  of flickering between clips during playback near the seam
- the timeline seam no longer contains a UI-only empty strip that can make the
  playhead feel like it is sitting in a non-media region between clip 1 and
  clip 2
- scrub proxy failures no longer poison the shared playback state, which should
  prevent seam crossing from incorrectly degrading into a global `error` state
- play/seek/scrub/end-scrub can no longer assume the decoder session has
  already switched clips just because the controller announced a new active clip
  request; this reduces the "first play tap does nothing" behavior after
  cross-clip scrub or seam handoff
- exact seam positions no longer behave like a dead zone for scrub/playback
  dispatch, which should reduce the apparent jump to `0.00s` and the feeling of
  a hidden gap between adjacent clips
- leaving scrub now clears any pending proxy replay before playback resumes, so
  a late scrub-session completion cannot re-apply an old seam target after the
  user has already pressed play
- controller/UI state can no longer fully switch to the target clip before the
  decoder activation itself completes, which should reduce the unstable first
  `play` tap after moving back from clip 2 to clip 1
- end-of-scrub no longer clears its handoff-pending guard immediately after the
  bridge call returns; it now waits for runtime acknowledgment before treating
  the scrub release as complete
- the preview should no longer remain on clip 1's display asset while clip 2 is
  already rendering (or the reverse), which reduces the severe aspect mismatch
  introduced when decoder-confirmed activation landed after first-frame events

## Phase 3 Stability Notes

- `V103` and `V104` proved that delaying active clip ownership until
  decoder-confirmed activation can regress seam stability when the rest of the
  runtime still behaves like a single-session reload path.
- The immediate rollback path returns clip ownership publication and scrub
  completion to the more stable `V102` behavior while keeping the rest of the
  Phase 3 project-time authority work intact.
- This rollback is intentional inside `Phase 3`: when a stability pass makes
  seam playback materially worse, we restore the last stable ownership model
  first, then continue deeper runtime work from that safer baseline.

## Phase 3 Adjacent Prewarm

- The playback runtime now keeps an adjacent decoder session preloaded with the
  next clip path whenever the active project request has a resolvable next
  clip.
- At end-of-clip handoff, the engine first tries to promote this prewarmed
  session instead of forcing the current playback session to fully reload the
  next clip on the seam itself.
- If the adjacent prewarm is unavailable or stale, runtime falls back to the
  existing internal continuation path, so Phase 3 keeps a safe fallback rather
  than relying on preload always being ready.
- This is the first Phase 3 change that aims directly at reducing seam lag by
  shrinking the work performed exactly at clip 1 -> clip 2 handoff.
- `V106` showed that this adjacent-prewarm experiment is not stable enough yet:
  on-device it regressed seam completion and cross-clip scrub behavior, so the
  experiment is rolled back in `V107` while Phase 3 continues from the more
  stable `V105`-style continuation path.
- `V108` freezes multi-clip runtime metadata on the Flutter side: seam-time
  `durationResolved` and `trimChanged` events no longer rewrite project
  timeline state or reset scrub dispatch bookkeeping while more than one clip
  exists, because those late metadata events were making the seam look like a
  temporary empty zone even though engine project time remained continuous.
- `V109` proved too optimistic for the current runtime: queueing `Play`
  through scrub completion made playback worse on device, so that experiment is
  rolled back in the next stability pass and Phase 3 returns to the earlier
  direct toggle path while play responsiveness is addressed deeper in runtime.
- `Beta 8` intentionally keeps the more stable `V108` / `V110` runtime path as
  the mainline while Phase 3 continues, instead of promoting the unfinished
  `V111` scrub-play experiment into the source snapshot.

## What This Phase Still Does Not Solve

- truly seamless adjacent playback using a prewarmed dual-decoder runtime
- decoder pool prewarm on a second live decoder surface path
- multi-clip scrub runtime across boundaries
- Vulkan compositor transitions
- multi-layer composition
