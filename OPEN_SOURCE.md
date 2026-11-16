# Open-source preparation

PalmRay is released under the [MIT License](LICENSE).

## Reviewable export

Run:

```sh
python3 tools/export_open_source.py
```

This creates `dist/palmray-preview/` and `dist/palmray-preview.zip`. It copies only an explicit list of source and documentation files. It does not change the working phone app or Mac signing setup.

The export:

- Includes the original Swift prototype, the offline HTML walkthrough, setup guides, and example project configuration.
- Replaces local bundle IDs with `com.example` identifiers and removes the original signing-team and signing-certificate identifiers.
- Uses an ad-hoc signature by default for the Mac preview; contributors can supply their own stable identity with `HAND_CONTROL_SIGNING_IDENTITY`. macOS may require Accessibility authorization again after a rebuild without a stable signing identity.
- Generates the iPhone project using XcodeGen and an explicitly supplied `DEVELOPMENT_TEAM` at build time.
- Excludes device logs, generated Xcode projects, built apps, device identifiers, local paths, private handoff notes, and glasses protocol/reverse-engineering tools.

The exporter scans its output for the known local identity values, absolute home-directory paths, and accidental private files. This is a scoped check, not a general-purpose secret scanner or a complete license audit. The export is freshly assembled each time; it refuses to remove a nonempty destination and accepts `--output` for another preview directory.

## Known product limits to disclose

The transport is local plain TCP with Bonjour discovery. There is no sender authentication, pairing approval or transport encryption. A peer on the same reachable network could attempt to supply pointer input while system control is enabled. A release for broader use should add authenticated pairing and transport protection; the current prototype should be restricted to trusted networks.

System cursor control requires Accessibility permission. Tracking loss, pause and disconnect release held input. Releasing a mouse button can finish an action that already began. Start with the test window and harmless controls.

The phone probe still selects TrueDepth devices. Its working detector uses RGB, but support for phones with only ordinary front cameras requires a capture-discovery change and a device test. Dark-room recognition and end-to-end latency remain unverified. Only one tester has tried the prototype. Fist scrolling was confirmed in the practice document; system scrolling still needs explicit live validation.

System-wide control of other apps on the same iPhone is a research objective, not a supported feature. The HTML demo is a scripted browser illustration and never reads a camera or controls the operating system.

## Attribution

The One Euro implementation follows the published algorithm by Casiez, Roussel and Vogel: [authors' page](https://gery.casiez.net/1euro/) and [reference implementations](https://github.com/casiez/OneEuroFilter). No external JavaScript, fonts or images are bundled in the HTML. The Bluetooth projects mentioned during feasibility research have not been incorporated into this code.

## Validation of this preview

The exported Mac build and existing regression checks pass. The generated iPhone project also compiles for iOS Simulator with signing disabled. Browser checks cover responsive layout, simulated clicks, sample scrolling, reset, presentation navigation and keyboard control. See [validation notes](release/VALIDATION.md) for scope and limitations.
