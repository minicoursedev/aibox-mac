#!/bin/zsh
set -euo pipefail

aibox_root="${0:A:h:h}"
cd "$aibox_root"
swift build
aibox_bundle="$aibox_root/build/AIBox.app"
mkdir -p "$aibox_bundle/Contents/MacOS"
cp .build/debug/AIBox "$aibox_bundle/Contents/MacOS/AIBox"
cp .build/debug/aibox-notify "$aibox_bundle/Contents/MacOS/aibox-notify"
cp App/Info.plist "$aibox_bundle/Contents/Info.plist"
mkdir -p "$aibox_bundle/Contents/Resources"
rm -rf "$aibox_bundle/Contents/Resources/AIBoxMac_AIBoxCore.bundle"
cp -R .build/debug/AIBoxMac_AIBoxCore.bundle "$aibox_bundle/Contents/Resources/"
codesign --force --sign - "$aibox_bundle/Contents/MacOS/aibox-notify"
codesign --force --sign - "$aibox_bundle"
printf 'App 已建立：%s\n' "$aibox_bundle"
