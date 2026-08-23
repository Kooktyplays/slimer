#!/usr/bin/env python3
"""Author every sprite the GDQuest pack doesn't provide, in the pack's style.

The pack is flat vector: no outlines, 2-3 tones per object, a lighter
top-lit region, occasionally one small highlight dot. Everything here is drawn
at 4x and downsampled with LANCZOS to get the same soft antialiased edges.

Outputs to assets/sprites/gen/. Deterministic - safe to re-run.
"""
from __future__ import annotations

import colorsys
import math
import random
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "sprites"
OUT = SPRITES / "gen"
SS = 4  # supersample factor


# --------------------------------------------------------------------------
# palette - sampled from the pack so new art sits beside it without clashing
# --------------------------------------------------------------------------
class C:
    # foliage
    LEAF_D = (43, 104, 56)
    LEAF_M = (48, 149, 64)
    LEAF_L = (74, 182, 86)
    LEAF_XL = (116, 206, 108)
    # bark / wood
    BARK_D = (112, 76, 47)
    BARK_M = (152, 106, 66)
    BARK_L = (204, 152, 105)
    # stone
    ROCK_D = (84, 92, 106)
    ROCK_M = (118, 127, 142)
    ROCK_L = (156, 165, 180)
    # water
    WATER_D = (40, 118, 168)
    WATER_M = (58, 148, 201)
    WATER_L = (96, 190, 231)
    # misc
    GOLD_D = (214, 149, 26)
    GOLD_M = (247, 190, 47)
    GOLD_L = (255, 226, 122)
    BONE = (232, 226, 205)
    WHITE = (255, 255, 255)
    SHADOW = (0, 0, 0)
    ESSENCE_D = (98, 62, 178)
    ESSENCE_M = (146, 102, 234)
    ESSENCE_L = (196, 166, 255)


# --------------------------------------------------------------------------
# drawing helpers
# --------------------------------------------------------------------------
class Art:
    """A supersampled RGBA canvas with flat-vector shading helpers."""

    def __init__(self, w: int, h: int):
        self.w, self.h = w, h
        self.img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.img)

    # -- primitives (coordinates in final-resolution pixels) ---------------
    def ellipse(self, cx, cy, rx, ry, fill):
        self.d.ellipse(
            [(cx - rx) * SS, (cy - ry) * SS, (cx + rx) * SS, (cy + ry) * SS], fill=fill
        )

    def circle(self, cx, cy, r, fill):
        self.ellipse(cx, cy, r, r, fill)

    def poly(self, pts, fill):
        self.d.polygon([(x * SS, y * SS) for x, y in pts], fill=fill)

    def rrect(self, x0, y0, x1, y1, r, fill):
        self.d.rounded_rectangle(
            [x0 * SS, y0 * SS, x1 * SS, y1 * SS], radius=r * SS, fill=fill
        )

    def line(self, pts, fill, width):
        self.d.line([(x * SS, y * SS) for x, y in pts], fill=fill, width=int(width * SS),
                    joint="curve")

    def blob(self, cx, cy, rx, ry, fill, wobble=0.0, points=72, seed=0):
        """An organic near-ellipse - the pack's default silhouette.

        Radius is the base ellipse perturbed by a few low-frequency harmonics
        with random phase, normalised so it stays within +/- `wobble`.
        """
        rng = random.Random(seed)
        harmonics = [
            (rng.randint(2, 4), rng.uniform(0, 2 * math.pi), rng.uniform(0.5, 1.0))
            for _ in range(3)
        ]
        norm = sum(amp for _, _, amp in harmonics) or 1.0
        pts = []
        for i in range(points):
            a = 2 * math.pi * i / points
            k = sum(amp * math.cos(freq * a + ph) for freq, ph, amp in harmonics) / norm
            r = 1.0 + k * wobble
            pts.append((cx + math.cos(a) * rx * r, cy + math.sin(a) * ry * r))
        self.poly(pts, fill)

    # -- shading -----------------------------------------------------------
    def light(self, shape_fn, color):
        """Paint `color` only where `shape_fn` overlaps what's already drawn.

        This is how every object here gets its top-lit region: draw the full
        silhouette in the mid tone, then wash a big light shape over it that
        gets clipped to the silhouette automatically.
        """
        layer = Image.new("RGBA", self.img.size, (0, 0, 0, 0))
        sub = Art.__new__(Art)
        sub.w, sub.h, sub.img = self.w, self.h, layer
        sub.d = ImageDraw.Draw(layer)
        shape_fn(sub, color)
        mask = ImageChops.multiply(self.img.getchannel("A"), layer.getchannel("A"))
        self.img.paste(layer, (0, 0), mask)

    def top_light(self, color, cut=0.45, skew=-0.10):
        """Standard upper-body light wash."""
        y = self.h * cut
        self.light(
            lambda a, c: a.ellipse(
                self.w * (0.5 + skew), y - self.h * 0.30, self.w * 0.62, self.h * 0.58, c
            ),
            color,
        )

    def dot(self, cx, cy, r, color=C.WHITE, alpha=210):
        self.circle(cx, cy, r, (*color, alpha))

    # -- output ------------------------------------------------------------
    def finish(self) -> Image.Image:
        return self.img.resize((self.w, self.h), Image.LANCZOS)

    def save(self, name: str):
        img = self.finish()
        OUT.mkdir(parents=True, exist_ok=True)
        img.save(OUT / name)
        return img


def ground_shadow(a: Art, cx, cy, rx, ry, alpha=52):
    a.ellipse(cx, cy, rx, ry, (0, 0, 0, alpha))


# --------------------------------------------------------------------------
# 0. originals replacing the GDQuest pack sources
# --------------------------------------------------------------------------
# Everything in this section exists so the game owns its whole art set.
#
# Slimer shipped using thirteen sprites from GDQuest's starter pack, which are
# CC BY-NC-SA 4.0 - free to share, and specifically not sellable. That single
# fact, not the Steam pipeline, is what blocked a paid release: the code is MIT
# and every other sprite here was already original.
#
# These are authored in the same flat-vector idiom as the rest of this file so
# they sit beside the ~180 sprites already generated here: no outlines, two or
# three tones per object, one top-lit region, the occasional highlight dot.
# Dimensions match the files they replace exactly, so scene offsets, hitbox
# constants and anchor points all stay valid.


class P:
    """Palette for the replaced sprites."""

    # slime: the source all six enemy colours are hue-rotated from, so its
    # relative shading has to be strong enough to survive the rotation
    SLIME_D = (58, 150, 30)
    SLIME_M = (92, 205, 39)
    SLIME_L = (153, 241, 65)
    SLIME_XL = (208, 255, 132)
    EYE = (26, 58, 30)
    # player
    GHOST_D = (196, 208, 224)
    GHOST_M = (232, 240, 250)
    GHOST_L = (255, 255, 255)
    GHOST_EYE = (38, 44, 62)
    # gun
    STEEL_D = (68, 74, 88)
    STEEL_M = (104, 112, 130)
    STEEL_L = (150, 160, 180)
    GRIP_D = (86, 58, 38)
    GRIP_M = (124, 84, 54)
    # shot
    SHOT_CORE = (255, 250, 214)
    SHOT_MID = (255, 214, 108)
    SHOT_EDGE = (250, 166, 44)
    # pine
    PINE_D = (28, 84, 58)
    PINE_M = (38, 116, 74)
    PINE_L = (58, 152, 92)


