# Mac hand control

The iPhone TrueDepth Probe app sends RGB hand observations to this native Mac test window. The Mac advertises `_rayneohand._tcp` over Bonjour. The phone discovers it automatically. Allow Local Network access on both devices.

## Run

```sh
./HandControl/build.sh
open HandControl/build/HandControl.app
```

On the iPhone, open TrueDepth Probe and tap **Start RGB → Mac**. Hold one hand about 20–50 cm above the front camera. Move your open hand to aim at a target, then pinch and release to click. Press R in the Mac window to reset counters. Stop on the phone ends capture and disconnects the sender. Closing the Mac window quits the receiver. The probe now starts idle when opened normally; `--mac-control` launches directly into RGB streaming for device testing.

The app starts in test mode. Its six tiles count clicks, and the footer counts clicks between tiles. The sender transmits normalized middle-finger-base position, tracking validity, pinch state, sequence number, and processing time. It transmits no camera images. TCP carries newline-delimited JSON. One sensor connects at a time. Only one packet can await acknowledgement; newer samples are skipped until it is acknowledged, and a 400 ms acknowledgement timeout reconnects the sender. This bounds queued gesture data during network stalls.

The middle finger base supplies hand position. **Relative · mouse-style** is now the default movement mode. Ordinary movement uses a fixed gain, capped at the sensitivity setting. Very slow fine adjustments use 30% of that gain, with a smooth transition up to normal speed. Faster sweeps stay at the normal gain ceiling. A One Euro filter adapts smoothing to movement speed. A soft dead zone of 0.006 camera-image units suppresses small excursions around the current hand anchor. These are provisional parameters, not measurements of the user's tremor or breathing.

Lower the hand out of view, reposition it comfortably, and bring it back to continue from the cursor's current location. Tracking reacquisition resets the hand anchor without warping the cursor. In system mode the current OS cursor location is used, so repositioning with the physical mouse also works. Palm or pinch-tracking loss during a drag releases the mouse button; reposition the hand between drags.

**Direct · position-based** retains absolute camera-to-screen mapping, with the adaptive filter. In direct mode 1.5× maps the central 40% of the image to the display. In relative mode sensitivity instead scales the speed-dependent movement gain. The existing user-selected sensitivity is preserved. Both settings persist across launches, and changes release pending input.

The same movement processing feeds test and system modes. Pinch onset freezes aim, two closed samples confirm press, and two open samples confirm release. The system-pointer code handles held-pinches for dragging. Releasing a pinch resets the relative movement origin to avoid a jump. Lost tracking requires a fresh open hand to re-arm.

