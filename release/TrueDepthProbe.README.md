# PalmRay iPhone probe

The native app is still named **TrueDepth Probe**. It captures camera frames, runs Apple Vision hand pose estimation locally and streams hand observations to the Mac receiver. No camera frames are sent over the network or saved by the app. Device diagnostics and hand-state logs are written to the app's Documents directory; the Share log action exports them explicitly.

## Build

Requires Xcode, XcodeGen, a developer signing team and a connected iPhone. Tested with Xcode 27.2 and an iPhone 16e on iOS 26.6.1. The deployment target is iOS 18. Other devices have not been validated. This probe currently discovers TrueDepth cameras; adapting discovery to ordinary RGB front cameras is still needed for phones without TrueDepth.

From the source root:

```sh
cd TrueDepthProbe
xcodegen generate
open TrueDepthProbe.xcodeproj
```

In Xcode, select your Apple development team, choose a unique bundle identifier, select your iPhone and run. The example project has no preselected team.

For a command-line build after configuring signing:

```sh
xcodebuild -project TrueDepthProbe.xcodeproj \
  -scheme TrueDepthProbe -configuration Debug -sdk iphoneos \
  -derivedDataPath /private/tmp/palmray-probe-build \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  PRODUCT_BUNDLE_IDENTIFIER=com.yourname.PalmRayProbe \
  -allowProvisioningUpdates build
```

The build product is `/private/tmp/palmray-probe-build/Build/Products/Debug-iphoneos/TrueDepthProbe.app`. Use Xcode or `xcrun devicectl device install app --device YOUR_DEVICE_ID` followed by that path. Use your configured bundle identifier if launching from `devicectl`. The optional app argument `--mac-control` starts RGB streaming immediately; normal launch waits for a choice.

## Run

1. Build and start the Mac receiver. Allow camera and Local Network access on the phone and Local Network access on the Mac.
2. With orientation lock off, rotate the phone sideways while holding it upright, then place it screen up on a desk or lap.
3. Tap **Start RGB → Mac**. Begin with one hand about 20–50 cm above the front camera and adjust for a clear view.
4. Move an open hand to aim. Pinch thumb and index with the other fingers open to click; hold the pinch to drag. Make a relaxed fist and move vertically to scroll. Open the hand to return to pointing.
5. Use the Mac practice UI first. Stop on the phone ends capture and disconnects the sender. Backgrounding the app also stops capture.

Portrait and both landscape orientations are supported. Preview and Vision coordinates share the same orientation transform. Rotation briefly invalidates input to cancel stale gestures.

## What the probe established

Normal-light RGB tracking was more consistent for the tester than hand detection on grayscale depth frames. Public RGB video was 1280×720; the public depth stream was 640×360 at approximately 30 FPS after startup. The working pointer pipeline uses RGB, not LiDAR or depth.

The probe also dynamically checks two experimental infrared device-type symbols. One resolved but discovered no devices; the other was unavailable. The tested TrueDepth device exposed only the front RGB camera through its constituent-device list. Raw IR discovery remains unsuccessful through these routes. Dark-room performance is unverified.

The normal diagnostic view analyzes up to ten frames per second. Streaming analyzes at most twenty per second, subject to capture scheduling and processing; the initial live Mac session received roughly fifteen updates per second. Processing time is not end-to-end latency.

## Input and privacy limits

Palm movement and pinch validity are separate. A visible middle-finger base can continue pointing when fingertips are unclear. Unknown pinch state disables clicking. A fist uses visible curled-finger evidence and does not require every finger tip to be visible. The Mac receiver handles debounce, pause and input release.

Bonjour and plain TCP send only compact observations. There is no application-level pairing, authentication or encryption. Use a trusted network; this is a prototype. Private device logs are not included in the public preview. This app contains no glasses communication or firmware code.