def gen_slime_body():
    """The slime every enemy colour is derived from.

    Hue-rotated into six colours by gen_enemies(), so the shading has to read
    as shading rather than as hue - hence four tones with real value contrast
    between them, and highlights that stay light after the rotation.
    """
    a = Art(108, 90)
    # Fills the canvas edge to edge, because the sprite this replaces did. Every
    # offset tuned against it - the elite crown at y=-34, the face at y=-6, the
    # hit radii in EnemyTypes - is relative to this frame, so a silhouette that
    # sits smaller inside the same canvas leaves the crown floating above the
    # slime's head and the face riding high on its body.
    a.blob(54, 52, 54, 38, (*P.SLIME_M, 255), wobble=0.04, seed=11)
    a.ellipse(54, 34, 45, 34, (*P.SLIME_M, 255))     # dome, up to the top edge
    a.ellipse(54, 68, 53, 22, (*P.SLIME_M, 255))     # base, down to the bottom
    # the base darkens where it meets the ground
    a.light(lambda s, c: s.ellipse(54, 96, 58, 30, c), (*P.SLIME_D, 255))
    # top-lit dome
    a.light(lambda s, c: s.ellipse(46, 20, 44, 34, c), (*P.SLIME_L, 255))
    a.light(lambda s, c: s.ellipse(40, 10, 26, 20, c), (*P.SLIME_XL, 255))
    # One soft specular, clipped to the dome. dot() paints unclipped, so a
    # highlight placed near the top edge hangs off the silhouette and reads as a
    # bubble stuck to the slime; light() masks to what is already drawn.
    a.light(lambda s, c: s.ellipse(38, 18, 17, 11, c), (255, 255, 255, 110))
    a.light(lambda s, c: s.ellipse(34, 15, 7, 5, c), (255, 255, 255, 200))
    a.save("slime_body.png")


def gen_slime_face():
    """Default slime eyes: two soft dark ovals."""
    a = Art(56, 28)
    a.ellipse(14, 14, 7, 9, (*P.EYE, 255))
    a.ellipse(42, 14, 7, 9, (*P.EYE, 255))
    a.dot(16, 10, 2.4, C.WHITE, 210)
    a.dot(44, 10, 2.4, C.WHITE, 210)
    a.save("slime_face.png")


def gen_player_body():
    """The player: a small round spirit, deliberately not slime-shaped.

    Pale and cool against a forest of warm greens, because the one thing the
    player must never lose track of in a crowd is themselves.
    """
    a = Art(84, 73)
    # Full-bleed for the same reason as the slime: the face offset in
    # player.tscn is relative to this frame.
    a.blob(42, 34, 42, 34, (*P.GHOST_M, 255), wobble=0.03, seed=7)
    # a wavy hem rather than a flat bottom, so it reads as floating
    for i in range(4):
        x = 12 + i * 20.0
        a.ellipse(x, 64, 12, 9, (*P.GHOST_M, 255))
    a.light(lambda s, c: s.ellipse(42, 78, 44, 20, c), (*P.GHOST_D, 255))
    a.light(lambda s, c: s.ellipse(34, 10, 30, 24, c), (*P.GHOST_L, 255))
    a.light(lambda s, c: s.ellipse(26, 12, 7, 6, c), (255, 255, 255, 255))
    a.save("boo_body.png")


def gen_player_face():
    a = Art(48, 25)
    a.ellipse(13, 12, 6, 8, (*P.GHOST_EYE, 255))
    a.ellipse(35, 12, 6, 8, (*P.GHOST_EYE, 255))
    a.dot(15, 9, 2.2, C.WHITE, 230)
    a.dot(37, 9, 2.2, C.WHITE, 230)
    a.save("boo_face.png")


def gen_pistol():
    """Side-on sidearm, muzzle to the right - the scene rotates it to aim."""
    a = Art(70, 50)
    # Grip first and raked back, so the silhouette reads as a pistol at the size
    # it is actually drawn - a vertical stub under a bar reads as a hammer.
    a.poly([(10, 20), (24, 20), (20, 46), (6, 46)], (*P.GRIP_M, 255))
    a.poly([(10, 20), (24, 20), (22, 32), (8, 32)], (*P.GRIP_D, 255))
    a.rrect(4, 13, 50, 27, 5, (*P.STEEL_M, 255))      # slide
    a.rrect(44, 16, 66, 24, 4, (*P.STEEL_M, 255))     # barrel
    a.rrect(24, 26, 34, 33, 2, (*P.STEEL_D, 255))     # trigger guard stub
    a.light(lambda s, c: s.rrect(2, 9, 66, 19, 4, c), (*P.STEEL_L, 255))
    a.light(lambda s, c: s.rrect(2, 23, 66, 34, 4, c), (*P.STEEL_D, 255))
    a.light(lambda s, c: s.circle(12, 16, 2.5, c), (255, 255, 255, 170))
    a.save("pistol.png")


def gen_bullet():
    """Bullet: a bright lozenge with a warm trail, pointing right."""
    a = Art(50, 28)
    # A soft tail that tapers back, so the shot reads as travelling rather than
    # as a floating dot, with the bright core running along the axis instead of
    # sitting on it as a highlight blob.
    a.poly([(4, 14), (22, 9), (22, 19)], (*P.SHOT_EDGE, 150))
    a.ellipse(28, 14, 18, 8, (*P.SHOT_EDGE, 255))
    a.ellipse(30, 14, 13, 5.5, (*P.SHOT_MID, 255))
    a.ellipse(32, 14, 8, 3.2, (*P.SHOT_CORE, 255))
    a.save("projectile.png")


def gen_muzzle_flash():
    """Four-point star, brightest at the centre."""
    a = Art(32, 32)
    a.poly([(16, 0), (21, 12), (32, 16), (21, 20), (16, 32),
            (11, 20), (0, 16), (11, 12)], (*P.SHOT_EDGE, 235))
    a.poly([(16, 5), (19, 13), (27, 16), (19, 19), (16, 27),
            (13, 19), (5, 16), (13, 13)], (*P.SHOT_MID, 245))
    a.circle(16, 16, 5, (*P.SHOT_CORE, 255))
    a.save("muzzle_flash.png")


def gen_impact_circle():
    """Impact puff. Tinted per hit type at runtime, so this is white."""
    a = Art(64, 64)
    a.circle(32, 32, 30, (255, 255, 255, 70))
    a.circle(32, 32, 22, (255, 255, 255, 130))
    a.circle(32, 32, 13, (255, 255, 255, 225))
    a.save("impact_circle.png")


def gen_pine_tree():
    """Conifer: three stacked skirts over a short trunk."""
    a = Art(128, 152)
    ground_shadow(a, 64, 144, 28, 8)
    # Trunk first and short, so the skirts cover all of it but the base - it
    # used to be drawn tall and showed through the gaps between tiers.
    a.rrect(59, 124, 69, 147, 3, (*C.BARK_D, 255))
    a.rrect(59, 124, 64, 147, 3, (*C.BARK_M, 255))
    # Overlapping skirts, widest at the bottom, each seated on the one below.
    tiers = [(134, 59), (106, 50), (79, 40), (54, 29)]
    for y, half in tiers:
        a.poly([(64 - half, y), (64 + half, y), (64, y - 48)], (*P.PINE_M, 255))
    a.light(lambda s, c: s.ellipse(42, 46, 38, 70, c), (*P.PINE_L, 255))
    a.light(lambda s, c: s.ellipse(98, 122, 40, 48, c), (*P.PINE_D, 255))
    a.save("pine_tree.png")


