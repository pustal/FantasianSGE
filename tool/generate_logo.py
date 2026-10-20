#!/usr/bin/env python3
"""Generates the FantasianSGE logo and app icons as SVG.

The emblem: a faceted save crystal floating inside a brass gear ring (a nod to
the hand-built, clockwork dioramas of FANTASIAN's world), circled by two gold
arrows for the two-way transfer between Apple Arcade and Neo Dimension.

Outputs (in assets/brand/):
  logo.svg          emblem on a transparent background (used in the app)
  app_icon.svg      full-bleed square icon (iOS, Windows, Linux)
  app_icon_mac.svg  rounded-square icon with the macOS margin

Render to PNG with:  rsvg-convert -w 1024 assets/brand/app_icon.svg -o icon.png
"""

import math
import os

SIZE = 1024
CX = CY = SIZE / 2

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "brand")


def gear_path(cx, cy, r_outer, r_root, teeth, tooth_frac=0.46):
    """A closed gear outline: flat-topped teeth between r_root and r_outer."""
    pts = []
    step = 2 * math.pi / teeth
    for i in range(teeth):
        a0 = i * step - math.pi / 2
        half_tip = step * tooth_frac / 2
        half_base = half_tip * 1.35
        for ang, r in ((a0 - half_base, r_root), (a0 - half_tip, r_outer),
                       (a0 + half_tip, r_outer), (a0 + half_base, r_root)):
            pts.append((cx + r * math.cos(ang), cy + r * math.sin(ang)))
    d = "M " + " L ".join(f"{x:.1f} {y:.1f}" for x, y in pts) + " Z"
    return d


def circle_path(cx, cy, r):
    """A circle as a path, so it can cut a hole with evenodd."""
    return (f"M {cx - r:.1f} {cy:.1f} a {r:.1f} {r:.1f} 0 1 0 {2 * r:.1f} 0 "
            f"a {r:.1f} {r:.1f} 0 1 0 {-2 * r:.1f} 0 Z")


def arc_arrow(cx, cy, r, start_deg, end_deg, head=66):
    """An arc from start to end (clockwise, degrees, 0 = east) with a head."""
    def pt(deg, rad=r):
        a = math.radians(deg)
        return cx + rad * math.cos(a), cy + rad * math.sin(a)

    x0, y0 = pt(start_deg)
    x1, y1 = pt(end_deg)
    large = 1 if (end_deg - start_deg) % 360 > 180 else 0
    arc = f"M {x0:.1f} {y0:.1f} A {r} {r} 0 {large} 1 {x1:.1f} {y1:.1f}"
    # Arrowhead: a triangle pointing along the tangent at the end.
    tangent = math.radians(end_deg + 90)
    tip = (x1 + head * 0.9 * math.cos(tangent), y1 + head * 0.9 * math.sin(tangent))
    left = pt(end_deg, r - head * 0.75)
    right = pt(end_deg, r + head * 0.75)
    headd = (f"M {left[0]:.1f} {left[1]:.1f} L {tip[0]:.1f} {tip[1]:.1f} "
             f"L {right[0]:.1f} {right[1]:.1f} Z")
    return arc, headd


