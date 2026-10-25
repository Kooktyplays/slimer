#!/usr/bin/env python3
"""Draw Slimer's typeface and emit it as a TrueType file.

Why this file exists at all
--------------------------
The game had no font. Every label rendered in Godot's stock face, which is the
loudest "unfinished project" signal in the whole build - louder than the sprites,
because text is on screen in every single frame including the menu.

Why it is generated rather than downloaded
------------------------------------------
`RIGHTS.md` and `LICENSE-ASSETS.md` both state that the game contains no
third-party assets, and that claim is load-bearing: thirteen CC BY-NC-SA sprites
previously made the game unsellable at any price, and retiring them is what made
it sellable. A downloaded typeface would re-open exactly that question. So the
letterforms are ours, drawn here, exactly as the slime is.

Why an outline font rather than a bitmap
---------------------------------------
`ui/ui_theme.gd` puts an outline on EVERY label - 6 px normally, 10 px on titles
- and that outline is the only thing keeping white text legible over a green
forest. Outlines come from FreeType's stroker and need real outline data; a
bitmap font has none, so `outline_size` silently becomes a no-op and every label
in the game loses its contrast at once. The UI also asks for 24 distinct sizes
from 12 to 104, an 8.7x range no single bitmap atlas covers.

The shapes
----------
Straight-line contours only - every point on-curve, no quadratics. That is not a
shortcut to dodge writing a curve fitter. The entire art pack is flat polygons
with chamfered silhouettes (see `Art.blob` and the octagonal props in
gen_art.py), and a face built the same way belongs to it. Bowls are octagons,
diagonals are real diagonals, and at 12 px the chamfers read as curves anyway.
"""
from __future__ import annotations

from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.ttGlyphPen import TTGlyphPen

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "fonts" / "gen"

# --------------------------------------------------------------------------
# metrics
# --------------------------------------------------------------------------
UPM = 1000
ASCENDER = 760
DESCENDER = -200
CAP = 700          # cap height
XH = 490           # x-height
STEM = 116         # vertical stem
THIN = 104         # horizontal bar
CH = 84            # corner chamfer on caps
CHX = 70           # corner chamfer on lowercase
SIDE = 70          # default side bearing

## Every digit shares this advance.
##
## Tabular on purpose. The HUD counts money, waves, kills and a combo multiplier
## upward in real time, and with proportional figures a 1 replacing a 0 makes the
## whole number twitch sideways every frame it changes.
DIGIT_ADV = 560

## A fixed head timestamp, so the file is byte-identical across regenerations.
## Seconds since 1904-01-01, which is TrueType's epoch; this is 2026-01-01.
FONT_EPOCH = 3850070400


# --------------------------------------------------------------------------
# contour helpers
#
# Outer contours are wound CLOCKWISE in this y-up space and counters
# ANTI-clockwise. TrueType fills by non-zero winding, so a counter wound the same
# way as its bowl adds to the winding number instead of cancelling it, and the
# glyph comes out solid - an O that looks like a filled blob is always this.
# --------------------------------------------------------------------------
def _area(contour: list) -> float:
    """Twice the signed area. Negative is clockwise in this y-up space."""
    total = 0.0
    for i in range(len(contour)):
        x0, y0 = contour[i]
        x1, y1 = contour[(i + 1) % len(contour)]
        total += x0 * y1 - x1 * y0
    return total


def cw(contour: list) -> list:
    """Force clockwise: an OUTER contour, ink."""
    return contour if _area(contour) <= 0 else list(reversed(contour))


def ccw(contour: list) -> list:
    """Force anti-clockwise: a COUNTER, a hole punched in an outer contour."""
    return contour if _area(contour) >= 0 else list(reversed(contour))


def rect(x0: float, y0: float, x1: float, y1: float) -> list:
    """An axis-aligned box, clockwise."""
    return [(x0, y0), (x0, y1), (x1, y1), (x1, y0)]


def oct_box(x0: float, y0: float, x1: float, y1: float, c: float) -> list:
    """A box with its four corners cut, clockwise. The workhorse shape."""
    return cw([
        (x0 + c, y0), (x0, y0 + c), (x0, y1 - c), (x0 + c, y1),
        (x1 - c, y1), (x1, y1 - c), (x1, y0 + c), (x1 - c, y0),
    ])


def ring(x0: float, y0: float, x1: float, y1: float, c: float,
         tx: float, ty: float) -> list:
    """An octagonal bowl: outer clockwise, counter reversed."""
    outer = oct_box(x0, y0, x1, y1, c)
    inner = oct_box(x0 + tx, y0 + ty, x1 - tx, y1 - ty, max(c - min(tx, ty), 8))
    return [cw(outer), ccw(inner)]


