#!/usr/bin/env python3
"""Remake every sprite as pixel art in Aseprite, through the pixel-plugin MCP server.

pixel-plugin (github.com/willibrandon/pixel-plugin) ships pixel-mcp, an MCP
server that drives Aseprite. This script talks to it over stdio the same way
Claude Code does, so the whole remake is one repeatable command:

    python3 tools/gen_pixelart.py              # needs pixel-plugin + Aseprite
    python3 tools/gen_pixelart.py --only gen/rock_a.png gen/slime_body.png

Every sprite is rebuilt at half resolution (1 art pixel = PX game pixels) and
scaled back up with nearest-neighbour onto its original canvas, so filenames,
sizes, frame grids, anchors, hitboxes and face offsets all stay valid.

Per sprite: Aseprite downsamples it, outlines it and quantizes it to a small
palette. Around that, this script keeps what Aseprite's tools would flatten:
  * transparency is reduced to a few fixed levels instead of being thrown
    away, so ghost slimes stay see-through and death frames still fade;
  * the soft ground shadow baked under props is kept as its own layer, so it
    is not outlined;
  * sprite sheets are processed frame by frame, so an outline never bleeds
    into the neighbouring frame.

Weapon sprites that gen_art.py does not draw are drawn here from scratch with
Aseprite's drawing tools (draw_weapons()).

tools/art_ref/ holds the pre-remake sprites (snapshotted on first run), so
reruns always start from the same source rather than from their own output.
Run gen_art.py first if you change it, then delete the affected art_ref files.

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
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

TOOLS = Path(__file__).resolve().parent
ROOT = TOOLS.parent
SPRITES = ROOT / "assets" / "sprites"
REF = TOOLS / "art_ref"

PX = 2                    # game pixels per art pixel
OUTLINE = "#1C2420"       # one dark outline colour for the whole game
ALPHA_LEVELS = np.array([0, 64, 128, 192, 255])


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
                                 "clientInfo": {"name": "slimer-gen-pixelart", "version": "2"}})
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
        pts = sorted((x, y) for x, y in pts if 0 <= x < self.w and 0 <= y < self.h)
        if pts:
            self.m("draw_pixels", **self._at(
                pixels=[{"x": x, "y": y, "color": color} for x, y in pts]))

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


def rect_px(x0, y0, x1, y1):
    """Pixels in [x0, x1) x [y0, y1)."""
    return {(x, y) for x in range(x0, x1) for y in range(y0, y1)}


def hexc(rgb):
    return "#%02X%02X%02X" % tuple(rgb)


# --------------------------------------------------------------------------
# alpha handling around Aseprite
# --------------------------------------------------------------------------
def _max3(a: np.ndarray) -> np.ndarray:
    p = np.pad(a, 1)
    return np.max([p[dy:dy + a.shape[0], dx:dx + a.shape[1]]
                   for dy in range(3) for dx in range(3)], axis=0)


def posterize_alpha(alpha: np.ndarray) -> np.ndarray:
    """Few discrete alpha levels; anti-aliased rims take their neighbours' level.

    A rim pixel at alpha 110 next to an opaque interior becomes opaque (crisp
    pixel edge); a whole frame fading at alpha 90 stays at that level instead
    of snapping to solid.
    """
    near = _max3(alpha)
    keep = (alpha >= 24) & (alpha >= 0.45 * near)
    value = np.where(alpha >= 0.8 * near, alpha, near)          # rims adopt neighbours
    idx = np.abs(value[..., None] - ALPHA_LEVELS[None, None, :]).argmin(-1)
    out = ALPHA_LEVELS[idx]
    out[~keep] = 0
    return out


def split(img: Image.Image):
    """(body rgb, body alpha, shadow rgba) for one downsampled frame."""
    arr = np.asarray(img.convert("RGBA")).astype(np.int32)
    alpha = posterize_alpha(arr[..., 3])
    dark = arr[..., :3].max(-1) < 60
    shadow_mask = (alpha > 0) & (alpha <= 128) & dark
    body_mask = (alpha > 0) & ~shadow_mask
    shadow = np.zeros_like(arr)
    shadow[shadow_mask] = [0, 0, 0, 0]
    shadow[shadow_mask, 3] = alpha[shadow_mask]
    body_alpha = np.where(body_mask, alpha, 0)
    rgb = arr.copy()
    rgb[..., 3] = np.where(body_mask, 255, 0)
    return (Image.fromarray(rgb.astype(np.uint8), "RGBA"), body_alpha,
            Image.fromarray(shadow.astype(np.uint8), "RGBA"))


def recombine(exported: Image.Image, body_alpha: np.ndarray, shadow: Image.Image):
    """Put the real alpha back; outline pixels fade with the body they ring."""
    arr = np.asarray(exported.convert("RGBA")).astype(np.int32)
    body = body_alpha > 0
    ring = (arr[..., 3] > 0) & ~body
    near = _max3(body_alpha)
    arr[..., 3] = np.where(body, body_alpha, np.where(ring, near, 0))
    out = shadow.copy()
    out.alpha_composite(Image.fromarray(arr.astype(np.uint8), "RGBA"))
    return out


# --------------------------------------------------------------------------
# per-sprite options
# --------------------------------------------------------------------------
# No outline: faces and eyes sit on a body that already has one; FX and
# overlays are tinted or additive; ground cover and tiles would turn to noise.
NO_OUTLINE = ("_face", "eyes", "glow", "ring", "shockwave", "spark", "orb",
              "impact_circle", "ground_", "crosshair", "muzzle_flash", "leaf_",
              "grass_", "flower_", "badge", "tall_grass")
PALETTE_SIZE = {"icon_": 4, "ground_": 5, "eyes": 6, "leaf_": 3, "grass_": 4,
                "flower_": 4, "crosshair": 2, "elite_crown": 16, "badge": 6,
                "glow": 2, "ring": 2, "shockwave": 2, "spark": 2, "orb": 3,
                "impact_circle": 2, "ground_shadow": 2, "app_icon": 24}
SCALE = {"app_icon": 8}          # the 1024 icon gets a chunkier grid


def opt(name: str, table, default):
    for key, val in table.items():
        if key in name:
            return val
    return default


def frames_for(name: str) -> int:
    """Animation sheets lay their frames out left to right."""
    if name.startswith("boss_") and name.endswith("_body"):
        return 4
    if name.startswith("enemy_") and name.endswith("_body") or name == "slime_body":
        return 8
    if name == "coin_strip":
        return 6
    return 1


def pixelize(m: PixelMCP, rel: str, tmp: Path):
    ref_path = REF / rel
    ref = Image.open(ref_path).convert("RGBA")
    name = Path(rel).stem
    scale = opt(name, SCALE, PX)
    w, h = math.ceil(ref.width / scale), math.ceil(ref.height / scale)
    stem = rel.replace("/", "_")[:-4]
    ds_path = tmp / f"{stem}.ds.png"
    m("downsample_image", source_path=str(ref_path), target_width=w, target_height=h,
      output_path=str(ds_path))
    small = Image.open(ds_path).convert("RGBA")

    if name.startswith("ground_") and name != "ground_shadow":   # opaque tiles
        c = Canvas(m, w, h)
        c.import_png(ds_path)
        c.quantize(opt(name, PALETTE_SIZE, 12))
        land(c.export(tmp / f"{stem}.png"), rel, ref.size, scale)
        return

    n = frames_for(name)
    fw = w // n
    outline = not any(k in name for k in NO_OUTLINE)
    sheet = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    for f in range(n):
        frame = small.crop((f * fw, 0, (f + 1) * fw if f < n - 1 else w, h))
        body, body_alpha, shadow = split(frame)
        if body_alpha.max() == 0:
            sheet.alpha_composite(shadow, (f * fw, 0))
            continue
        fpath = tmp / f"{stem}.{f}.in.png"
        body.save(fpath)
        c = Canvas(m, frame.width, frame.height)
        c.import_png(fpath)
        if outline:
            c.outline()
        c.quantize(opt(name, PALETTE_SIZE, 12) + (1 if outline else 0))
        out = recombine(c.export(tmp / f"{stem}.{f}.png"), body_alpha, shadow)
        sheet.alpha_composite(out, (f * fw, 0))
    land(sheet, rel, ref.size, scale)


def land(art: Image.Image, rel: str, size, scale=PX):
    """Nearest-neighbour up to game scale, trimmed to the original canvas."""
    big = art.resize((art.width * scale, art.height * scale), Image.NEAREST)
    out = Image.new("RGBA", size, (0, 0, 0, 0))
    out.alpha_composite(big.crop((0, 0, *size)))
    path = SPRITES / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    out.save(path)
    if Path(rel).stem == "app_icon":
        out.save(path.parent / "slimer.ico", sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
        out.save(path.parent / "slimer.icns")
    return out


# --------------------------------------------------------------------------
# weapons - drawn from scratch, nothing to pixelize
# --------------------------------------------------------------------------
STEEL = [(70, 78, 92), (124, 134, 150), (176, 186, 200), (226, 232, 240)]
WOOD = [(92, 60, 36), (138, 94, 58), (182, 132, 84)]
BRASS = [(150, 104, 30), (214, 160, 54), (250, 214, 112)]


def _weapon(m, tmp, name, w, h, layers):
    """layers: [(pixel set, rgb)], painted in order, then outlined."""
    c = Canvas(m, w, h)
    for pts, rgb in layers:
        c.pixels(pts, hexc(rgb))
    c.outline()
    land(c.export(tmp / f"{name}.png"), f"gen/{name}.png", (w * PX, h * PX))


def draw_weapons(m, tmp):
    """Each weapon points right with its grip near the left; the gun scene
    rotates and mirrors it. Art pixels, so 35x25 here is 70x50 in game."""
    # Scattergun: short, fat double barrel, wooden stock
    _weapon(m, tmp, "weapon_scattergun", 36, 22, [
        (poly_px([(1, 12), (11, 10), (11, 17), (4, 20), (1, 18)]), WOOD[1]),
        (rect_px(9, 8, 33, 15), STEEL[1]),
        (rect_px(9, 8, 33, 10), STEEL[2]),
        (rect_px(13, 11, 34, 12), STEEL[0]),
        (rect_px(9, 15, 15, 19), STEEL[0]),
        (rect_px(30, 8, 34, 15), STEEL[0]),
    ])
    # Repeater: long thin barrel, drum magazine
    _weapon(m, tmp, "weapon_repeater", 38, 22, [
        (poly_px([(2, 11), (12, 10), (10, 20), (5, 20)]), STEEL[0]),
        (rect_px(8, 7, 24, 13), STEEL[1]),
        (rect_px(8, 7, 24, 9), STEEL[2]),
        (rect_px(22, 9, 37, 11), STEEL[2]),
        (ellipse_px(16, 15, 4, 4), BRASS[1]),
        (ellipse_px(15, 14, 1.6, 1.6), BRASS[2]),
    ])
    # Longshot: rifle with a scope
    _weapon(m, tmp, "weapon_longshot", 44, 20, [
        (poly_px([(1, 9), (14, 9), (14, 13), (6, 17), (1, 16)]), WOOD[1]),
        (rect_px(2, 9, 14, 10), WOOD[2]),
        (rect_px(13, 9, 30, 13), WOOD[0]),
        (rect_px(13, 9, 43, 11), STEEL[1]),
        (rect_px(15, 4, 27, 7), STEEL[0]),
        (rect_px(16, 4, 26, 5), STEEL[2]),
        (rect_px(18, 7, 20, 9), STEEL[0]),
    ])
    # Ember launcher: wide tube, glowing mouth
    _weapon(m, tmp, "weapon_launcher", 38, 24, [
        (rect_px(6, 14, 11, 22), WOOD[1]),
        (rect_px(4, 6, 33, 15), (88, 112, 74)),
        (rect_px(4, 6, 33, 8), (120, 148, 98)),
        (rect_px(31, 5, 37, 16), STEEL[0]),
        (rect_px(34, 7, 37, 14), (255, 140, 60)),
        (rect_px(12, 15, 16, 18), STEEL[0]),
    ])
    # Blade: straight sword, gold guard
    _weapon(m, tmp, "weapon_blade", 40, 14, [
        (rect_px(1, 6, 8, 9), WOOD[0]),
        (rect_px(7, 2, 10, 13), BRASS[1]),
        (poly_px([(10, 5), (34, 5), (39, 7), (34, 10), (10, 10)]), STEEL[2]),
        (rect_px(10, 7, 34, 8), STEEL[3]),
        (rect_px(10, 9, 34, 10), STEEL[1]),
    ])
    # Maul: long haft, heavy head
    _weapon(m, tmp, "weapon_maul", 40, 24, [
        (rect_px(1, 11, 30, 14), WOOD[1]),
        (rect_px(1, 11, 30, 12), WOOD[2]),
        (rect_px(27, 3, 39, 22), STEEL[1]),
        (rect_px(27, 3, 39, 6), STEEL[2]),
        (rect_px(27, 19, 39, 22), STEEL[0]),
        (rect_px(30, 9, 36, 16), BRASS[1]),
    ])
    # Thornspear: long shaft, leaf-shaped head
    _weapon(m, tmp, "weapon_spear", 50, 12, [
        (rect_px(1, 5, 38, 7), WOOD[1]),
        (rect_px(1, 5, 38, 6), WOOD[2]),
        (rect_px(34, 4, 37, 8), (60, 120, 60)),
        (poly_px([(37, 6), (42, 2), (49, 6), (42, 10)]), STEEL[2]),
        (rect_px(39, 5, 48, 6), STEEL[3]),
    ])


# --------------------------------------------------------------------------
def snapshot_refs():
    """Copy the pre-remake sprites into art_ref/ once."""
    n = 0
    for src in sorted(SPRITES.rglob("*.png")):
        if Path(src).stem.startswith("weapon_"):
            continue                       # drawn here, nothing to keep
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
                    help="sprite paths under assets/sprites/, e.g. gen/rock_a.png, "
                         "or 'weapons'")
    args = ap.parse_args()

    snapshot_refs()
    every = sorted(str(p.relative_to(REF)) for p in REF.rglob("*.png"))
    targets = args.only or every + ["weapons"]

    m = PixelMCP()
    with tempfile.TemporaryDirectory(prefix="slimer-pixelart-") as td:
        tmp = Path(td)
        for rel in targets:
            if rel == "weapons":
                draw_weapons(m, tmp)
                print("  drew      weapons")
                continue
            pixelize(m, rel, tmp)
            print(f"  pixelized {rel}")


if __name__ == "__main__":
    main()