def emblem():
    """The emblem's SVG elements (no background)."""
    gear = gear_path(CX, CY, 412, 372, 18)
    ring_hole = circle_path(CX, CY, 318)
    arc1, head1 = arc_arrow(CX, CY, 262, 200, 318)
    arc2, head2 = arc_arrow(CX, CY, 262, 20, 138)

    # Crystal: an elongated hexagonal gem with four facets.
    top, bottom = (CX, 268), (CX, 760)
    lt, rt = (CX - 96, 420), (CX + 96, 420)
    lb, rb = (CX - 96, 612), (CX + 96, 612)
    mid_top, mid_bot = (CX, 458), (CX, 574)

    def poly(*pts):
        return " ".join(f"{x:.0f},{y:.0f}" for x, y in pts)

    stars = [(372, 372, 7), (660, 352, 5), (664, 650, 7), (360, 668, 4)]
    star_svg = "\n".join(
        f'<path d="M {x} {y - s * 3} L {x + s * 0.8} {y - s * 0.8} L {x + s * 3} {y} '
        f'L {x + s * 0.8} {y + s * 0.8} L {x} {y + s * 3} L {x - s * 0.8} {y + s * 0.8} '
        f'L {x - s * 3} {y} L {x - s * 0.8} {y - s * 0.8} Z" fill="#FFF3C8" opacity="0.9"/>'
        for x, y, s in stars)

    return f"""
  <defs>
    <linearGradient id="gold" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FBE3A0"/>
      <stop offset="0.45" stop-color="#E0B456"/>
      <stop offset="1" stop-color="#9C6B22"/>
    </linearGradient>
    <radialGradient id="well" cx="0.5" cy="0.45" r="0.6">
      <stop offset="0" stop-color="#22366B"/>
      <stop offset="1" stop-color="#0B1230"/>
    </radialGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="#9BEBFF" stop-opacity="0.75"/>
      <stop offset="1" stop-color="#9BEBFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <path d="{gear} {ring_hole}" fill="url(#gold)" fill-rule="evenodd"
        stroke="#6E4A14" stroke-width="6" stroke-linejoin="round"/>
  <circle cx="{CX}" cy="{CY}" r="318" fill="url(#well)"/>
  <circle cx="{CX}" cy="{CY}" r="318" fill="none" stroke="#6E4A14" stroke-width="6"/>
  <circle cx="{CX}" cy="{CY}" r="300" fill="none" stroke="#E0B456" stroke-width="3" opacity="0.55"/>
  {star_svg}
  <circle cx="{CX}" cy="{CY + 4}" r="210" fill="url(#glow)"/>
  <g stroke="#2A1A05" stroke-width="5" stroke-linejoin="round">
    <polygon points="{poly(top, lt, mid_top)}" fill="#D9FAFF"/>
    <polygon points="{poly(top, rt, mid_top)}" fill="#8FDDF5"/>
    <polygon points="{poly(lt, lb, mid_bot, mid_top)}" fill="#6CCBEC"/>
    <polygon points="{poly(rt, rb, mid_bot, mid_top)}" fill="#3A93CF"/>
    <polygon points="{poly(lb, bottom, mid_bot)}" fill="#3F9FD6"/>
    <polygon points="{poly(rb, bottom, mid_bot)}" fill="#1F5C9A"/>
  </g>
  <path d="M {CX - 58} 446 L {CX - 30} 360" stroke="#FFFFFF" stroke-width="12"
        stroke-linecap="round" opacity="0.85"/>
  <g fill="none" stroke="url(#gold)" stroke-width="30" stroke-linecap="round">
    <path d="{arc1}"/>
    <path d="{arc2}"/>
  </g>
  <path d="{head1}" fill="url(#gold)" stroke="#6E4A14" stroke-width="4" stroke-linejoin="round"/>
  <path d="{head2}" fill="url(#gold)" stroke="#6E4A14" stroke-width="4" stroke-linejoin="round"/>
"""


def background(rounded):
    """Night-sky backdrop; rounded=True gives the macOS icon shape and margin."""
    if rounded:
        # macOS icons sit in an 824px rounded square centred in 1024.
        shape = '<rect x="100" y="100" width="824" height="824" rx="185" fill="url(#sky)"/>'
    else:
        shape = f'<rect width="{SIZE}" height="{SIZE}" fill="url(#sky)"/>'
    return f"""
  <defs>
    <radialGradient id="sky" cx="0.5" cy="0.35" r="0.85">
      <stop offset="0" stop-color="#3B4F8C"/>
      <stop offset="0.55" stop-color="#1A2654"/>
      <stop offset="1" stop-color="#0A0F26"/>
    </radialGradient>
  </defs>
  {shape}
"""


def svg(body, scale=1.0):
    """Wraps elements in an SVG document, optionally shrinking the emblem."""
    inner = body
    if scale != 1.0:
        off = CX * (1 - scale)
        inner = f'<g transform="translate({off:.1f} {off:.1f}) scale({scale})">{body}</g>'
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" '
            f'width="{SIZE}" height="{SIZE}">{inner}</svg>\n')


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    files = {
        "logo.svg": svg(emblem()),
        "app_icon.svg": svg(background(False) + f'<g transform="translate({CX * 0.12:.1f} {CY * 0.12:.1f}) scale(0.88)">{emblem()}</g>'),
        "app_icon_mac.svg": svg(background(True) + f'<g transform="translate({CX * 0.3:.1f} {CY * 0.3:.1f}) scale(0.7)">{emblem()}</g>'),
    }
    for name, content in files.items():
        with open(os.path.join(OUT_DIR, name), "w", encoding="utf-8") as f:
            f.write(content)
        print("wrote", name)


if __name__ == "__main__":
    main()
