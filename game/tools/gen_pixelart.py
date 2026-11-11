#!/usr/bin/env python3
"""Remake every sprite as pixel art in Aseprite, through the pixel-plugin MCP server.

pixel-plugin (github.com/willibrandon/pixel-plugin) ships pixel-mcp, an MCP
server that drives Aseprite. This script talks to it over stdio the same way
Claude Code does, so the whole remake is one repeatable command:

    python3 tools/gen_pixelart.py              # needs pixel-plugin + Aseprite
    python3 tools/gen_pixelart.py --only gen/rock_a.png slime_body.png

Every sprite is rebuilt at half resolution (1 art pixel = PX game pixels),
then scaled up with nearest-neighbour onto its original canvas, so filenames,
sizes, anchors, hitboxes and face offsets all stay valid.

Two routes:
  * Our own art (everything gen_art.py drew) is downsampled in Aseprite,
    outlined, and quantized to a small palette.
  * Every sprite that came from the GDQuest pack (see RIGHTS.md) is redrawn
    from scratch with Aseprite's drawing tools instead - nothing is sampled
    from the pack art - so the pixel-art build carries no CC BY-NC-SA art.

The soft white FX textures (glow, rings, sparks), which are tinted in-engine,
come from gen_pixellab.gen_procedural() on the same pixel grid.

tools/art_ref/ holds the pre-remake sprites (snapshotted on first run), so
reruns always start from the same source rather than from their own output.

Setup: install pixel-plugin, then point ~/.config/pixel-mcp/config.json at an
Aseprite binary ("aseprite_path"). Override the server with PIXEL_MCP=path.
"""
from __future__ import annotations

import argparse
import glob
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
SPRITES = ROOT / "assets" / "sprites"
REF = TOOLS / "art_ref"

PX = 2                    # game pixels per art pixel
OUTLINE = "#1C2420"       # one dark outline colour for the whole game
SHADOW_ALPHA = 52         # gen_art.ground_shadow()'s alpha

sys.path.insert(0, str(TOOLS))
import gen_art  # noqa: E402  (recolor + tint table, so colours stay promises)
import gen_pixellab  # noqa: E402  (procedural FX on the same grid)