def gen_ground_shadow():
    """The soft ellipse under every actor.

    Three stacked ellipses rather than a blur: it downsamples to the same soft
    edge and stays deterministic.
    """
    a = Art(84, 52)
    a.ellipse(42, 26, 41, 25, (0, 0, 0, 38))
    a.ellipse(42, 26, 34, 20, (0, 0, 0, 52))
    a.ellipse(42, 26, 25, 14, (0, 0, 0, 64))
    a.save("ground_shadow.png")


def gen_original_potions():
    """Potions, authored rather than sliced out of the pack's 3x3 sheets.

    Drawn at 32px, matching what the old slice-and-scale produced, so
    Pickup.POTION_SCALE still lands where it was tuned.
    """
    fills = {
        "red": ((196, 48, 62), (238, 92, 104), (255, 158, 166)),
        "blue": ((34, 106, 190), (62, 152, 238), (140, 202, 255)),
        "purple": ((112, 54, 178), (156, 92, 232), (206, 166, 255)),
        "green": ((46, 142, 62), (78, 190, 90), (150, 232, 150)),
        "yellow": ((198, 152, 26), (240, 196, 52), (255, 232, 140)),
    }
    for name, (dark, mid, light) in fills.items():
        a = Art(32, 32)
        # cork and neck
        a.rrect(13, 2, 19, 8, 2, (*C.BARK_M, 255))
        a.rrect(14, 7, 18, 12, 1, (168, 172, 180, 255))
        # round flask
        a.circle(16, 21, 10, (*dark, 255))
        a.circle(16, 21, 9, (*mid, 255))
        # liquid line and a lit shoulder
        a.ellipse(16, 17, 8, 3, (*light, 200))
        a.light(lambda s, c: s.ellipse(11, 14, 7, 8, c), (*light, 255))
        a.light(lambda s, c: s.ellipse(11.5, 16, 2.4, 3.2, c), (255, 255, 255, 220))
        a.save(f"potion_{name}.png")


# --------------------------------------------------------------------------
# 1. enemy recolours - hue-rotate the base slime so shading survives intact
# --------------------------------------------------------------------------
# source slime tones: (92,205,39) mid, (153,241,65) light, (208,255,132) hi
SRC_HUE = colorsys.rgb_to_hsv(92 / 255, 205 / 255, 39 / 255)[0]

# name -> (target hue deg, saturation mul, value mul)
ENEMY_TINTS = {
    "green":  (101, 1.00, 1.00),
    "red":    (357, 1.00, 0.94),
    "blue":   (207, 0.96, 1.02),
    "yellow": (46,  1.00, 1.06),
    "purple": (280, 0.90, 0.98),
    "orange": (24,  1.02, 1.02),
}


def recolor(src: Image.Image, hue_deg: float, sat_mul: float, val_mul: float) -> Image.Image:
    """Rotate hue to an absolute target, preserving relative shading."""
    src = src.convert("RGBA")
    px = src.load()
    out = Image.new("RGBA", src.size)
    opx = out.load()
    delta = (hue_deg / 360.0) - SRC_HUE
    for y in range(src.height):
        for x in range(src.width):
            r, g, b, al = px[x, y]
            if al == 0:
                opx[x, y] = (0, 0, 0, 0)
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            h = (h + delta) % 1.0
            s = min(1.0, s * sat_mul)
            v = min(1.0, v * val_mul)
            nr, ng, nb = colorsys.hsv_to_rgb(h, s, v)
            opx[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), al)
    return out


def gen_enemies():
    # Reads the slime authored above, in OUT, not the pack file in SPRITES.
    body = Image.open(OUT / "slime_body.png")
    OUT.mkdir(parents=True, exist_ok=True)
    for name, (hue, sm, vm) in ENEMY_TINTS.items():
        recolor(body, hue, sm, vm).save(OUT / f"enemy_{name}_body.png")

    # elite trim: a spiky crown ring drawn over the body silhouette
    for name, (hue, sm, vm) in ENEMY_TINTS.items():
        a = Art(108, 90)
        rr, gg, bb = colorsys.hsv_to_rgb(hue / 360.0, min(1.0, 0.55 * sm), 1.0)
        col = (round(rr * 255), round(gg * 255), round(bb * 255))
        for i in range(7):
            x = 16 + i * 12.6
            a.poly([(x - 6, 30), (x, 8), (x + 6, 30)], (*C.GOLD_M, 255))
            a.poly([(x - 3, 26), (x, 14), (x + 3, 26)], (*C.GOLD_L, 255))
        a.rrect(12, 26, 96, 36, 5, (*C.GOLD_D, 255))
        a.rrect(12, 26, 96, 31, 3, (*C.GOLD_M, 255))
        a.circle(54, 31, 4, (*col, 255))
        a.save(f"elite_crown_{name}.png")


def gen_faces():
    """Eye variants. The pack face is one dark shape reused across colours."""
    # angry: eyes narrowed into inward-slanting slits
    a = Art(56, 28)
    dark = (26, 58, 30, 255)
    a.poly([(3, 6), (23, 13), (23, 23), (3, 18)], dark)
    a.poly([(53, 6), (33, 13), (33, 23), (53, 18)], dark)
    a.save("eyes_angry.png")

    # dead: X eyes
    a = Art(56, 28)
    col = (26, 58, 30, 255)
    for cx in (13, 43):
        a.line([(cx - 7, 7), (cx + 7, 21)], col, 4)
        a.line([(cx - 7, 21), (cx + 7, 7)], col, 4)
    a.save("eyes_dead.png")

    # boss: glowing slit eyes
    a = Art(56, 28)
    a.poly([(2, 8), (22, 4), (22, 20), (2, 16)], (24, 20, 34, 255))
    a.poly([(54, 8), (34, 4), (34, 20), (54, 16)], (24, 20, 34, 255))
    a.ellipse(12, 12, 4, 5, (255, 232, 120, 255))
    a.ellipse(44, 12, 4, 5, (255, 232, 120, 255))
    a.save("eyes_boss.png")


# --------------------------------------------------------------------------
# 2. forest props
# --------------------------------------------------------------------------
def gen_trees():
    # round deciduous tree, two variants
    for idx, seed in enumerate((7, 23)):
        w, h = 150, 172
        a = Art(w, h)
        ground_shadow(a, w / 2, h - 14, 40, 12)
        # trunk
        a.rrect(w / 2 - 11, h - 74, w / 2 + 11, h - 12, 6, (*C.BARK_M, 255))
        a.rrect(w / 2 - 11, h - 74, w / 2 - 2, h - 12, 5, (*C.BARK_L, 255))
        # canopy: three overlapping blobs
        canopy = Art(w, h)
        rng = random.Random(seed)
        for cx, cy, rx, ry in (
            (w * 0.30, h * 0.42, 40, 36),
            (w * 0.70, h * 0.40, 42, 38),
            (w * 0.50, h * 0.27, 48, 40),
        ):
            canopy.blob(cx, cy + rng.uniform(-3, 3), rx, ry, (*C.LEAF_M, 255),
                        wobble=0.16, seed=seed + int(cx))
        canopy.light(
            lambda s, c: s.blob(w * 0.42, h * 0.20, 46, 32, c, wobble=0.18, seed=seed),
            (*C.LEAF_L, 255),
        )
        canopy.light(lambda s, c: s.blob(w * 0.36, h * 0.14, 26, 16, c, wobble=0.2,
                                         seed=seed + 3), (*C.LEAF_XL, 255))
        a.img.alpha_composite(canopy.img)
        a.save(f"tree_round_{'ab'[idx]}.png")

    # dead / bare tree
    a = Art(120, 156)
    ground_shadow(a, 60, 144, 26, 9)
    a.rrect(52, 62, 68, 148, 6, (*C.BARK_D, 255))
    a.rrect(52, 62, 58, 148, 4, (*C.BARK_M, 255))
    a.line([(60, 84), (32, 52), (24, 26)], (*C.BARK_D, 255), 8)
    a.line([(60, 96), (92, 62), (102, 38)], (*C.BARK_D, 255), 8)
    a.line([(60, 70), (74, 40), (70, 18)], (*C.BARK_D, 255), 6)
    a.line([(32, 52), (16, 44)], (*C.BARK_D, 255), 5)
    a.line([(92, 62), (108, 56)], (*C.BARK_D, 255), 5)
    a.save("tree_dead.png")

    # stump
    a = Art(74, 66)
    ground_shadow(a, 37, 56, 24, 8)
    a.rrect(14, 22, 60, 58, 8, (*C.BARK_M, 255))
    a.ellipse(37, 24, 23, 11, (*C.BARK_L, 255))
    a.ellipse(37, 24, 15, 7, (*C.BARK_M, 255))
    a.ellipse(37, 24, 7, 3, (*C.BARK_L, 255))
    a.save("stump.png")