def poly(*points: tuple) -> list:
    return cw(list(points))


def c_shape(x0: float, y0: float, x1: float, y1: float, c: float,
            t: float) -> list:
    """An octagonal bowl with its right side open - C, and the base of G.

    Traced as one contour rather than built from a ring with a bite taken out,
    because non-zero winding unions overlapping contours, it cannot subtract
    them. Anything that needs a hole has to be traced.
    """
    ci = max(c - t, 10)
    return cw([
        (x0 + c, y0), (x0, y0 + c), (x0, y1 - c), (x0 + c, y1), (x1, y1),
        (x1, y1 - t), (x0 + t + ci, y1 - t), (x0 + t, y1 - t - ci),
        (x0 + t, y0 + t + ci), (x0 + t + ci, y0 + t), (x1, y0 + t), (x1, y0),
    ])


def u_shape(x0: float, y0: float, x1: float, y1: float, c: float,
            t: float) -> list:
    """An octagonal bowl open at the TOP - U, and the base of J."""
    ci = max(c - t, 10)
    return cw([
        (x0 + c, y0), (x0, y0 + c), (x0, y1), (x0 + t, y1),
        (x0 + t, y0 + t + ci), (x0 + t + ci, y0 + t),
        (x1 - t - ci, y0 + t), (x1 - t, y0 + t + ci), (x1 - t, y1),
        (x1, y1), (x1, y0 + c), (x1 - c, y0),
    ])


def n_shape(x0: float, y0: float, x1: float, y1: float, c: float,
            t: float) -> list:
    """An octagonal bowl open at the BOTTOM - the arch of n, m, h."""
    ci = max(c - t, 10)
    return cw([
        (x0, y0), (x0, y1 - c), (x0 + c, y1), (x1 - c, y1), (x1, y1 - c),
        (x1, y0), (x1 - t, y0), (x1 - t, y1 - t - ci),
        (x1 - t - ci, y1 - t), (x0 + t + ci, y1 - t), (x0 + t, y1 - t - ci),
        (x0 + t, y0),
    ])


def diag(x0: float, y0: float, x1: float, y1: float, w: float) -> list:
    """A stroke from (x0,y0) to (x1,y1), `w` wide measured horizontally."""
    # Normalised, because the naive point order comes out ANTI-clockwise and a
    # ccw stroke laid across a cw bar cancels to a hole under non-zero winding -
    # which is exactly what put a notch in the apex of the A.
    return cw([(x0, y0), (x0 + w, y0), (x1 + w, y1), (x1, y1)])


def mirror(contour: list, axis: float) -> list:
    """Reflect a contour across a vertical line, preserving its winding.

    Reflection reverses orientation, so the point order is reversed back - a
    mirrored outer contour that stayed anti-clockwise would punch a hole in
    whatever it overlapped instead of adding to it.
    """
    return cw([(2.0 * axis - x, y) for (x, y) in reversed(contour)])


def d_shape(x0: float, y0: float, x1: float, y1: float, c: float,
            t: float) -> list:
    """Flat on the left, chamfered on the right - D, and the bowl of b/p."""
    outer = cw([(x0, y0), (x0, y1), (x1 - c, y1), (x1, y1 - c), (x1, y0 + c),
                (x1 - c, y0)])
    ci = max(c - t, 10)
    inner = [(x0 + t, y0 + t), (x0 + t, y1 - t), (x1 - t - ci, y1 - t),
             (x1 - t, y1 - t - ci), (x1 - t, y0 + t + ci),
             (x1 - t - ci, y0 + t)]
    return [outer, ccw(inner)]


def s_shape(x0: float, y0: float, x1: float, y1: float, t: float) -> list:
    """The S spine: top bar, upper-left stem, waist, lower-right stem, foot.

    Five overlapping boxes rather than one traced contour. Non-zero winding
    unions them, and an S traced in one pass is twenty points that all have to
    be right at once - this is five that can each be checked by eye.
    """
    mid_lo = (y0 + y1) / 2 - t / 2
    mid_hi = mid_lo + t
    return [
        rect(x0, y1 - t, x1, y1),
        rect(x0, mid_lo, x0 + t, y1),
        rect(x0, mid_lo, x1, mid_hi),
        rect(x1 - t, y0, x1, mid_hi),
        rect(x0, y0, x1, y0 + t),
    ]


