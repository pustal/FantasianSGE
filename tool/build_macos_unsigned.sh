#!/usr/bin/env bash
#
# Builds a macOS release of FantasianSGE without an Apple Developer account
# and zips it for handing round.
#
# The bundle is **ad-hoc signed** (CODE_SIGN_IDENTITY = "-", already set in the
# Xcode project): a valid signature nobody vouches for. It runs, but Gatekeeper
# refuses it on first launch until the quarantine attribute is removed. The
# READ ME written beside the zip says how.
#
# Usage:
#   tool/build_macos_unsigned.sh [--skip-checks] [extra flutter build arguments]
#
#   --skip-checks   skip `flutter analyze` and `flutter test`
#
# Anything else is passed through to `flutter build macos`.
#
# TWO ZIPS COME OUT OF ONE BUILD
#
#   FantasianSGE-<version>-<stamp>-macos-unsigned.zip        Impeller. Use this.
#   FantasianSGE-<version>-<stamp>-macos-unsigned-skia.zip   Skia. Only if that one hangs.
#
# Impeller, Flutter's default renderer, deadlocks in Metal's shader compiler on
# some older Intel GPUs (e.g. HD 4000): the icon bounces, no window appears.
# That is a Flutter fault (https://github.com/flutter/flutter/issues/153371),
# not an app one. The Skia copy is the same bundle with one Info.plist key
# changed, so it costs a second ditto, not a second build.
#
# About the sandbox: FantasianSGE ships with the App Sandbox off, because it
# has to reach FANTASIAN's container and check whether the game is running.
# There are no restricted entitlements, so nothing has to be swapped to sign
# ad-hoc.

# shellcheck source=tool/build_common.sh
source "$(dirname "$0")/build_common.sh"

require_macos "The macOS app"

SKIP_CHECKS=0
if [[ "${1:-}" == "--skip-checks" ]]; then
  SKIP_CHECKS=1
  shift
fi

readonly NAME="FantasianSGE"
readonly PRODUCTS="build/macos/Build/Products/Release"
readonly APP="$PRODUCTS/$NAME.app"
# The Skia copy goes in a subfolder so its bundle can keep the name
# FantasianSGE.app: ditto --keepParent names the folder inside the zip after
# the bundle, and "FantasianSGE-skia.app" would install as a second app.
readonly SKIA_DIR="$PRODUCTS/skia"
readonly SKIA_APP="$SKIA_DIR/$NAME.app"
readonly ZIP="$OUT/$NAME-$VERSION-$STAMP_SLUG-macos-unsigned.zip"
readonly ZIP_SKIA="$OUT/$NAME-$VERSION-$STAMP_SLUG-macos-unsigned-skia.zip"

run_checks "$SKIP_CHECKS"

step "flutter build macos --release ($BUILD_STAMP) $*"
flutter build macos --release "$STAMP_DEFINE" "$@"
[[ -d "$APP" ]] || die "The build reported success but $APP is not there."

step "Making the Skia variant"
# ditto rather than cp -a: bundle frameworks are symlinks with extended
# attributes, and ditto is the copy that reliably keeps both.
rm -rf "$SKIA_DIR"
mkdir -p "$SKIA_DIR"
ditto "$APP" "$SKIA_APP"
# Only the copy's Info.plist changes; the project keeps Impeller on.
/usr/libexec/PlistBuddy -c 'Add :FLTEnableImpeller bool false' \
  "$SKIA_APP/Contents/Info.plist" 2>/dev/null ||
  /usr/libexec/PlistBuddy -c 'Set :FLTEnableImpeller false' "$SKIA_APP/Contents/Info.plist"
# Editing a signed bundle invalidates its signature, which macOS reports as
# "damaged", so sign the copy again.
codesign --force --deep --sign - "$SKIA_APP"

step "What was built"
# An arm64-only bundle will not start on an Intel Mac, and a broken signature
# turns the quarantine prompt into a misleading "damaged" dialog.
lipo -archs "$APP/Contents/MacOS/$NAME" 2>/dev/null | sed 's/^/    architectures: /' || true
if codesign --verify --deep --strict "$APP"; then
  echo "    signature:     valid (ad-hoc)"
else
  echo "    signature:     INVALID - do not distribute this"
fi
if codesign --verify --deep --strict "$SKIA_APP"; then
  echo "    skia copy:     valid (ad-hoc)"
else
  echo "    skia copy:     INVALID - do not distribute this"
fi

# Older zips go, so the wrong build is never the one picked up. The glob also
# catches the -skia ones.
rm -f "$OUT"/$NAME-*-macos-unsigned*.zip

cat > "$OUT/READ ME FIRST (macOS).txt" <<NOTE
FantasianSGE $VERSION - macOS
=============================

Built $BUILD_STAMP. The same value is on the About screen, after "Build".


WHICH ZIP
---------

  $(basename "$ZIP")
      The normal build. Use this one.

  $(basename "$ZIP_SKIA")
      Only for a Mac where the first one will not open: the icon bounces once,
      no window appears, and the app shows as not responding. That is a
      graphics-renderer fault on some older Intel Macs. Apple Silicon Macs
      never need this one.


INSTALLING
----------

This build has no Apple Developer certificate behind it, so macOS refuses it
the first time and calls it "damaged" or "cannot be opened". Nothing is
damaged.

  1. Unzip and drag FantasianSGE.app into Applications.

  2. In Terminal, run exactly:

         xattr -dr com.apple.quarantine /Applications/FantasianSGE.app

     That removes the "downloaded from the internet" flag from this one app.
     (Or: try to open it once, then System Settings > Privacy & Security >
     Open Anyway.)

  3. Open FantasianSGE.

The first time it reads FANTASIAN's save, macOS may ask whether FantasianSGE
may access data from other apps. Allow it: the save lives inside FANTASIAN's
own container.
NOTE

step "Packaging"
# ditto, not zip: zip follows the bundle's symlinks, duplicating binaries and
# breaking the signature.
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$SKIA_APP" "$ZIP_SKIA"
# Leave nothing installable in build/ but the real bundle.
rm -rf "$SKIA_DIR"

echo
echo "Built $ZIP"
echo "      $ZIP_SKIA  (only for Macs the first will not open on)"
echo "Hand them round with '$OUT/READ ME FIRST (macOS).txt'."