def gen_bushes():
    for idx, (seed, w, h, tone) in enumerate((
        (11, 82, 64, C.LEAF_M),
        (29, 96, 72, C.LEAF_D),
        (41, 66, 54, C.LEAF_M),
    )):
        a = Art(w, h)
        ground_shadow(a, w / 2, h - 8, w * 0.34, 7)
        rng = random.Random(seed)
        for i in range(4):
            cx = w * (0.24 + 0.17 * i)
            cy = h * (0.52 - 0.10 * abs(i - 1.5))
            a.blob(cx, cy, w * 0.24, h * 0.36, (*tone, 255), wobble=0.18,
                   seed=seed + i)
        light = tuple(min(255, c + 34) for c in tone)
        a.light(lambda s, c: s.blob(w * 0.42, h * 0.26, w * 0.36, h * 0.30, c,
                                    wobble=0.2, seed=seed + 9), (*light, 255))
        if idx == 1:  # berry bush
            for _ in range(5):
                a.circle(rng.uniform(w * 0.2, w * 0.8), rng.uniform(h * 0.4, h * 0.75),
                         3.2, (214, 74, 84, 255))
        a.save(f"bush_{'abc'[idx]}.png")


def gen_rocks():
    specs = ((13, 56, 44), (37, 84, 58), (53, 38, 30))
    for idx, (seed, w, h) in enumerate(specs):
        a = Art(w, h)
        ground_shadow(a, w / 2, h - 6, w * 0.40, 6)
        a.blob(w / 2, h * 0.55, w * 0.44, h * 0.38, (*C.ROCK_M, 255), wobble=0.30,
               seed=seed)
        a.light(lambda s, c: s.blob(w * 0.42, h * 0.32, w * 0.34, h * 0.24, c,
                                    wobble=0.3, seed=seed + 5), (*C.ROCK_L, 255))
        a.save(f"rock_{'abc'[idx]}.png")

    # pebble scatter
    a = Art(54, 30)
    rng = random.Random(91)
    for _ in range(6):
        cx, cy = rng.uniform(8, 46), rng.uniform(12, 24)
        r = rng.uniform(3, 6)
        a.ellipse(cx, cy, r, r * 0.72, (*C.ROCK_M, 255))
        a.ellipse(cx - r * 0.2, cy - r * 0.25, r * 0.6, r * 0.4, (*C.ROCK_L, 255))
    a.save("pebbles.png")


def gen_logs():
    a = Art(136, 56)
    ground_shadow(a, 68, 46, 58, 8)
    a.rrect(8, 14, 128, 44, 14, (*C.BARK_M, 255))
    a.rrect(8, 14, 128, 27, 12, (*C.BARK_L, 255))
    a.ellipse(16, 29, 9, 15, (*C.BARK_D, 255))
    a.ellipse(16, 29, 5, 9, (*C.BARK_L, 255))
    for x in (48, 78, 104):
        a.line([(x, 20), (x + 5, 38)], (*C.BARK_D, 120), 2)
    a.save("log_a.png")

    # mossy log
    a = Art(120, 52)
    ground_shadow(a, 60, 44, 50, 7)
    a.rrect(6, 12, 114, 42, 13, (*C.BARK_D, 255))
    a.rrect(6, 12, 114, 25, 11, (*C.BARK_M, 255))
    for cx in (30, 58, 86):
        a.blob(cx, 16, 15, 7, (*C.LEAF_M, 255), wobble=0.3, seed=cx)
    a.ellipse(14, 27, 8, 14, (*C.BARK_D, 255))
    a.ellipse(14, 27, 4, 8, (*C.BARK_L, 255))
    a.save("log_b.png")


def gen_ground_detail():
    # grass tufts
    for idx, seed in enumerate((3, 19, 61)):
        w, h = 36, 28
        a = Art(w, h)
        rng = random.Random(seed)
        n = rng.randint(5, 7)
        for i in range(n):
            x = 4 + (w - 8) * i / max(1, n - 1) + rng.uniform(-2, 2)
            top = rng.uniform(4, 12)
            lean = rng.uniform(-5, 5)
            tone = C.LEAF_L if i % 2 else C.LEAF_M
            a.poly([(x - 2.4, h - 3), (x + lean, top), (x + 2.4, h - 3)], (*tone, 255))
        a.save(f"grass_{'abc'[idx]}.png")

    # fern
    a = Art(58, 50)
    for ang, ln in ((-62, 24), (-30, 30), (0, 32), (30, 30), (62, 24)):
        ar = math.radians(ang - 90)
        ex, ey = 29 + math.cos(ar) * ln, 46 + math.sin(ar) * ln
        a.line([(29, 46), (ex, ey)], (*C.LEAF_D, 255), 3)
        for t in (0.45, 0.7, 0.9):
            px, py = 29 + (ex - 29) * t, 46 + (ey - 46) * t
            a.ellipse(px, py, 5, 3.2, (*C.LEAF_M, 255))
    a.save("fern.png")

    # flowers
    for idx, petal in enumerate(((252, 220, 90), (236, 130, 190))):
        a = Art(26, 26)
        a.line([(13, 24), (13, 14)], (*C.LEAF_D, 255), 2)
        for i in range(6):
            ang = math.radians(i * 60)
            a.circle(13 + math.cos(ang) * 5, 12 + math.sin(ang) * 5, 4, (*petal, 255))
        a.circle(13, 12, 3.4, (*C.GOLD_M, 255))
        a.save(f"flower_{'ab'[idx]}.png")

    # mushroom cluster
    a = Art(38, 34)
    ground_shadow(a, 19, 30, 12, 4)
    for cx, cy, r in ((12, 20, 7), (25, 17, 9)):
        a.rrect(cx - 2.5, cy, cx + 2.5, 30, 2.5, (*C.BONE, 255))
        a.ellipse(cx, cy, r, r * 0.78, (206, 78, 70, 255))
        a.ellipse(cx - r * 0.25, cy - r * 0.22, r * 0.55, r * 0.35, (232, 118, 106, 255))
        a.dot(cx + r * 0.3, cy - r * 0.1, 1.6, C.WHITE, 235)
    a.save("mushroom.png")

    # reeds (pond edge)
    a = Art(40, 62)
    for x, top in ((10, 20), (20, 8), (30, 24)):
        a.line([(x, 58), (x + 3, top)], (*C.LEAF_D, 255), 3)
        a.rrect(x + 1, top - 8, x + 5, top + 4, 2, (*C.BARK_M, 255))
    a.save("reeds.png")

    # lily pad
    a = Art(46, 34)
    a.ellipse(23, 17, 21, 15, (*C.LEAF_M, 255))
    a.poly([(23, 17), (44, 12), (44, 22)], (0, 0, 0, 0))
    a.d.pieslice([2 * SS, 2 * SS, 44 * SS, 32 * SS], -18, 18, fill=(0, 0, 0, 0))
    a.ellipse(19, 13, 12, 8, (*C.LEAF_L, 255))
    a.save("lilypad.png")