Sources behind the motion design are [Apple's pointer acceleration description](https://support.apple.com/en-ie/guide/mac-help/mh29222/27/mac/27), [Ultraleap's cursor stabilization settings](https://docs.ultraleap.com/TouchFree/touchfree-user-manual/interaction-settings.html), and [the One Euro filter authors' reference](https://github.com/casiez/OneEuroFilter).

The app shows received updates per second and phone processing time. These are not an end-to-end latency measurement. Logs are written to `/private/tmp/rayneo-hand-receiver.log`; the iPhone also logs in its Documents directory.

## System cursor mode

Click **Accessibility settings** and enable **Hand Control** in macOS Accessibility. Then click **Enable system cursor**. The mode controls the display containing the Hand Control window at activation, using the selected relative or direct movement mode. Move the app to another display before enabling to choose that display.

- Open hand moves the system pointer.
- Pinch and release performs a left click.
- Hold the pinch for 0.3 seconds, then move to drag. Release drops the item. The movement is relative to the pinch origin to avoid an initial jump.
- **Control–Option–Command–P** pauses system control. The button and the menu-bar **Hand: LIVE** menu also provide pause. The shortcut registration must succeed before the mode can activate.
- Tracking loss or a stale stream releases any held mouse button and requires a fresh open hand. Releasing an already-posted mouse button can complete an action in the target app.
- Phone Stop or disconnect, Mac sleep, display changes, and app exit release held input. Disconnect and sleep also turn off system mode. Enable it again after restarting the phone stream.
- Startup always uses test mode. Pointer sensitivity is shared by both modes.

The public preview uses an ad-hoc signature by default. Set `HAND_CONTROL_SIGNING_IDENTITY` to your own stable signing identity to preserve macOS Accessibility authorization across rebuilds. Without stable signing, macOS may require authorization again.

## Scrolling

Make a relaxed fist, keeping the whole hand in view. Hold this pose briefly, then move the hand vertically. Moving the hand upward moves page content upward; moving down brings earlier content back. Open the hand to resume pointing.

**Scroll practice** opens a native scrollable document in the test window. In system mode, aim the pointer over the desired scrollable area before forming the pose. The pointer stays fixed during scrolling. A click or drag already in progress takes priority until released.

The phone checks wrist-to-tip / wrist-to-PIP curl ratios from whichever fingers are confidently visible. Entry requires at least two ratios below 1.08 and none above 1.18; sustaining requires one below 1.18 and none above 1.30. No specific ring/little joint is required, and missing joints are not counted as curled. Thumb position is unrestricted. These thresholds are provisional.

To distinguish a fist from a pinch, clicking requires a visibly extended non-index finger (ratio >1.25) and no visibly curled non-index fingers (<1.08). Pinch with the other fingers open. Unknown or ambiguous poses cannot arm clicks. An already held drag is released when pinch validity is lost, and that release may complete an action in the target app.

Three consecutive pose samples activate scrolling. Missing pose samples immediately stop wheel output and reset the movement anchor; a 0.35-second grace period keeps the cursor parked before returning to pointing. Reacquisition reanchors without a scroll jump. Full palm loss, timeout, pause, and disconnect reset immediately.

Vertical motion uses an adaptive filter, a 0.003-camera-unit dead zone, and 2250 scroll points per camera-unit movement, capped at 90 points per update. Fractional points accumulate. Optional `scrollPose` packets preserve compatibility with previous senders.

## Verification

`build.sh` runs the gesture-state self-test, covering an initially closed hand, debounce, one click per release, tracking-loss cancellation, and re-arming. A local TCP test also produced exactly one tile click and canceled a second press on tracking loss. Live iPhone-to-Mac delivery was verified at approximately 15 updates per second, with about 15–23 ms of processing per analyzed frame in the initial run. The subsequent live iPhone session registered pinch-release clicks on all six targets. Private session logs are not distributed. Quantitative accuracy and end-to-end latency remain unmeasured.

The system-pointer self-test uses an injected event sink and checks mouse down/up pairing, drag movement, stable release, cancellation, and display coordinate mapping. Accessibility permission was granted and the running app successfully entered system cursor mode. The user confirmed the live system-control trial worked and specifically reported dragging a window. System presses/releases and a subsequent pause were observed in the log, and the paused UI was verified. The exact pause mechanism was not separately confirmed.

The adaptive-motion self-test checks zero cursor motion for a bounded synthetic oscillation, precision slowdown and a fixed ceiling for ordinary and fast movement, jump-free reacquisition, and direct mapping. These synthetic results establish implementation behavior, not comfort or real-world accuracy. The updated app was built, signed, and visually checked in relative test mode at the preserved user setting (~1.3). User comfort validation remains pending.

The iPhone probe supports portrait and both landscape directions. Preview and tracking coordinates rotate together. Landscape testing uses the camera’s wider dimension for side-to-side hand motion. Regression checks verify backward-compatible decoding and palm-only movement without click arming.

Scroll-state tests cover entry debounce, both directions, no movement during pose loss, exit, reset, and basic pose classification. The native practice document was visually verified. The initial two-finger pose registered in live logs, but the user reported losing it as soon as they moved. The user found thumbs-up awkward and requested a fist. Fist classification, pinch disambiguation, receiver click suppression, and gap-recovery checks pass; the user confirmed fist scrolling feels good and requested more speed. Gain and the per-update cap were increased by 50%. The user subsequently confirmed the higher scroll speed works well. System scrolling still needs explicit live validation.