# --------------------------------------------------------------------------
# pixel-mcp client
# --------------------------------------------------------------------------
class PixelMCP:
    """Minimal MCP stdio client: one pixel-mcp process, JSON-RPC per line."""

    def __init__(self):
        exe = os.environ.get("PIXEL_MCP")
        if not exe:
            found = sorted(glob.glob(os.path.expanduser(
                "~/.claude/plugins/cache/pixel-plugin/pixel-plugin/*/bin/pixel-mcp")))
            if not found:
                raise SystemExit("pixel-mcp not found: install pixel-plugin "
                                 "(claude plugin install pixel-plugin) or set PIXEL_MCP")
            exe = found[-1]
        # pixel-mcp logs every call to stderr; an undrained pipe fills and
        # blocks the server, so the log goes to a file instead
        self.log = tempfile.NamedTemporaryFile("w+", prefix="pixel-mcp-", suffix=".log")
        self.proc = subprocess.Popen([exe], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                     stderr=self.log, text=True, bufsize=1)
        self.next_id = 0
        self._rpc("initialize", {"protocolVersion": "2024-11-05", "capabilities": {},
                                 "clientInfo": {"name": "slimer-gen-pixelart", "version": "1"}})
        self._send({"jsonrpc": "2.0", "method": "notifications/initialized"})

    def _send(self, msg):
        self.proc.stdin.write(json.dumps(msg) + "\n")

    def _rpc(self, method, params):
        self.next_id += 1
        self._send({"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params})
        while True:
            line = self.proc.stdout.readline()
            if not line:
                self.log.seek(0)
                raise SystemExit(f"pixel-mcp exited: {self.log.read().strip()[-600:]}")
            msg = json.loads(line)
            if msg.get("id") == self.next_id:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg["result"]

    def __call__(self, tool, **args):
        result = self._rpc("tools/call", {"name": tool, "arguments": args})
        text = "".join(c.get("text", "") for c in result.get("content", []))
        if result.get("isError"):
            raise RuntimeError(f"{tool}: {text}")
        try:
            return json.loads(text)
        except json.JSONDecodeError:
            return text


class Canvas:
    """One Aseprite sprite at art resolution, drawn through pixel-mcp."""

    def __init__(self, mcp: PixelMCP, w: int, h: int, layer="art"):
        self.m, self.w, self.h, self.layer = mcp, w, h, layer
        self.path = mcp("create_canvas", width=w, height=h, color_mode="rgb")["file_path"]
        mcp("add_layer", sprite_path=self.path, layer_name=layer)
        mcp("delete_layer", sprite_path=self.path, layer_name="Layer 1")

    def _at(self, **kw):
        return dict(sprite_path=self.path, layer_name=self.layer, frame_number=1, **kw)

    def pixels(self, pts, color):
        pts = [(x, y) for x, y in pts if 0 <= x < self.w and 0 <= y < self.h]
        if pts:
            self.m("draw_pixels", **self._at(
                pixels=[{"x": x, "y": y, "color": color} for x, y in pts]))

    def rect(self, x, y, w, h, color):
        self.m("draw_rectangle", **self._at(x=x, y=y, width=w, height=h, color=color, filled=True))

    def circle(self, cx, cy, r, color):
        self.m("draw_circle", **self._at(center_x=cx, center_y=cy, radius=r, color=color,
                                         filled=True))

    def line(self, x1, y1, x2, y2, color, thickness=1):
        self.m("draw_line", **self._at(x1=x1, y1=y1, x2=x2, y2=y2, color=color,
                                       thickness=thickness))

    def import_png(self, path: Path):
        self.m("import_image", **self._at(image_path=str(path)))

    def outline(self, color=OUTLINE):
        self.m("apply_outline", **self._at(color=color, thickness=1))

    def quantize(self, colors: int):
        self.m("quantize_palette", sprite_path=self.path, target_colors=colors,
               algorithm="median_cut", dither=False, preserve_transparency=True,
               convert_to_indexed=False)

    def export(self, out: Path) -> Image.Image:
        self.m("export_sprite", sprite_path=self.path, output_path=str(out), format="png",
               frame_number=1)
        return Image.open(out).convert("RGBA")


# --------------------------------------------------------------------------
# raster helpers - shapes as pixel sets, so fills can be layered and clipped
# --------------------------------------------------------------------------
def ellipse_px(cx, cy, rx, ry):
    return {(x, y)
            for y in range(math.floor(cy - ry), math.ceil(cy + ry) + 1)
            for x in range(math.floor(cx - rx), math.ceil(cx + rx) + 1)
            if ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2 <= 1.0}


def poly_px(pts):
    """Even-odd scanline fill, sampled at pixel centres."""
    ys = [p[1] for p in pts]
    out = set()
    for y in range(math.floor(min(ys)), math.ceil(max(ys)) + 1):
        sy = y + 0.5
        xs = []
        for (x0, y0), (x1, y1) in zip(pts, pts[1:] + pts[:1]):
            if (y0 <= sy < y1) or (y1 <= sy < y0):
                xs.append(x0 + (sy - y0) * (x1 - x0) / (y1 - y0))
        xs.sort()
        for a, b in zip(xs[::2], xs[1::2]):
            out.update((x, y) for x in range(math.ceil(a - 0.5), math.floor(b - 0.5) + 1))
    return out


def rrect_px(x0, y0, x1, y1, r):
    """Rounded rectangle covering [x0, x1) x [y0, y1)."""
    out = set()
    for y in range(y0, y1):
        for x in range(x0, x1):
            dx = max(x0 + r - (x + 0.5), 0, (x + 0.5) - (x1 - r))
            dy = max(y0 + r - (y + 0.5), 0, (y + 0.5) - (y1 - r))
            if dx * dx + dy * dy <= r * r:
                out.add((x, y))
    return out


def inset(shape, n=1):
    """Pixels of `shape` at least n steps from its edge."""
    cur = set(shape)
    for _ in range(n):
        cur = {(x, y) for x, y in cur
               if {(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)} <= cur}
    return cur


def hexc(rgb, a=None):
    s = "#%02X%02X%02X" % rgb
    return s + ("%02X" % a if a is not None else "")


# --------------------------------------------------------------------------
# output
# --------------------------------------------------------------------------
def art_size(ref: Image.Image):
    return math.ceil(ref.width / PX), math.ceil(ref.height / PX)


def land(art: Image.Image, rel: str, size, under: Image.Image | None = None):
    """Nearest-neighbour up to game scale, trimmed to the original canvas."""
    big = art.resize((art.width * PX, art.height * PX), Image.NEAREST)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    if under is not None:
        out.alpha_composite(under.resize((under.width * PX, under.height * PX),
                                         Image.NEAREST).crop((0, 0, *size)))
    out.alpha_composite(big.crop((0, 0, *size)))
    path = SPRITES / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)
    return out


# --------------------------------------------------------------------------
# route 1: our own art, rebuilt in Aseprite
# --------------------------------------------------------------------------
NO_OUTLINE = ("eyes_", "_eyes", "leaf_", "ground_", "grass_", "flower_", "crosshair")
# fewer colours where the source is already nearly flat
PALETTE_SIZE = {"elite_crown": 16, "icon_": 4, "ground_": 4, "eyes_": 5, "_eyes": 6, "leaf_": 3,
                "grass_": 4, "flower_": 4, "crosshair": 3}

# Fresh drawings, derived sprites and procedural FX - not pixelized from refs.
FRESH = ["slime_body.png", "slime_face.png", "boo_body.png", "boo_face.png", "pistol.png",
         "projectile.png", "muzzle_flash.png", "pine_tree.png",
         *[f"gen/potion_{c}.png" for c in ("red", "blue", "purple", "green", "yellow")]]
DERIVED = [f"gen/enemy_{c}_body.png" for c in gen_art.ENEMY_TINTS] + ["gen/app_icon.png"]
PROCEDURAL = ["gen/glow.png", "gen/ring.png", "gen/shockwave.png", "gen/spark.png",
              "gen/spark_square.png", "gen/orb.png", "ground_shadow.png", "impact_circle.png"]
# pack sheets nothing loads at runtime (gen_art.gen_potions sliced them)
SKIP = [f"potion_{c}_full.png" for c in ("red", "blue", "purple")]


def opt(rel: str, table, default):
    name = Path(rel).stem
    for key, val in table.items():
        if key in name:
            return val
    return default


def split_shadow(img: Image.Image):
    """Solid art vs. the soft baked-in ground shadow under props."""
    body = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    bp, sp, src = body.load(), shadow.load(), img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = src[x, y]
            if a >= 128:
                bp[x, y] = (r, g, b, 255)
            elif a >= 16 and max(r, g, b) < 60:
                sp[x, y] = (0, 0, 0, SHADOW_ALPHA)
    return body, shadow


def pixelize(m: PixelMCP, rel: str, tmp: Path):
    ref_path = REF / rel
    ref = Image.open(ref_path)
    w, h = art_size(ref)
    stem = rel.replace("/", "_")[:-4]
    ds = tmp / f"{stem}.ds.png"
    m("downsample_image", source_path=str(ref_path), target_width=w, target_height=h,
      output_path=str(ds))
    small = Image.open(ds).convert("RGBA")

    if Path(rel).stem.startswith("ground_"):        # opaque, seamless tiles
        body, shadow = small, None
    else:
        body, shadow = split_shadow(small)
    body.save(ds)

    c = Canvas(m, w, h)
    c.import_png(ds)
    outline = not any(k in Path(rel).stem for k in NO_OUTLINE)
    if outline:
        c.outline()
    c.quantize(opt(rel, PALETTE_SIZE, 12) + (1 if outline else 0))
    land(c.export(tmp / f"{stem}.png"), rel, ref.size, shadow)


# --------------------------------------------------------------------------
# route 2: pack sprites, redrawn from scratch
# --------------------------------------------------------------------------
SLIME_RIM, SLIME_MID, SLIME_DARK, SLIME_HI = (153, 241, 65), (92, 205, 39), (66, 170, 30), (208, 255, 132)


def slime_shape(w, h):
    """Gumdrop: flat base, near-vertical sides, round dome."""
    cx, base, top = w / 2, h - 1.5, 1.5
    out = set()
    for y in range(h):
        t = (y + 0.5 - top) / (base - top)
        if not 0 <= t <= 1:
            continue
        dome = math.sqrt(max(0.0, 1 - (1 - min(t / 0.62, 1)) ** 2))   # rounded top 62%
        foot = 1 - max(0.0, (t - 0.86) / 0.14) ** 2 * 0.12            # tucked-in base
        half = (w / 2 - 1.5) * dome * foot
        out.update((x, y) for x in range(w) if abs(x + 0.5 - cx) <= half)
    return out


def draw_slime_body(m, tmp):
    rel = "slime_body.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)
    c = Canvas(m, w, h)
    shape = slime_shape(w, h)
    inner = inset(shape, 2)
    c.pixels(shape, hexc(SLIME_RIM))
    c.pixels(inner, hexc(SLIME_MID))
    c.pixels({p for p in inner if p[1] >= h - 9}, hexc(SLIME_DARK))     # belly shade
    c.pixels(ellipse_px(13, 11, 4, 3.4) & inner, hexc(SLIME_HI))         # gloss
    c.pixels({(19, 7), (20, 7), (21, 8)} & inner, hexc(SLIME_HI))
    c.outline()
    land(c.export(tmp / "slime_body.png"), rel, ref.size)


def draw_slime_face(m, tmp):
    rel = "slime_face.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 28x14
    c = Canvas(m, w, h)
    dark = hexc((27, 81, 18))
    for cx in (5, 23):
        c.pixels(ellipse_px(cx, 5, 3.4, 3.6), dark)
    c.pixels({(10, 9), (11, 10), (12, 11), (13, 11), (14, 11), (15, 11), (16, 10), (17, 9),
              (12, 10), (15, 10)}, dark)
    land(c.export(tmp / "slime_face.png"), rel, ref.size)


def draw_boo_body(m, tmp):
    """White, because player.gd tints it (hurt flash) and reuses it as the outline."""
    rel = "boo_body.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 42x37
    c = Canvas(m, w, h)
    body = rrect_px(1, 1, w - 1, h - 1, 9)
    c.pixels(body, "#FFFFFF")
    c.pixels({p for p in inset(body, 1) if p[1] >= h - 7}, hexc((222, 226, 236)))
    c.pixels(ellipse_px(9, 7, 2.5, 2) & body, hexc((255, 255, 255)))
    land(c.export(tmp / "boo_body.png"), rel, ref.size)


def draw_boo_face(m, tmp):
    rel = "boo_face.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 24x13
    c = Canvas(m, w, h)
    for cx in (3.5, 20.5):
        c.pixels(ellipse_px(cx, 4, 3, 3.3), "#000000")
        c.pixels({(int(cx) - 1, 2)}, "#FFFFFF")
    c.pixels({(8, 9), (9, 10), (10, 11), (11, 11), (12, 11), (13, 11), (14, 10), (15, 9),
              (9, 9), (14, 9)}, "#000000")
    land(c.export(tmp / "boo_face.png"), rel, ref.size)


def draw_pistol(m, tmp):
    """Toy blaster pointing right; barrel tip at the Muzzle marker (x 70, y 19)."""
    rel = "pistol.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 35x25
    c = Canvas(m, w, h)
    dark, mid, light, pale = (52, 86, 168), (87, 135, 224), (119, 170, 250), (160, 200, 255)
    grip = poly_px([(5, 12), (13, 12), (11, 23), (4, 23)])
    c.pixels(grip, hexc(light))
    c.pixels({p for p in grip if p[0] <= 5 or p[1] >= 22}, hexc(mid))
    c.pixels(rrect_px(3, 7, 17, 15, 2), hexc(light))                   # frame
    c.pixels(rrect_px(13, 3, 34, 15, 3), hexc(mid))                    # barrel housing
    c.pixels(rrect_px(14, 4, 33, 7, 1), hexc(pale))                    # top light
    c.pixels(rrect_px(13, 12, 34, 15, 2) & rrect_px(13, 3, 34, 15, 3), hexc(dark))
    c.pixels(rrect_px(28, 6, 32, 13, 1), hexc(dark))                   # muzzle ring
    c.pixels(poly_px([(12, 15), (16, 15), (15, 19), (12, 19)]), hexc(dark))   # trigger
    c.outline()
    land(c.export(tmp / "pistol.png"), rel, ref.size)


def draw_projectile(m, tmp):
    rel = "projectile.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 25x14
    c = Canvas(m, w, h)
    tail = poly_px([(1, 6), (16, 2), (16, 12), (1, 8)])
    c.pixels(tail | ellipse_px(18, 7, 6, 5.5), hexc((255, 206, 61)))
    c.pixels(ellipse_px(18.5, 7, 3.6, 3.4), hexc((255, 150, 46)))
    c.pixels({(17, 5), (18, 5)}, hexc((255, 236, 170)))
    land(c.export(tmp / "projectile.png"), rel, ref.size)


def draw_muzzle_flash(m, tmp):
    rel = "muzzle_flash.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 16x16
    c = Canvas(m, w, h)
    star = poly_px([(0, 8), (5, 4), (8, 0), (11, 4), (16, 8), (11, 12), (8, 16), (5, 12)])
    c.pixels(star, hexc((255, 212, 61)))
    c.pixels(poly_px([(3, 8), (6, 6), (8, 3), (10, 6), (13, 8), (10, 10), (8, 13), (6, 10)]),
             hexc((255, 242, 170)))
    land(c.export(tmp / "muzzle_flash.png"), rel, ref.size)


def draw_pine_tree(m, tmp):
    rel = "pine_tree.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 64x76
    c = Canvas(m, w, h)
    cx = w / 2
    c.pixels({(x, y) for x in range(28, 36) for y in range(58, 76)}, hexc((152, 106, 66)))
    c.pixels({(x, y) for x in range(28, 30) for y in range(58, 76)}, hexc((204, 152, 105)))
    tiers = [(3, 25, 15), (13, 43, 22), (26, 62, 29)]                  # apex y, base y, half width
    for apex, base, half in reversed(tiers):
        tri = poly_px([(cx, apex), (cx + half, base), (cx - half, base)])
        c.pixels(tri, hexc((48, 149, 64)))
        c.pixels({p for p in tri if p[0] + 0.5 < cx - 1}, hexc((74, 182, 86)))   # sun side
        c.pixels({p for p in tri if p[1] >= base - 2}, hexc((43, 104, 56)))       # tier shadow
    c.outline()
    land(c.export(tmp / "pine_tree.png"), rel, ref.size)


POTIONS = {"red": (214, 48, 72), "blue": (58, 148, 220), "purple": (150, 80, 220),
           "green": (80, 200, 80), "yellow": (240, 200, 60)}


def draw_potion(m, tmp, colour):
    rel = f"gen/potion_{colour}.png"
    ref = Image.open(REF / rel)
    w, h = art_size(ref)                                                # 16x16
    c = Canvas(m, w, h)
    liquid = POTIONS[colour]
    shade = tuple(int(v * 0.68) for v in liquid)
    glass = (196, 214, 232)
    flask = ellipse_px(8, 10, 5.5, 5.2)
    c.pixels(flask, hexc(glass))
    c.pixels({(x, y) for x in range(6, 10) for y in range(3, 6)}, hexc(glass))   # neck
    c.pixels({(x, y) for x in range(6, 10) for y in range(1, 3)}, hexc((150, 106, 66)))  # cork
    fill = {p for p in inset(flask, 1) if p[1] >= 8}
    c.pixels(fill, hexc(liquid))
    c.pixels({p for p in fill if p[1] >= 13 or p[0] >= 11}, hexc(shade))
    c.pixels({(5, 9), (5, 10), (6, 8)}, "#FFFFFF")
    c.outline()
    land(c.export(tmp / f"potion_{colour}.png"), rel, ref.size)


# --------------------------------------------------------------------------
# derived
# --------------------------------------------------------------------------
def derive_enemies():
    body = Image.open(SPRITES / "slime_body.png").convert("RGBA")
    for name, (hue, sm, vm) in gen_art.ENEMY_TINTS.items():
        gen_art.recolor(body, hue, sm, vm).save(SPRITES / "gen" / f"enemy_{name}_body.png")


def compose_app_icon(m, tmp):
    """Slime on a forest disc, 64x64 art pixels blown up 16x to 1024."""
    n, scale = 64, 16
    c = Canvas(m, n, n)
    c.circle(32, 32, 31, hexc((36, 54, 38)))
    c.circle(32, 32, 29, hexc((52, 82, 54)))
    base = c.export(tmp / "icon_disc.png")
    body = Image.open(SPRITES / "slime_body.png").convert("RGBA")
    face = Image.open(SPRITES / "slime_face.png").convert("RGBA")
    body = body.resize((body.width // PX, body.height // PX), Image.NEAREST)
    face = face.resize((face.width // PX, face.height // PX), Image.NEAREST)
    bx, by = (n - body.width) // 2, 13
    base.alpha_composite(body, (bx, by))
    # enemy.tscn puts the face 6 px above the body's centre
    base.alpha_composite(face, (bx + (body.width - face.width) // 2,
                                by + body.height // 2 - 3 - face.height // 2))
    icon = base.resize((n * scale, n * scale), Image.NEAREST)
    out = SPRITES / "gen"
    icon.save(out / "app_icon.png")
    icon.save(out / "slimer.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
    icon.save(out / "slimer.icns")


# --------------------------------------------------------------------------
def snapshot_refs():
    """Copy the pre-remake sprites into art_ref/ once."""
    n = 0
    for src in sorted(SPRITES.rglob("*.png")):
        dst = REF / src.relative_to(SPRITES)
        if not dst.exists():
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            n += 1
    if n:
        print(f"snapshotted {n} reference sprites -> {REF.relative_to(ROOT)}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", nargs="+", metavar="PATH",
                    help="sprite paths under assets/sprites/, e.g. gen/rock_a.png")
    args = ap.parse_args()

    snapshot_refs()
    every = sorted(str(p.relative_to(REF)) for p in REF.rglob("*.png"))
    targets = args.only or every
    fresh_fns = {
        "slime_body.png": draw_slime_body, "slime_face.png": draw_slime_face,
        "boo_body.png": draw_boo_body, "boo_face.png": draw_boo_face,
        "pistol.png": draw_pistol, "projectile.png": draw_projectile,
        "muzzle_flash.png": draw_muzzle_flash, "pine_tree.png": draw_pine_tree,
        **{f"gen/potion_{c}.png": (lambda m, t, c=c: draw_potion(m, t, c)) for c in POTIONS},
    }

    m = PixelMCP()
    with tempfile.TemporaryDirectory(prefix="slimer-pixelart-") as td:
        tmp = Path(td)
        for rel in targets:
            if rel in SKIP or rel in DERIVED or rel in PROCEDURAL:
                continue
            if rel in fresh_fns:
                fresh_fns[rel](m, tmp)
                print(f"  drew      {rel}")
            else:
                pixelize(m, rel, tmp)
                print(f"  pixelized {rel}")
        if args.only is None or "slime_body.png" in targets:
            derive_enemies()
            print("  enemy recolours")
        if args.only is None or {"slime_body.png", "slime_face.png", "gen/app_icon.png"} & set(targets):
            compose_app_icon(m, tmp)
            print("  app icons")
    if args.only is None:
        gen_pixellab.gen_procedural()
        print("  procedural FX")


if __name__ == "__main__":
    main()