def gen_shop_props():
    """Lantern post that marks the shop/rest clearing."""
    a = Art(72, 108)
    ground_shadow(a, 36, 98, 20, 7)
    a.rrect(32, 40, 40, 100, 4, (*C.BARK_D, 255))
    a.rrect(32, 40, 35, 100, 3, (*C.BARK_M, 255))
    a.poly([(20, 40), (52, 40), (44, 20), (28, 20)], (*C.ROCK_D, 255))
    a.poly([(24, 38), (48, 38), (42, 22), (30, 22)], (255, 226, 140, 255))
    a.circle(36, 30, 6, (255, 248, 208, 255))
    a.poly([(18, 20), (54, 20), (36, 6)], (*C.ROCK_D, 255))
    a.save("shop_lantern.png")

    # campfire (rest phase)
    a = Art(70, 58)
    ground_shadow(a, 35, 48, 22, 7)
    for x0, y0, x1, y1 in ((14, 44, 40, 34), (30, 34, 56, 46), (16, 38, 52, 40)):
        a.line([(x0, y0), (x1, y1)], (*C.BARK_D, 255), 6)
    a.poly([(35, 6), (46, 30), (24, 30)], (250, 148, 44, 255))
    a.poly([(35, 14), (43, 32), (27, 32)], (255, 200, 60, 255))
    a.poly([(35, 22), (40, 33), (30, 33)], (255, 244, 176, 255))
    a.save("campfire.png")


# --------------------------------------------------------------------------
# 3. bosses - unique silhouettes, each with a separate eye layer to animate
# --------------------------------------------------------------------------
def gen_boss_bramble():
    """Mini-boss 1: Bramble Warden - thorny root creature."""
    w, h = 208, 196
    a = Art(w, h)
    ground_shadow(a, w / 2, h - 16, 62, 16)
    # root legs
    for sx in (-1, 1):
        a.line([(w / 2 + sx * 18, h - 66), (w / 2 + sx * 52, h - 34),
                (w / 2 + sx * 62, h - 18)], (*C.BARK_D, 255), 13)
    # body
    a.blob(w / 2, h * 0.50, 62, 56, (*C.BARK_M, 255), wobble=0.14, seed=5)
    a.light(lambda s, c: s.blob(w * 0.44, h * 0.34, 50, 36, c, wobble=0.16, seed=6),
            (*C.BARK_L, 255))
    # thorns around the crown
    for i in range(9):
        ang = math.radians(-172 + i * 18)
        bx, by = w / 2 + math.cos(ang) * 56, h * 0.50 + math.sin(ang) * 50
        tx, ty = w / 2 + math.cos(ang) * 84, h * 0.50 + math.sin(ang) * 76
        px, py = -math.sin(ang) * 9, math.cos(ang) * 9
        a.poly([(bx + px, by + py), (tx, ty), (bx - px, by - py)], (*C.LEAF_D, 255))
    # vine wraps
    for yy in (0.52, 0.64):
        a.line([(w / 2 - 54, h * yy), (w / 2 - 18, h * (yy + 0.04)),
                (w / 2 + 20, h * (yy - 0.02)), (w / 2 + 54, h * (yy + 0.03))],
               (*C.LEAF_M, 255), 7)
    a.save("boss_bramble_body.png")

    a = Art(96, 40)
    a.ellipse(24, 20, 15, 13, (30, 24, 18, 255))
    a.ellipse(72, 20, 15, 13, (30, 24, 18, 255))
    a.ellipse(24, 19, 8, 8, (168, 240, 96, 255))
    a.ellipse(72, 19, 8, 8, (168, 240, 96, 255))
    a.dot(21, 16, 3)
    a.dot(69, 16, 3)
    a.save("boss_bramble_eyes.png")


def gen_boss_toad():
    """Mini-boss 2: Toadfather - bloated toad that spits and spawns adds."""
    w, h = 232, 172
    a = Art(w, h)
    ground_shadow(a, w / 2, h - 14, 76, 16)
    # hind legs
    for sx in (-1, 1):
        a.ellipse(w / 2 + sx * 76, h - 44, 26, 20, (*C.LEAF_D, 255))
        a.ellipse(w / 2 + sx * 88, h - 26, 22, 11, (*C.LEAF_D, 255))
    # body
    a.blob(w / 2, h * 0.56, 92, 62, (*C.LEAF_M, 255), wobble=0.10, seed=17)
    a.light(lambda s, c: s.blob(w * 0.46, h * 0.36, 78, 42, c, wobble=0.12, seed=18),
            (*C.LEAF_L, 255))
    # pale belly
    a.light(lambda s, c: s.ellipse(w / 2, h * 0.80, 58, 28, c), (196, 224, 150, 255))
    # warts
    rng = random.Random(4)
    for _ in range(11):
        ang = rng.uniform(math.pi, 2 * math.pi)
        rr = rng.uniform(0.3, 0.86)
        cx = w / 2 + math.cos(ang) * 82 * rr
        cy = h * 0.56 + math.sin(ang) * 54 * rr
        a.circle(cx, cy, rng.uniform(4, 7), (*C.LEAF_D, 255))
    # eye mounds
    for sx in (-1, 1):
        a.ellipse(w / 2 + sx * 38, h * 0.26, 30, 26, (*C.LEAF_M, 255))
        a.ellipse(w / 2 + sx * 38 - 4, h * 0.22, 22, 16, (*C.LEAF_L, 255))
    a.save("boss_toad_body.png")

    a = Art(160, 56)
    for cx in (34, 126):
        a.ellipse(cx, 28, 21, 21, (250, 246, 226, 255))
        a.ellipse(cx, 28, 11, 17, (238, 176, 40, 255))
        a.ellipse(cx, 28, 5, 15, (26, 22, 18, 255))
        a.dot(cx - 6, 20, 4.5)
    a.save("boss_toad_eyes.png")


def gen_boss_wisp():
    """Mini-boss 3: Wisp Choir - spectral orb cluster, ranged."""
    w, h = 176, 176
    a = Art(w, h)
    a.circle(w / 2, h / 2, 54, (*C.ESSENCE_M, 255))
    a.light(lambda s, c: s.circle(w * 0.42, h * 0.38, 40, c), (*C.ESSENCE_L, 255))
    # tattered veil
    pts = [(w / 2 - 54, h / 2 + 6)]
    for i in range(9):
        x = w / 2 - 54 + i * 13.5
        pts.append((x + 6.75, h / 2 + (46 if i % 2 else 68)))
    pts.append((w / 2 + 54, h / 2 + 6))
    a.poly(pts, (*C.ESSENCE_M, 235))
    # halo orbs
    for i in range(3):
        ang = math.radians(-90 + i * 120)
        a.circle(w / 2 + math.cos(ang) * 68, h / 2 + math.sin(ang) * 68, 13,
                 (*C.ESSENCE_L, 235))
    a.dot(w * 0.36, h * 0.32, 9, C.WHITE, 190)
    a.save("boss_wisp_body.png")

    a = Art(96, 40)
    for cx in (26, 70):
        a.ellipse(cx, 20, 9, 13, (250, 250, 255, 255))
        a.ellipse(cx, 21, 5, 8, (86, 44, 150, 255))
    a.save("boss_wisp_eyes.png")


