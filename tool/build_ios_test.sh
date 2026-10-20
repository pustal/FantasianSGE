#!/usr/bin/env bash
#
# Builds an iOS test artifact of FantasianSGE without an Apple Developer
# account.
#
# iOS installs nothing that is not signed by a certificate Apple issued for
# that device, so only two things are possible without an account:
#
#   simulator   (default) a Runner.app for the iOS Simulator. Needs no
#               signature and runs on any Mac with Xcode.
#
#   --device    an unsigned .ipa, to be re-signed with your own Apple ID in
#               Sideloadly or AltStore. With a free Apple ID it works for seven
#               days and a device holds at most three such apps; a paid
#               account removes both limits (and then Xcode or TestFlight is
#               the better route).
#
# Usage:
#   tool/build_ios_test.sh [--device] [--skip-checks] [extra flutter build arguments]
#
# Anything else is passed through to `flutter build ios`.
#
# On iOS the app is a converter: it cannot read FANTASIAN's own save (iOS keeps
# every app's files private), but converts files opened through the Files app.

# shellcheck source=tool/build_common.sh
source "$(dirname "$0")/build_common.sh"

require_macos "The iOS app"

TARGET="simulator"
SKIP_CHECKS=0
# Options may come in either order, before any pass-through arguments.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) TARGET="device"; shift ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    *) break ;;
  esac
done
readonly TARGET

readonly NAME="FantasianSGE"
readonly BUNDLE_ID="com.pustal.fantasianSge"

run_checks "$SKIP_CHECKS"

if [[ "$TARGET" == "simulator" ]]; then
  # Debug, not release: the Simulator runs the host architecture and Flutter
  # has no AOT release build for it.
  step "flutter build ios --simulator --debug ($BUILD_STAMP) $*"
  flutter build ios --simulator --debug "$STAMP_DEFINE" "$@"

  readonly APP="build/ios/iphonesimulator/Runner.app"
  [[ -d "$APP" ]] || die "The build reported success but $APP is not there."

  readonly ZIP="$OUT/$NAME-$VERSION-$STAMP_SLUG-ios-simulator.zip"
  rm -f "$OUT"/$NAME-*-ios-simulator.zip
  # ditto, not zip: a bundle is built out of symlinks that zip would follow.
  ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

  cat > "$OUT/READ ME FIRST (iOS Simulator).txt" <<NOTE
FantasianSGE $VERSION - iOS Simulator
=====================================

Built $BUILD_STAMP. The same value is on the About screen, after "Build".

This runs in the Simulator on a Mac, not on a phone. To install:

  1. Unzip it.
  2. Open the Simulator (Xcode > Open Developer Tool > Simulator) and boot a
     device.
  3. Drag Runner.app onto the simulated screen, or run:

         xcrun simctl install booted Runner.app
         xcrun simctl launch booted $BUNDLE_ID

To test with a save, drag a FANTASIAN zip or a root.json onto the simulated
device; it lands in the Files app, where FantasianSGE can open it.
NOTE

  echo
  echo "Built $ZIP"
  echo "Hand it round with '$OUT/READ ME FIRST (iOS Simulator).txt'."
  exit 0
fi

# --- unsigned device build ---------------------------------------------------

step "flutter build ios --release --no-codesign ($BUILD_STAMP) $*"
flutter build ios --release --no-codesign "$STAMP_DEFINE" "$@"

readonly APP="build/ios/iphoneos/Runner.app"
[[ -d "$APP" ]] || die "The build reported success but $APP is not there."

readonly IPA="$OUT/$NAME-$VERSION-$STAMP_SLUG-ios-unsigned.ipa"
readonly STAGE="$OUT/.payload-$STAMP_SLUG"
rm -f "$OUT"/$NAME-*-ios-unsigned.ipa
rm -rf "$STAGE"
# An .ipa is a zip holding the bundle under Payload/ and nothing else, which
# is the layout Sideloadly and AltStore expect.
mkdir -p "$STAGE/Payload"
cp -a "$APP" "$STAGE/Payload/"
(cd "$STAGE" && ditto -c -k --sequesterRsrc --keepParent Payload "../../../$IPA")
rm -rf "$STAGE"

cat > "$OUT/READ ME FIRST (iOS).txt" <<NOTE
FantasianSGE $VERSION - iPhone / iPad
=====================================

Built $BUILD_STAMP. The same value is on the About screen, after "Build".

This .ipa is unsigned and will not install as it is. Re-sign it with your own
Apple ID:

  1. Install Sideloadly (sideloadly.io) or AltStore on a Mac or PC.
  2. Connect the iPhone or iPad by cable and trust the computer.
  3. Drag this .ipa in, enter an Apple ID, and let it install.
  4. On the device: Settings > General > VPN & Device Management, and trust
     the developer certificate shown there.

With a free Apple ID the app stops opening after seven days and has to be
installed again the same way, and a device holds at most three sideloaded apps.

On iOS FantasianSGE converts files you open through the Files app (a zip of
the FANTASIAN folder, or a root.json). It cannot read FANTASIAN's own save on
the device: iOS keeps every app's files private. See the About screen.
NOTE

step "What was built"
du -h "$IPA" | sed 's/^/    ipa: /'
echo
echo "Built $IPA  (unsigned; see the note beside it)"
echo "Hand it round with '$OUT/READ ME FIRST (iOS).txt'."