# --------------------------------------------------------------------------
# the glyph set
#
# Each entry is (advance, [contour, ...]). A contour is a list of (x, y).
# Built as a function so the helpers above stay readable at the call site.
# --------------------------------------------------------------------------
def glyphs() -> dict:
    g: dict = {}

    def put(ch: str, adv: float, *contours) -> None:
        flat: list = []
        for c in contours:
            # ring() returns a list OF contours; everything else one contour.
            if c and isinstance(c[0], list):
                flat.extend(c)
            else:
                flat.append(c)
        g[ch] = (round(adv), [[(round(x), round(y)) for (x, y) in c] for c in flat])

    # ---- space and .notdef ----------------------------------------------
    put(" ", 300)

    # ---- digits, all on DIGIT_ADV ---------------------------------------
    d0, d1 = SIDE, DIGIT_ADV - SIDE
    mid = (d0 + d1) / 2
    put("0", DIGIT_ADV, ring(d0, 0, d1, CAP, CH, THIN, THIN))
    # A 1 with a real flag and a foot, so it cannot be read as a bare bar.
    put("1", DIGIT_ADV,
        rect(mid - STEM / 2, 0, mid + STEM / 2, CAP),
        poly((d0 + 10, CAP - 150), (mid - STEM / 2, CAP - 40),
             (mid - STEM / 2, CAP - 190)),
        rect(d0 + 10, 0, d1 - 10, THIN))
    put("2", DIGIT_ADV,
        rect(d0, CAP - THIN, d1, CAP),
        poly((d1 - THIN, CAP - THIN), (d1, CAP - THIN), (d1, CAP / 2 + 40),
             (d1 - THIN, CAP / 2 + 40)),
        poly((d0, 0), (d0, THIN), (d1, CAP / 2 + 40), (d1 - THIN, CAP / 2 + 40)),
        rect(d0, 0, d1, THIN))
    put("3", DIGIT_ADV,
        rect(d0, CAP - THIN, d1, CAP),
        rect(d0 + 60, CAP / 2 - THIN / 2, d1, CAP / 2 + THIN / 2),
        rect(d0, 0, d1, THIN),
        rect(d1 - THIN, 0, d1, CAP))
    put("4", DIGIT_ADV,
        rect(d1 - THIN - 60, 0, d1 - 60, CAP),
        poly((d0, XH - 40), (d1 - THIN - 60, CAP), (d1 - THIN - 60, XH - 40)),
        rect(d0, XH - 40 - THIN, d1, XH - 40))
    put("5", DIGIT_ADV,
        rect(d0, CAP - THIN, d1, CAP),
        rect(d0, CAP / 2 - THIN / 2, d0 + THIN, CAP),
        rect(d0, CAP / 2 - THIN / 2, d1, CAP / 2 + THIN / 2),
        rect(d1 - THIN, 0, d1, CAP / 2 + THIN / 2),
        rect(d0, 0, d1, THIN))
    put("6", DIGIT_ADV,
        rect(d0, 0, d0 + THIN, CAP),
        rect(d0, CAP - THIN, d1, CAP),
        ring(d0, 0, d1, CAP / 2 + THIN / 2, CH, THIN, THIN))
    put("7", DIGIT_ADV,
        rect(d0, CAP - THIN, d1, CAP),
        poly((mid - STEM / 2, 0), (d1 - THIN, CAP - THIN), (d1, CAP - THIN),
             (mid + STEM / 2, 0)))
    put("8", DIGIT_ADV,
        ring(d0, CAP / 2 - THIN / 2, d1, CAP, CH, THIN, THIN),
        ring(d0, 0, d1, CAP / 2 + THIN / 2, CH, THIN, THIN))
    put("9", DIGIT_ADV,
        rect(d1 - THIN, 0, d1, CAP),
        rect(d0, 0, d1, THIN),
        ring(d0, CAP / 2 - THIN / 2, d1, CAP, CH, THIN, THIN))


    # ---- uppercase -------------------------------------------------------
    # Cap letters sit on a 460-wide body unless the shape needs otherwise. The
    # advance is body + two side bearings, so spacing stays even without a
    # kerning table to lean on.
    L = SIDE
    W = 460
    R = L + W
    cx = (L + R) / 2
    adv = R + SIDE

    # The apex is filled explicitly. Two mirrored diagonals meet there along a
    # coincident edge, and a shared edge between two contours is exactly where a
    # rasteriser drops a pixel - it showed up as a notch in the point of the A.
    put("A", adv,
        diag(L, 0, cx - STEM / 2, CAP - 60, STEM),
        mirror(diag(L, 0, cx - STEM / 2, CAP - 60, STEM), cx),
        poly((cx - STEM / 2 - 40, CAP - 60), (cx - 40, CAP), (cx + 40, CAP),
             (cx + STEM / 2 + 40, CAP - 60)),
        rect(L + 74, XH - 190, R - 74, XH - 190 + THIN))
    put("B", adv,
        rect(L, 0, L + STEM, CAP),
        d_shape(L, CAP / 2 - THIN / 2, R, CAP, CH, THIN),
        d_shape(L, 0, R, CAP / 2 + THIN / 2, CH, THIN))
    put("C", adv, c_shape(L, 0, R, CAP, CH, THIN))
    put("D", adv, d_shape(L, 0, R, CAP, CH, THIN))
    put("E", R - 40 + SIDE,
        rect(L, 0, L + STEM, CAP),
        rect(L, CAP - THIN, R - 40, CAP),
        rect(L, CAP / 2 - THIN / 2, R - 90, CAP / 2 + THIN / 2),
        rect(L, 0, R - 40, THIN))
    put("F", R - 60 + SIDE,
        rect(L, 0, L + STEM, CAP),
        rect(L, CAP - THIN, R - 40, CAP),
        rect(L, CAP / 2 - THIN / 2, R - 90, CAP / 2 + THIN / 2))
    put("G", adv,
        c_shape(L, 0, R, CAP, CH, THIN),
        rect(R - STEM, 0, R, CAP / 2 + THIN / 2),
        rect(cx - 20, CAP / 2 - THIN / 2, R, CAP / 2 + THIN / 2))
    put("H", adv,
        rect(L, 0, L + STEM, CAP),
        rect(R - STEM, 0, R, CAP),
        rect(L, CAP / 2 - THIN / 2, R, CAP / 2 + THIN / 2))
    put("I", 2 * SIDE + STEM, rect(L, 0, L + STEM, CAP))
    put("J", adv - 60,
        rect(R - 60 - STEM, CAP / 2, R - 60, CAP),
        u_shape(L, 0, R - 60, CAP / 2 + THIN, CH, THIN))
    put("K", adv,
        rect(L, 0, L + STEM, CAP),
        diag(L + STEM - 10, CAP / 2 - 60, R - STEM, CAP, STEM),
        diag(R - STEM, 0, L + STEM - 10, CAP / 2 + 60, STEM))
    put("L", R - 40 + SIDE,
        rect(L, 0, L + STEM, CAP),
        rect(L, 0, R - 40, THIN))
    # The vee drops to 130, not to 280. A shallow M is the classic geometric-sans
    # failure: at 14 px the middle disappears into the two stems and it reads as
    # an H with a thick top.
    mx = (L + R + 110) / 2
    put("M", R + 110 + SIDE,
        rect(L, 0, L + STEM, CAP),
        rect(R + 110 - STEM, 0, R + 110, CAP),
        diag(L, CAP, mx - STEM / 2, 130, STEM),
        mirror(diag(L, CAP, mx - STEM / 2, 130, STEM), mx))
    put("N", adv + 30,
        rect(L, 0, L + STEM, CAP),
        rect(R + 30 - STEM, 0, R + 30, CAP),
        diag(L, CAP, R + 30 - STEM, 0, STEM))
    put("O", adv, ring(L, 0, R, CAP, CH, THIN, THIN))
    put("P", adv,
        rect(L, 0, L + STEM, CAP),
        d_shape(L, CAP / 2 - THIN / 2, R, CAP, CH, THIN))
    put("Q", adv,
        ring(L, 0, R, CAP, CH, THIN, THIN),
        diag(cx + 20, THIN + 20, R - 20, -60, STEM))
    put("R", adv,
        rect(L, 0, L + STEM, CAP),
        d_shape(L, CAP / 2 - THIN / 2, R, CAP, CH, THIN),
        diag(L + STEM - 10, CAP / 2 + 40, R - STEM, 0, STEM))
    put("S", adv, s_shape(L, 0, R, CAP, THIN))
    put("T", adv,
        rect(L, CAP - THIN, R, CAP),
        rect(cx - STEM / 2, 0, cx + STEM / 2, CAP))
    put("U", adv, u_shape(L, 0, R, CAP, CH, THIN))
    put("V", adv,
        diag(cx - STEM / 2, 0, L, CAP, STEM),
        mirror(diag(cx - STEM / 2, 0, L, CAP, STEM), cx))
    put("W", R + 190 + SIDE,
        diag(L + 130, 0, L, CAP, STEM),
        diag(L + 130, 0, L + 250, CAP, STEM),
        mirror(diag(L + 130, 0, L, CAP, STEM), (L + R + 190) / 2),
        mirror(diag(L + 130, 0, L + 250, CAP, STEM), (L + R + 190) / 2))
    put("X", adv,
        diag(L, 0, R - STEM, CAP, STEM),
        diag(R - STEM, 0, L, CAP, STEM))
    put("Y", adv,
        diag(L, CAP, cx - STEM / 2, CAP - 360, STEM),
        mirror(diag(L, CAP, cx - STEM / 2, CAP - 360, STEM), cx),
        rect(cx - STEM / 2, 0, cx + STEM / 2, CAP - 300))
    put("Z", adv,
        rect(L, CAP - THIN, R, CAP),
        diag(L, THIN, R - STEM, CAP - THIN, STEM),
        rect(L, 0, R, THIN))

    # ---- lowercase -------------------------------------------------------
    # A single-storey design: `a` and `g` are one bowl each. Two-storey forms
    # need curves that a straight-contour face cannot make convincingly, and a
    # hard-cornered double-storey `a` reads as a typo at 14 px.
    AS = 720           # ascender
    DS = -190          # descender
    w = 400
    r = L + w
    cxl = (L + r) / 2
    advl = r + SIDE

    put("a", advl,
        ring(L, 0, r, XH, CHX, THIN, THIN),
        rect(r - STEM, 0, r, XH))
    put("b", advl,
        rect(L, 0, L + STEM, AS),
        ring(L, 0, r, XH, CHX, THIN, THIN))
    put("c", advl, c_shape(L, 0, r, XH, CHX, THIN))
    put("d", advl,
        rect(r - STEM, 0, r, AS),
        ring(L, 0, r, XH, CHX, THIN, THIN))
    put("e", advl,
        c_shape(L, 0, r, XH, CHX, THIN),
        rect(L, XH / 2 - THIN / 2, r, XH / 2 + THIN / 2))
    put("f", 300 + SIDE,
        rect(110, 0, 110 + STEM, AS - CHX),
        poly((110, AS - CHX), (110 + CHX, AS), (300, AS), (300, AS - THIN),
             (110 + STEM, AS - THIN), (110 + STEM, AS - CHX)),
        rect(30, XH - THIN, 300, XH))
    put("g", advl,
        ring(L, 0, r, XH, CHX, THIN, THIN),
        rect(r - STEM, DS, r, XH),
        rect(L, DS, r, DS + THIN))
    put("h", advl,
        rect(L, 0, L + STEM, AS),
        n_shape(L, 0, r, XH, CHX, THIN))
    put("i", 2 * SIDE + STEM,
        rect(L, 0, L + STEM, XH),
        rect(L, XH + 70, L + STEM, XH + 70 + STEM))
    put("j", 2 * SIDE + STEM + 60,
        rect(L + 60, DS + THIN, L + 60 + STEM, XH),
        rect(L, DS, L + 60 + STEM, DS + THIN),
        rect(L + 60, XH + 70, L + 60 + STEM, XH + 70 + STEM))
    put("k", advl,
        rect(L, 0, L + STEM, AS),
        diag(L + STEM - 10, XH / 2 - 50, r - STEM, XH, STEM),
        diag(r - STEM, 0, L + STEM - 10, XH / 2 + 50, STEM))
    put("l", 2 * SIDE + STEM, rect(L, 0, L + STEM, AS))
    put("m", r + 300 + SIDE,
        rect(L, 0, L + STEM, XH),
        n_shape(L, 0, L + 300, XH, CHX, THIN),
        n_shape(L + 300 - STEM, 0, r + 300, XH, CHX, THIN))
    put("n", advl,
        rect(L, 0, L + STEM, XH),
        n_shape(L, 0, r, XH, CHX, THIN))
    put("o", advl, ring(L, 0, r, XH, CHX, THIN, THIN))
    put("p", advl,
        rect(L, DS, L + STEM, XH),
        ring(L, 0, r, XH, CHX, THIN, THIN))
    put("q", advl,
        rect(r - STEM, DS, r, XH),
        ring(L, 0, r, XH, CHX, THIN, THIN))
    put("r", 320 + SIDE,
        rect(L, 0, L + STEM, XH),
        poly((L + STEM, XH - THIN), (L + STEM, XH), (320, XH),
             (320, XH - CHX), (320 - CHX, XH - THIN)))
    put("s", advl, s_shape(L, 0, r, XH, THIN))
    put("t", 320 + SIDE,
        rect(130, 0, 130 + STEM, AS - 120),
        rect(30, XH - THIN, 320, XH),
        rect(130, 0, 320, THIN))
    put("u", advl,
        u_shape(L, 0, r, XH, CHX, THIN),
        rect(r - STEM, 0, r, XH))
    put("v", advl,
        diag(cxl - STEM / 2, 0, L, XH, STEM),
        mirror(diag(cxl - STEM / 2, 0, L, XH, STEM), cxl))
    put("w", r + 190 + SIDE,
        diag(L + 120, 0, L, XH, STEM),
        diag(L + 120, 0, L + 230, XH, STEM),
        mirror(diag(L + 120, 0, L, XH, STEM), (L + r + 190) / 2),
        mirror(diag(L + 120, 0, L + 230, XH, STEM), (L + r + 190) / 2))
    put("x", advl,
        diag(L, 0, r - STEM, XH, STEM),
        diag(r - STEM, 0, L, XH, STEM))
    put("y", advl,
        diag(L, XH, cxl - STEM / 2 + 40, 0, STEM),
        diag(r - STEM, XH, L + 30, DS, STEM))
    put("z", advl,
        rect(L, XH - THIN, r, XH),
        diag(L, THIN, r - STEM, XH - THIN, STEM),
        rect(L, 0, r, THIN))


    # ---- punctuation -----------------------------------------------------
    # U+0020-U+007E is shipped whole, including the ten characters no string in
    # the game currently uses. They cost a few hundred bytes each and they
    # remove a whole class of future bug: the first time someone interpolates a
    # save file name or writes an achievement with an exclamation mark, the
    # glyph is already there instead of a .notdef box.
    DOT = 116
    pw = DOT + 2 * SIDE

    put(".", pw, oct_box(L, 0, L + DOT, DOT, 30))
    put(",", pw,
        oct_box(L, 0, L + DOT, DOT, 30),
        poly((L + 14, -130), (L, 0), (L + DOT, 0), (L + DOT - 10, 0)))
    put(":", pw,
        oct_box(L, 0, L + DOT, DOT, 30),
        oct_box(L, XH - DOT, L + DOT, XH, 30))
    put(";", pw,
        oct_box(L, XH - DOT, L + DOT, XH, 30),
        oct_box(L, 0, L + DOT, DOT, 30),
        poly((L + 14, -130), (L, 0), (L + DOT, 0), (L + DOT - 10, 0)))
    put("!", pw,
        rect(L, DOT + 70, L + DOT, CAP),
        oct_box(L, 0, L + DOT, DOT, 30))
    put("?", 420 + SIDE,
        rect(L, CAP - THIN, 420, CAP),
        rect(420 - THIN, CAP / 2, 420, CAP),
        rect(L + 140, CAP / 2 - THIN, 420, CAP / 2),
        rect(L + 140, DOT + 60, L + 140 + THIN, CAP / 2),
        oct_box(L + 140, 0, L + 140 + DOT, DOT, 30))
    put("'", 2 * SIDE + 90, rect(L, CAP - 210, L + 90, CAP))
    put('"', 2 * SIDE + 250,
        rect(L, CAP - 210, L + 90, CAP),
        rect(L + 160, CAP - 210, L + 250, CAP))
    put("(", 260 + SIDE,
        poly((190, DESCENDER + 40), (90, 200), (90, CAP - 200), (190, CAP + 40),
             (190 + THIN, CAP + 40), (90 + THIN, CAP - 200), (90 + THIN, 200),
             (190 + THIN, DESCENDER + 40)))
    put(")", 260 + SIDE,
        mirror([(190, DESCENDER + 40), (90, 200), (90, CAP - 200),
                (190, CAP + 40), (190 + THIN, CAP + 40), (90 + THIN, CAP - 200),
                (90 + THIN, 200), (190 + THIN, DESCENDER + 40)], 200))
    put("[", 260 + SIDE,
        rect(90, DESCENDER + 40, 90 + THIN, CAP + 40),
        rect(90, DESCENDER + 40, 250, DESCENDER + 40 + THIN),
        rect(90, CAP + 40 - THIN, 250, CAP + 40))
    put("]", 260 + SIDE,
        rect(250 - THIN, DESCENDER + 40, 250, CAP + 40),
        rect(90, DESCENDER + 40, 250, DESCENDER + 40 + THIN),
        rect(90, CAP + 40 - THIN, 250, CAP + 40))
    put("{", 300 + SIDE,
        rect(150, DESCENDER + 40, 150 + THIN, CAP + 40),
        rect(70, CAP / 2 - THIN / 2, 150 + THIN, CAP / 2 + THIN / 2),
        rect(150, CAP + 40 - THIN, 290, CAP + 40),
        rect(150, DESCENDER + 40, 290, DESCENDER + 40 + THIN))
    put("}", 300 + SIDE,
        rect(210 - THIN, DESCENDER + 40, 210, CAP + 40),
        rect(210 - THIN, CAP / 2 - THIN / 2, 290, CAP / 2 + THIN / 2),
        rect(70, CAP + 40 - THIN, 210, CAP + 40),
        rect(70, DESCENDER + 40, 210, DESCENDER + 40 + THIN))
    put("<", 420 + SIDE,
        diag(90, XH / 2, 380, XH + 100, THIN),
        diag(90, XH / 2, 380, XH / 2 - (XH / 2 + 100 - XH / 2), THIN))
    put(">", 420 + SIDE,
        mirror(diag(90, XH / 2, 380, XH + 100, THIN), 235),
        mirror(diag(90, XH / 2, 380, XH / 2 - (XH / 2 + 100 - XH / 2), THIN), 235))
    put("/", 380 + SIDE, diag(60, -60, 300, CAP + 40, STEM))
    put("\\", 380 + SIDE, mirror(diag(60, -60, 300, CAP + 40, STEM), 250))
    put("|", 2 * SIDE + STEM, rect(L, DESCENDER, L + STEM, CAP + 60))
    put("-", 340 + SIDE, rect(60, XH / 2 - THIN / 2, 340, XH / 2 + THIN / 2))
    put("_", 460 + SIDE, rect(20, DESCENDER + 40, 460, DESCENDER + 40 + THIN))
    put("=", 400 + SIDE,
        rect(60, XH / 2 + 30, 400, XH / 2 + 30 + THIN),
        rect(60, XH / 2 - 130, 400, XH / 2 - 130 + THIN))
    put("+", 460 + SIDE,
        rect(60, XH / 2 - THIN / 2, 460, XH / 2 + THIN / 2),
        rect(260 - THIN / 2, XH / 2 - 200, 260 + THIN / 2, XH / 2 + 200))
    put("*", 400 + SIDE,
        rect(230 - THIN / 2, CAP - 320, 230 + THIN / 2, CAP),
        diag(100, CAP - 280, 330, CAP - 60, THIN * 0.8),
        mirror(diag(100, CAP - 280, 330, CAP - 60, THIN * 0.8), 230))
    put("#", 520 + SIDE,
        rect(150, 0, 150 + THIN, CAP),
        rect(330, 0, 330 + THIN, CAP),
        rect(50, CAP / 2 + 40, 520, CAP / 2 + 40 + THIN),
        rect(50, CAP / 2 - 160, 520, CAP / 2 - 160 + THIN))
    put("$", adv,
        s_shape(L, 40, R, CAP - 40, THIN),
        rect(cx - STEM / 2, -30, cx + STEM / 2, CAP + 30))
    put("%", 620 + SIDE,
        ring(60, CAP - 260, 280, CAP, 40, 70, 70),
        ring(400, 0, 620, 260, 40, 70, 70),
        diag(150, -20, 430, CAP + 20, THIN))
    # Stylised rather than traditional. A real ampersand is a curve problem, and
    # no string in the game uses one - this exists so a future one is not a box.
    put("&", adv,
        ring(L, CAP / 2 + 20, L + 290, CAP, 60, THIN, THIN),
        c_shape(L, 0, L + 330, CAP / 2 + THIN / 2, CH, THIN),
        diag(L + 150, CAP / 2 - 40, R, CAP - 80, STEM))
    put("@", 680 + SIDE,
        ring(40, 0, 680, CAP, 120, THIN, THIN),
        ring(220, 180, 500, 480, 50, 80, 80),
        rect(500 - 80, 180, 500, CAP / 2))
    put("^", 420 + SIDE,
        diag(60, CAP - 260, 235 - THIN / 2, CAP, THIN),
        mirror(diag(60, CAP - 260, 235 - THIN / 2, CAP, THIN), 235))
    put("~", 460 + SIDE,
        poly((60, XH / 2 - 20), (170, XH / 2 + 90), (290, XH / 2 - 20),
             (400, XH / 2 + 90), (400, XH / 2 + 90 - THIN),
             (290, XH / 2 - 20 - THIN), (170, XH / 2 + 90 - THIN),
             (60, XH / 2 - 20 - THIN)))
    put("`", 2 * SIDE + 150, diag(L, CAP - 90, L + 110, CAP, 80))

    # ---- the non-ASCII characters the UI actually uses -------------------
    # All five were found by scanning every .gd and .tscn string. U+00B7 is the
    # easy one to miss: hud.gd writes it as the escape "\u00b7" inside
    # "GREENWOOD  \u00b7  DEPTH 1", so grepping for the character finds nothing.
    put("\u00b7", pw, oct_box(L, XH / 2 - DOT / 2, L + DOT, XH / 2 + DOT / 2, 30))
    put("\u00d7", 420 + SIDE,
        diag(90, XH / 2 - 150, 330, XH / 2 + 150, THIN * 0.9),
        mirror(diag(90, XH / 2 - 150, 330, XH / 2 + 150, THIN * 0.9), 235))
    put("\u2014", 700 + SIDE, rect(20, XH / 2 - THIN / 2, 700, XH / 2 + THIN / 2))
    put("\u2013", 440 + SIDE, rect(20, XH / 2 - THIN / 2, 440, XH / 2 + THIN / 2))
    put("\u2026", 3 * DOT + 2 * 90 + 2 * SIDE,
        oct_box(L, 0, L + DOT, DOT, 30),
        oct_box(L + DOT + 90, 0, L + 2 * DOT + 90, DOT, 30),
        oct_box(L + 2 * DOT + 180, 0, L + 3 * DOT + 180, DOT, 30))
    # The essence mark. A four-pointed star with concave flanks, so it reads as
    # a spark rather than as a plus sign at 14 px.
    put("\u2726", 520 + SIDE,
        poly((290, CAP), (350, 430), (520, 370), (350, 310), (290, -60),
             (230, 310), (60, 370), (230, 430)))
    put("\u2019", 2 * SIDE + 90,
        poly((L, CAP - 210), (L, CAP), (L + 90, CAP), (L + 90, CAP - 150)))
    put("\u2022", 300 + SIDE,
        oct_box(80, XH / 2 - 90, 260, XH / 2 + 90, 55))
    put("\u00a9", 700 + SIDE,
        ring(40, 0, 700, CAP, 130, THIN, THIN),
        c_shape(210, 180, 530, CAP - 180, 60, 80))

    return g


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------
def build(path: Path) -> dict:
    data = glyphs()
    order = [".notdef"] + [_name(ch) for ch in data]
    cmap = {ord(ch): _name(ch) for ch in data}

    fb = FontBuilder(UPM, isTTF=True)
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap(cmap)

    pen_glyphs = {".notdef": _pen([rect(80, 0, 420, CAP),
                                   list(reversed(rect(160, 80, 340, CAP - 80)))])}
    metrics = {".notdef": (500, 80)}
    for ch, (adv, contours) in data.items():
        name = _name(ch)
        pen_glyphs[name] = _pen(contours)
        lsb = min((x for c in contours for (x, _y) in c), default=0)
        metrics[name] = (adv, lsb)

    fb.setupGlyf(pen_glyphs)
    fb.setupHorizontalMetrics(metrics)
    fb.setupHorizontalHeader(ascent=ASCENDER, descent=DESCENDER, lineGap=0)
    fb.setupNameTable({
        "familyName": "Slimer",
        "styleName": "Regular",
        "uniqueFontIdentifier": "Slimer-Regular-1.0",
        "fullName": "Slimer Regular",
        "psName": "Slimer-Regular",
        "version": "Version 1.0",
        "copyright": "Copyright Tanav Yedlapalli. Generated by tools/font.py.",
    })
    fb.setupOS2(sTypoAscender=ASCENDER, sTypoDescender=DESCENDER,
                sCapHeight=CAP, sxHeight=XH, usWeightClass=500)
    fb.setupPost()

    # Pin the timestamps. fontTools stamps head.created with the current time
    # and, on save, rewrites head.modified to "now" as well - so regenerating
    # identical letterforms produced a different binary every run. That broke
    # the claim LICENSE-ASSETS.md makes about every asset here ("re-running them
    # reproduces the exact art the game ships with") and left a spurious diff in
    # git for anyone who ran gen_art.py and changed nothing.
    fb.font["head"].created = FONT_EPOCH
    fb.font["head"].modified = FONT_EPOCH
    fb.font.recalcTimestamp = False

    path.parent.mkdir(parents=True, exist_ok=True)
    fb.save(str(path))
    return data


def _pen(contours: list):
    pen = TTGlyphPen(None)
    for contour in contours:
        if len(contour) < 3:
            continue
        pen.moveTo(contour[0])
        for pt in contour[1:]:
            pen.lineTo(pt)
        pen.closePath()
    return pen.glyph()


def _name(ch: str) -> str:
    """A PostScript-safe glyph name. Only uniXXXX is guaranteed collision-free."""
    if ch == " ":
        return "space"
    return "uni%04X" % ord(ch)


def main() -> None:
    path = OUT / "slimer.ttf"
    data = build(path)
    kb = path.stat().st_size / 1024
    print(f"  font: {len(data)} glyphs, {kb:.1f} KB -> "
          f"{path.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