def gen_boss_oak():
    """Major boss 1: The Ancient Oak - treant with root arms."""
    w, h = 340, 332
    a = Art(w, h)
    ground_shadow(a, w / 2, h - 22, 118, 24)
    # roots
    for sx, off in ((-1, 0), (1, 0), (-1, 30), (1, 30)):
        a.line([(w / 2 + sx * 26, h - 96),
                (w / 2 + sx * (76 + off), h - 56),
                (w / 2 + sx * (104 + off), h - 24)], (*C.BARK_D, 255), 18)
    # trunk
    a.poly([(w / 2 - 56, h - 90), (w / 2 - 74, h * 0.36), (w / 2 + 74, h * 0.36),
            (w / 2 + 56, h - 90)], (*C.BARK_M, 255))
    a.poly([(w / 2 - 56, h - 90), (w / 2 - 74, h * 0.36), (w / 2 - 24, h * 0.36),
            (w / 2 - 20, h - 90)], (*C.BARK_L, 255))
    # bark grooves
    for gx in (-40, -8, 26, 52):
        a.line([(w / 2 + gx, h * 0.42), (w / 2 + gx + 6, h - 100)], (*C.BARK_D, 150), 4)
    # arms
    for sx in (-1, 1):
        a.line([(w / 2 + sx * 62, h * 0.46), (w / 2 + sx * 122, h * 0.40),
                (w / 2 + sx * 146, h * 0.54)], (*C.BARK_D, 255), 20)
        for fy in (0.50, 0.58, 0.66):
            a.line([(w / 2 + sx * 146, h * 0.54), (w / 2 + sx * 162, h * fy)],
                   (*C.BARK_D, 255), 8)
    # canopy
    can = Art(w, h)
    for cx, cy, rx, ry, seed in (
        (0.24, 0.20, 74, 56, 31), (0.76, 0.19, 76, 58, 32),
        (0.50, 0.12, 92, 62, 33), (0.36, 0.28, 62, 46, 34), (0.66, 0.29, 64, 48, 35),
    ):
        can.blob(w * cx, h * cy, rx, ry, (*C.LEAF_D, 255), wobble=0.14, seed=seed)
    can.light(lambda s, c: s.blob(w * 0.44, h * 0.14, 96, 52, c, wobble=0.16, seed=36),
              (*C.LEAF_M, 255))
    can.light(lambda s, c: s.blob(w * 0.36, h * 0.09, 56, 26, c, wobble=0.18, seed=37),
              (*C.LEAF_L, 255))
    a.img.alpha_composite(can.img)
    a.save("boss_oak_body.png")

    a = Art(200, 80)
    for cx in (52, 148):
        a.ellipse(cx, 40, 30, 26, (28, 20, 14, 255))
        a.ellipse(cx, 38, 17, 17, (255, 190, 60, 255))
        a.ellipse(cx, 38, 8, 9, (60, 26, 10, 255))
        a.dot(cx - 8, 30, 5.5)
    a.save("boss_oak_eyes.png")


def gen_boss_sovereign():
    """Major boss 2: The Slime Sovereign - crowned colossus."""
    w, h = 320, 300
    a = Art(w, h)
    ground_shadow(a, w / 2, h - 18, 116, 22)
    # body: big slime dome
    # Dome and skirt must overlap, or the silhouette shows a gap between them:
    # the pieslice's flat edge sits at the vertical centre of its bounding box.
    a.d.pieslice([26 * SS, 60 * SS, (w - 26) * SS, (h - 12) * SS], 180, 360,
                 fill=(*C.ESSENCE_M, 255))
    a.rrect(26, h * 0.48, w - 26, h - 16, 26, (*C.ESSENCE_M, 255))
    # Light wash as a near-circle centred high: its lower boundary is strongly
    # convex, so it reads as a lit dome instead of a flat seam across the body.
    a.light(lambda s, c: s.circle(w * 0.44, h * 0.24, 122, c), (*C.ESSENCE_L, 255))
    a.dot(w * 0.30, h * 0.30, 15, C.WHITE, 170)
    a.dot(w * 0.38, h * 0.24, 7, C.WHITE, 140)
    # drips along the base
    for dx in (-78, -30, 26, 74):
        a.circle(w / 2 + dx, h - 18, 11, (*C.ESSENCE_M, 255))
    # suspended cores - these light up one at a time as phases are cleared
    for cx, cy in ((-40, 0.74), (34, 0.78), (-6, 0.86)):
        a.circle(w / 2 + cx, h * cy, 15, (*C.ESSENCE_D, 235))
        a.circle(w / 2 + cx, h * cy, 9, (*C.ESSENCE_L, 200))
        a.dot(w / 2 + cx - 3, h * cy - 4, 3.4, C.WHITE, 190)
    # crown
    cy = 66
    for i in range(5):
        x = w / 2 - 88 + i * 44
        a.poly([(x - 20, cy), (x, cy - 46), (x + 20, cy)], (*C.GOLD_M, 255))
        a.poly([(x - 10, cy - 6), (x, cy - 36), (x + 10, cy - 6)], (*C.GOLD_L, 255))
        a.circle(x, cy - 48, 7, (236, 92, 108, 255))
    a.rrect(w / 2 - 100, cy - 4, w / 2 + 100, cy + 22, 10, (*C.GOLD_D, 255))
    a.rrect(w / 2 - 100, cy - 4, w / 2 + 100, cy + 9, 6, (*C.GOLD_M, 255))
    for gx in (-64, -22, 22, 64):
        a.circle(w / 2 + gx, cy + 9, 8, (86, 196, 236, 255))
    a.save("boss_sovereign_body.png")

    a = Art(220, 90)
    for cx in (58, 162):
        a.ellipse(cx, 46, 34, 30, (24, 16, 40, 255))
        a.ellipse(cx, 44, 19, 20, (255, 236, 140, 255))
        a.ellipse(cx, 44, 9, 12, (40, 20, 60, 255))
        a.dot(cx - 9, 34, 6)
    a.save("boss_sovereign_eyes.png")


# --------------------------------------------------------------------------
# 4. projectiles, pickups, effects
# --------------------------------------------------------------------------
def gen_projectiles():
    # enemy orb (tinted in-engine per shooter)
    a = Art(28, 28)
    a.circle(14, 14, 12, (255, 255, 255, 255))
    a.circle(14, 14, 8, (255, 255, 255, 255))
    a.dot(10, 10, 3.4, C.WHITE, 255)
    a.save("orb.png")

    # thorn / spike projectile
    a = Art(40, 18)
    a.poly([(2, 9), (28, 2), (38, 9), (28, 16)], (*C.LEAF_D, 255))
    a.poly([(6, 9), (26, 5), (32, 9), (26, 13)], (*C.LEAF_L, 255))
    a.save("thorn.png")

    # boss heavy orb
    a = Art(48, 48)
    a.circle(24, 24, 22, (*C.ESSENCE_D, 255))
    a.circle(24, 24, 16, (*C.ESSENCE_M, 255))
    a.circle(24, 24, 9, (*C.ESSENCE_L, 255))
    a.dot(18, 17, 5)
    a.save("boss_orb.png")

    # telegraph ring (scaled/faded in-engine before a boss slam)
    a = Art(160, 160)
    a.circle(80, 80, 78, (255, 255, 255, 255))
    a.d.ellipse([(80 - 66) * SS, (80 - 66) * SS, (80 + 66) * SS, (80 + 66) * SS],
                fill=(0, 0, 0, 0))
    a.save("ring.png")

    # soft radial glow for lights, telegraph fills, pickup auras
    n = 128
    g = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    px = g.load()
    for y in range(n):
        for x in range(n):
            d = math.hypot(x - n / 2 + 0.5, y - n / 2 + 0.5) / (n / 2)
            if d >= 1.0:
                continue
            px[x, y] = (255, 255, 255, int(255 * (1.0 - d) ** 2.2))
    OUT.mkdir(parents=True, exist_ok=True)
    g.save(OUT / "glow.png")

    # shockwave: thicker soft ring
    a = Art(192, 192)
    a.circle(96, 96, 94, (255, 255, 255, 255))
    a.d.ellipse([(96 - 72) * SS, (96 - 72) * SS, (96 + 72) * SS, (96 + 72) * SS],
                fill=(0, 0, 0, 0))
    img = a.finish().filter(ImageFilter.GaussianBlur(2.5))
    img.save(OUT / "shockwave.png")


