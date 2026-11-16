#!/bin/zsh
set -eu
cd "${0:A:h}/.."
app_bundle="$PWD/HandControl/build/HandControl.app"
mkdir -p "$app_bundle/Contents/MacOS"
cp HandControl/Info.plist "$app_bundle/Contents/Info.plist"
swiftc -module-cache-path /private/tmp/rayneo-swift-cache Shared/HandPacket.swift HandControl/SystemPointer.swift HandControl/PointerMotion.swift HandControl/ScrollGesture.swift HandControl/main.swift -o "$app_bundle/Contents/MacOS/HandControl"
"$app_bundle/Contents/MacOS/HandControl" --self-test
signing_identity="${HAND_CONTROL_SIGNING_IDENTITY:--}"
codesign --force --sign "$signing_identity" "$app_bundle"
