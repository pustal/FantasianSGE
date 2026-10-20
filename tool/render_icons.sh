#!/usr/bin/env bash
# Renders the app icons for every platform from the SVGs in assets/brand.
#
# Requires: python3, rsvg-convert (librsvg) and ImageMagick's `convert`.
#   macOS:  brew install librsvg imagemagick
#   Debian: sudo apt install librsvg2-bin imagemagick
#
# Usage (from the repository root):  tool/render_icons.sh
set -euo pipefail

cd "$(dirname "$0")/.."
BRAND=assets/brand

# 1. Regenerate the SVGs from their source.
python3 tool/generate_logo.py

# 2. In-app logo and a preview icon.
rsvg-convert -w 768 "$BRAND/logo.svg" -o "$BRAND/logo.png"
rsvg-convert -w 512 "$BRAND/app_icon.svg" -o "$BRAND/app_icon.png"

# 3. macOS: rounded-square icon with Apple's standard margin.
for size in 16 32 64 128 256 512 1024; do
  rsvg-convert -w "$size" "$BRAND/app_icon_mac.svg" \
    -o "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_${size}.png"
done

# 4. iOS: full-bleed square, no transparency (App Store requirement).
python3 - <<'PY'
import json, subprocess, tempfile, os
folder = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
contents = json.load(open(os.path.join(folder, "Contents.json")))
tmp = tempfile.mktemp(suffix=".png")
done = set()
for image in contents["images"]:
    name = image.get("filename")
    if not name or name in done:
        continue
    pixels = round(float(image["size"].split("x")[0]) * int(image["scale"].rstrip("x")))
    subprocess.run(["rsvg-convert", "-w", str(pixels), "assets/brand/app_icon.svg", "-o", tmp], check=True)
    subprocess.run(["convert", tmp, "-background", "#0A0F26", "-alpha", "remove",
                    "-alpha", "off", os.path.join(folder, name)], check=True)
    done.add(name)
os.remove(tmp)
PY

# 5. Windows: one multi-resolution .ico.
tmpdir="$(mktemp -d)"
for size in 16 24 32 48 64 128 256; do
  rsvg-convert -w "$size" "$BRAND/app_icon.svg" -o "$tmpdir/$size.png"
done
convert "$tmpdir"/{16,24,32,48,64,128,256}.png windows/runner/resources/app_icon.ico
rm -rf "$tmpdir"

echo "Icons rendered."