def gen_pickups():
    # spinning coin: 6-frame horizontal strip
    fw, fh, n = 30, 30, 6
    strip = Image.new("RGBA", (fw * n, fh), (0, 0, 0, 0))
    for i in range(n):
        t = i / n
        rx = max(1.6, abs(math.cos(math.pi * t)) * 12.0)
        a = Art(fw, fh)
        a.ellipse(fw / 2, fh / 2, rx, 12, (*C.GOLD_D, 255))
        if rx > 4:
            a.ellipse(fw / 2, fh / 2, rx - 2.4, 9.6, (*C.GOLD_M, 255))
            a.ellipse(fw / 2 - rx * 0.25, fh / 2 - 3, rx * 0.42, 4.4, (*C.GOLD_L, 255))
        strip.paste(a.finish(), (i * fw, 0))
    OUT.mkdir(parents=True, exist_ok=True)
    strip.save(OUT / "coin_strip.png")

    # essence crystal (meta currency)
    a = Art(34, 42)
    a.poly([(17, 2), (31, 16), (17, 40), (3, 16)], (*C.ESSENCE_M, 255))
    a.poly([(17, 2), (17, 40), (3, 16)], (*C.ESSENCE_L, 255))
    a.poly([(17, 2), (24, 16), (17, 26)], (*C.ESSENCE_D, 200))
    a.save("essence.png")


def gen_ui_icons():
    """64x64 ability and HUD glyphs: one accent colour plus white."""
    def new():
        return Art(64, 64)

    W = (255, 255, 255, 255)

    # dash - motion chevrons
    a = new()
    for i, x in enumerate((14, 30, 46)):
        al = 110 + i * 72
        a.poly([(x - 10, 18), (x + 2, 32), (x - 10, 46), (x - 3, 46),
                (x + 9, 32), (x - 3, 18)], (255, 255, 255, al))
    a.save("icon_dash.png")

    # grenade
    a = new()
    a.circle(32, 38, 19, W)
    a.rrect(27, 12, 37, 22, 3, W)
    a.line([(37, 15), (50, 10)], W, 4)
    a.save("icon_grenade.png")

    # shield
    a = new()
    a.poly([(32, 8), (54, 18), (54, 34), (32, 56), (10, 34), (10, 18)], W)
    a.poly([(32, 18), (45, 24), (45, 33), (32, 45), (19, 33), (19, 24)],
           (255, 255, 255, 90))
    a.save("icon_shield.png")

    # time slow - hourglass
    a = new()
    a.rrect(14, 8, 50, 14, 3, W)
    a.rrect(14, 50, 50, 56, 3, W)
    a.poly([(18, 14), (46, 14), (34, 32), (46, 50), (18, 50), (30, 32)], W)
    a.save("icon_timeslow.png")

    # nova blast - burst
    a = new()
    for i in range(8):
        ang = math.radians(i * 45)
        a.poly([(32 + math.cos(ang) * 10, 32 + math.sin(ang) * 10),
                (32 + math.cos(ang + 0.32) * 28, 32 + math.sin(ang + 0.32) * 28),
                (32 + math.cos(ang - 0.32) * 28, 32 + math.sin(ang - 0.32) * 28)], W)
    a.circle(32, 32, 11, W)
    a.save("icon_nova.png")

    # heal burst - cross with rays
    a = new()
    a.rrect(26, 12, 38, 52, 4, W)
    a.rrect(12, 26, 52, 38, 4, W)
    for i in range(4):
        ang = math.radians(45 + i * 90)
        a.circle(32 + math.cos(ang) * 24, 32 + math.sin(ang) * 24, 4,
                 (255, 255, 255, 150))
    a.save("icon_heal.png")

    # lightning bolt
    a = new()
    a.poly([(38, 6), (16, 36), (29, 36), (24, 58), (48, 26), (34, 26)], W)
    a.save("icon_lightning.png")

    # rapid fire - three bullets
    a = new()
    for i, y in enumerate((16, 32, 48)):
        a.rrect(14, y - 5, 40, y + 5, 5, W)
        a.poly([(40, y - 5), (52, y), (40, y + 5)], W)
    a.save("icon_rapidfire.png")

    # orbital - ring with satellite
    a = new()
    a.circle(32, 32, 26, W)
    a.circle(32, 32, 20, (0, 0, 0, 0))
    a.circle(32, 32, 9, W)
    a.circle(52, 20, 7, W)
    a.save("icon_orbital.png")

    # decoy - two ghosts
    a = new()
    for dx, al in ((-6, 110), (8, 255)):
        cx = 32 + dx
        a.d.pieslice([(cx - 15) * SS, 14 * SS, (cx + 15) * SS, 44 * SS], 180, 360,
                     fill=(255, 255, 255, al))
        a.rrect(cx - 15, 29, cx + 15, 46, 3, (255, 255, 255, al))
        for i in range(3):
            a.circle(cx - 10 + i * 10, 46, 5, (255, 255, 255, al))
    a.save("icon_decoy.png")

    # surge - three swept speed lines, leaning forward
    a = new()
    for i, y in enumerate((16, 32, 48)):
        lead = 8 + i * 4
        a.poly([(10 + lead, y - 5), (52, y - 5), (46, y + 5), (4 + lead, y + 5)],
               (255, 255, 255, 235 - i * 30))
    a.save("icon_surge.png")

    # vault - an arcing leap over a landing burst
    a = new()
    a.line([(10, 50), (20, 20), (34, 12), (48, 22), (54, 46)], W, 5)
    a.circle(54, 50, 7, W)
    for x in (40, 54, 60):
        a.line([(x, 56), (x, 62)], (255, 255, 255, 150), 3)
    a.save("icon_vault.png")

    # thornwall - a barrier with spikes along its top
    a = new()
    a.rrect(8, 30, 56, 52, 3, W)
    for x in (12, 24, 36, 48):
        a.poly([(x, 30), (x + 6, 12), (x + 12, 30)], W)
    a.line([(8, 40), (56, 40)], (0, 0, 0, 70), 3)
    a.save("icon_thornwall.png")

    # cinders - three flames off a scorched line
    a = new()
    a.rrect(8, 50, 56, 56, 3, W)
    for i, cx in enumerate((18, 32, 46)):
        h = (14, 4, 18)[i]
        a.poly([(cx, h), (cx + 9, 30), (cx + 5, 50), (cx - 5, 50), (cx - 9, 30)],
               (255, 255, 255, 240 - i * 20))
    a.save("icon_cinders.png")

    # life steal - heart with drop
    a = new()
    a.circle(23, 24, 11, W)
    a.circle(41, 24, 11, W)
    a.poly([(12, 27), (52, 27), (32, 54)], W)
    a.poly([(32, 34), (38, 45), (26, 45)], (0, 0, 0, 0))
    a.save("icon_lifesteal.png")

    # HUD glyphs
    a = new()
    a.circle(23, 24, 11, W)
    a.circle(41, 24, 11, W)
    a.poly([(12, 27), (52, 27), (32, 54)], W)
    a.save("icon_heart.png")

    a = new()
    a.circle(32, 32, 22, W)
    a.circle(32, 32, 16, (0, 0, 0, 0))
    a.rrect(28, 14, 36, 50, 4, W)
    a.save("icon_coin.png")

    a = new()
    a.rrect(22, 10, 42, 44, 8, W)
    a.poly([(22, 44), (42, 44), (36, 56), (28, 56)], W)
    a.save("icon_ammo.png")

    a = new()
    a.poly([(32, 4), (56, 26), (32, 60), (8, 26)], W)
    a.save("icon_essence.png")

    # crosshair
    a = Art(48, 48)
    a.circle(24, 24, 16, (255, 255, 255, 230))
    a.circle(24, 24, 12, (0, 0, 0, 0))
    for ang in (0, 90, 180, 270):
        r = math.radians(ang)
        a.line([(24 + math.cos(r) * 9, 24 + math.sin(r) * 9),
                (24 + math.cos(r) * 22, 24 + math.sin(r) * 22)], (255, 255, 255, 230), 3)
    a.circle(24, 24, 2.4, (255, 255, 255, 255))
    a.save("crosshair.png")


