# PalmRay

**Your iPhone camera. Your Mac cursor.**

Hand input for the screen on your desk—or the screen in your AR / XR glasses. PalmRay is the working project name; the native prototype apps retain their original names.

An experimental iPhone-to-Mac input system built in native Swift. An iPhone processes RGB camera frames locally, estimates hand joints, and sends compact observations to a Mac. The receiver turns them into a stabilized pointer, pinch clicks, held-pinch drags, and fist scrolling.

**[Open the visual walkthrough →](docs/index.html)**

The walkthrough is a self-contained HTML file: open it in a browser, explore the illustrative gesture demo, or switch to presentation mode. It needs no server, account, fonts, or JavaScript dependencies from the internet.

## What works today

- RGB hand tracking on an iPhone 16e, with a landscape camera view.
- Relative pointer movement with adaptive smoothing and slower fine adjustments.
- Pinch/release clicks and held-pinch drags on macOS; moving a real window was confirmed in a live trial.
- Fist scrolling in the Mac practice document, confirmed by the tester, including the faster scroll setting.
- Local Bonjour discovery, acknowledged TCP packets, and input cancellation on tracking loss or disconnection.

This is a prototype, not a measured accessibility product. Trials have involved one tester. End-to-end latency, false activation rates, fatigue, and dark-room performance have not been quantified. System-wide scroll injection is implemented; the confirmed scrolling trial used the practice document.

## How it works

```text
iPhone RGB camera → Apple Vision hand joints → hand observations
                                                    │
                                          Bonjour + local TCP
                                                    │
Mac: tracking checks → motion filter / gesture state → test UI or system input
```

Video stays on the phone. The network carries hand coordinates, validity flags, gesture state, sequence numbers, and analysis duration. The current local TCP connection has **no application-level pairing, authentication, or encryption**. Use the prototype only on a trusted network, particularly with system cursor control enabled. Pairing/authentication is a priority before broader use.

The Mac app starts in test mode. System input requires macOS Accessibility permission and explicit activation. Control–Option–Command–P pauses system control; the Mac pause button and the phone's Stop button also stop input. Losing tracking releases a held mouse button, which can finish an action already in progress in the target app.

## Try it

Use a Mac with Xcode command-line tools and an iPhone with a suitable front camera. The tested device is an iPhone 16e. The iPhone project targets iOS 18 or later; builds were tested using Xcode 27.2. Other devices and older Xcode releases have not been validated. The probe currently enumerates TrueDepth devices; adapting camera discovery is needed for RGB-only phones. LiDAR is not used by the working RGB pipeline.

1. Build the Mac app with `./HandControl/build.sh`, then open `HandControl/build/HandControl.app`.
2. Build and install the iPhone app using Xcode and your own signing team. See [the phone guide](TrueDepthProbe/README.md).
3. Allow camera and Local Network access. Place the phone sideways, screen up, and start **RGB → Mac**.
4. Test pointing and pinch clicks on the tiles, then use **Scroll practice**. Start with the hand about 20–50 cm above the camera and adjust for visibility and comfort.
5. Enable system control only after the practice interactions work reliably. See [the Mac guide](HandControl/README.md).

For a portable source copy with example bundle IDs and no local signing credentials, use the release export described in [OPEN_SOURCE.md](OPEN_SOURCE.md).

## Where the code lives

| Path | Responsibility |
| --- | --- |
| `TrueDepthProbe/Sources/App.swift` | Camera capture, orientation, hand joints and pose classification |
| `TrueDepthProbe/Sources/HandSender.swift` | Local discovery, TCP transport, acknowledgements and reconnect |
| `Shared/HandPacket.swift` | Wire format, pinch gating and fist classification |
| `HandControl/PointerMotion.swift` | One Euro filtering, dead zone and relative pointer gain |
| `HandControl/ScrollGesture.swift` | Scroll entry, recognition-gap handling and vertical motion |
| `HandControl/SystemPointer.swift` | Mouse events, click/drag state and release handling |
| `HandControl/main.swift` | Native Mac UI, receiver and system-control lifecycle |

The Mac build runs existing state-machine regression checks. They cover clicks, dragging, cancellation, precision gain, tracking reacquisition, fist classification and scroll recovery. They verify implementation behavior, not human accuracy or comfort.

## Where this is going

The intended everyday target is **a phone driving display glasses**, ideally with that same phone providing input. The Mac is the development testbed. A real system pointer on the target phone, operating existing apps, is the next feasibility milestone.

That milestone is **not implemented or proven**. macOS event injection cannot simply be ported into an ordinary iOS app. Built-in accessibility controls and external Bluetooth input are research candidates. Using a second phone as a controller is a fallback; a single-phone setup is the preference.

## Scope and attribution

No glasses hardware is required for the demonstrated iPhone-to-Mac input. These Swift apps contain no glasses firmware or vendor HID commands. Firmware research, raw device logs and private lab notes are intentionally excluded from the proposed public package.

The motion filter follows the [One Euro filter](https://gery.casiez.net/1euro/) by Géry Casiez, Nicolas Roussel and Daniel Vogel (CHI 2012). Camera capture and hand pose estimation use Apple's AVFoundation and Vision frameworks; system events on Mac use Core Graphics. See [the walkthrough](docs/index.html#build) for implementation links.

## License

Released under the [MIT License](LICENSE). This is an experimental prototype; see [OPEN_SOURCE.md](OPEN_SOURCE.md) for what is included and its known limitations.