def gen_particles():
    # leaf particle for ambient falling leaves
    for idx, tone in enumerate((C.LEAF_L, C.LEAF_M, (196, 158, 68))):
        a = Art(20, 14)
        a.ellipse(10, 7, 9, 5.5, (*tone, 255))
        a.line([(2, 7), (18, 7)], (*C.LEAF_D, 170), 1.2)
        a.save(f"leaf_{idx}.png")

    # generic square/round spark used by hit + death bursts
    a = Art(16, 16)
    a.circle(8, 8, 7, (255, 255, 255, 255))
    a.save("spark.png")

    a = Art(14, 14)
    a.rrect(1, 1, 13, 13, 3, (255, 255, 255, 255))
    a.save("spark_square.png")


def gen_icons():
    """Application icons: a green slime on a dark forest disc.

    Windows wants a multi-size .ico and macOS wants an .icns; without them
    both exports ship the generic Godot icon, which looks unfinished on a
    store page and in a taskbar.
    """
    sizes = [16, 32, 48, 64, 128, 256, 512, 1024]
    body = Image.open(OUT / "slime_body.png").convert("RGBA")
    face = Image.open(OUT / "slime_face.png").convert("RGBA")

    master = Art(1024, 1024)
    master.circle(512, 512, 500, (36, 54, 38, 255))
    master.circle(512, 512, 470, (52, 82, 54, 255))
    base = master.finish()

    # the slime, scaled to sit on the disc with a little headroom
    slime = body.resize((720, 600), Image.LANCZOS)
    base.alpha_composite(slime, (152, 250))
    eyes = face.resize((320, 150), Image.LANCZOS)
    base.alpha_composite(eyes, (352, 420))

    OUT.mkdir(parents=True, exist_ok=True)
    base.save(OUT / "app_icon.png")
    base.save(OUT / "slimer.ico",
              sizes=[(s, s) for s in sizes if s <= 256])

    # .icns needs an iconset directory and Apple's iconutil
    import subprocess

    iconset = OUT / "slimer.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    for s in (16, 32, 128, 256, 512):
        base.resize((s, s), Image.LANCZOS).save(iconset / f"icon_{s}x{s}.png")
        base.resize((s * 2, s * 2), Image.LANCZOS).save(
            iconset / f"icon_{s}x{s}@2x.png")
    try:
        subprocess.run(["iconutil", "-c", "icns", str(iconset),
                        "-o", str(OUT / "slimer.icns")], check=True,
                       capture_output=True)
        shutil.rmtree(iconset)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"  (no .icns: {exc}) - macOS icon skipped, .ico still written")


def _seamless_noise(size: int, octaves, seed: int):
    """Tileable value noise in [0,1], built from wrap-around box blurs."""
    import numpy as np

    r = np.random.default_rng(seed)
    acc = np.zeros((size, size), dtype=float)
    weight = 0.0
    for radius, amp in octaves:
        field = r.random((size, size))
        # box blur with np.roll wraps at the edges, which is what makes the
        # result tile without a visible seam
        for _ in range(2):
            blurred = np.zeros_like(field)
            for dy in range(-radius, radius + 1):
                for dx in range(-radius, radius + 1):
                    blurred += np.roll(np.roll(field, dy, 0), dx, 1)
            field = blurred / ((2 * radius + 1) ** 2)
        field -= field.min()
        if field.max() > 0:
            field /= field.max()
        acc += field * amp
        weight += amp
    return acc / weight


def gen_ground_tiles():
    """Seamless 256px ground tiles - one draw call for the whole forest floor."""
    import numpy as np

    size = 256
    specs = {
        # name: (dark, mid, light) - quantised into flat bands, no gradients,
        # so the floor reads as the same flat-vector language as the props
        "ground_grass": ((44, 74, 48), (52, 88, 55), (61, 101, 62)),
        "ground_clearing": ((72, 106, 60), (84, 120, 68), (97, 134, 77)),
        "ground_path": ((104, 86, 60), (120, 100, 70), (134, 114, 82)),
        "ground_water": ((36, 108, 156), (46, 128, 178), (62, 152, 202)),
    }
    for idx, (name, tones) in enumerate(specs.items()):
        n = _seamless_noise(size, [(9, 1.0), (4, 0.5), (2, 0.25)], 1000 + idx)
        out = np.zeros((size, size, 4), dtype=np.uint8)
        # three flat bands rather than a smooth ramp
        bands = [(0.00, tones[0]), (0.42, tones[1]), (0.66, tones[2])]
        for threshold, color in bands:
            mask = n >= threshold
            out[mask] = (*color, 255)
        Image.fromarray(out, "RGBA").save(OUT / f"{name}.png")


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    steps = [
        # The originals first: gen_enemies and gen_icons read the slime this
        # authors, so it has to exist before they run.
        ("base slime", gen_slime_body),
        ("slime face", gen_slime_face),
        ("player", gen_player_body),
        ("player face", gen_player_face),
        ("pistol", gen_pistol),
        ("bullet", gen_bullet),
        ("muzzle flash", gen_muzzle_flash),
        ("impact puff", gen_impact_circle),
        ("pine tree", gen_pine_tree),
        ("ground shadow", gen_ground_shadow),
        ("potions", gen_original_potions),

        ("ground tiles", gen_ground_tiles),
        ("app icons", gen_icons),
        ("enemy recolours", gen_enemies),
        ("faces", gen_faces),
        ("trees", gen_trees),
        ("bushes", gen_bushes),
        ("rocks", gen_rocks),
        ("logs", gen_logs),
        ("ground detail", gen_ground_detail),
        ("shop props", gen_shop_props),
        ("boss: bramble", gen_boss_bramble),
        ("boss: toad", gen_boss_toad),
        ("boss: wisp", gen_boss_wisp),
        ("boss: oak", gen_boss_oak),
        ("boss: sovereign", gen_boss_sovereign),
        ("projectiles", gen_projectiles),
        ("pickups", gen_pickups),
        ("ui icons", gen_ui_icons),
        ("particles", gen_particles),
    ]
    for label, fn in steps:
        fn()
        print(f"  {label}")
    print(f"{len(list(OUT.glob('*.png')))} sprites -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
