#!/usr/bin/env python3
"""Remake the game's sprites as pixel art with the PixelLab API.

Every sprite keeps its filename, canvas size and on-canvas footprint, so no
scene, hitbox or face offset has to change. Art is generated at 1/PX scale and
blown up with NEAREST, so one art pixel is PX game pixels everywhere.

    PIXELLAB_API_KEY=... python3 tools/gen_pixellab.py          # generate + apply
    python3 tools/gen_pixellab.py --list                          # manifest + cost
    python3 tools/gen_pixellab.py --dry-run                       # no API calls
    python3 tools/gen_pixellab.py --only slime_body boss_toad_body --force

Layout (tools/pixellab/ has a .gdignore so Godot never imports it):
    ref/   the sprites as they were before the remake. Snapshotted on the first
           run; used for canvas size, footprint and as the init image.
    raw/   PixelLab's output, exactly as returned. Committed - it is the source
           of truth, so re-running only re-does post-processing and costs
           nothing. --force (or deleting a file) buys a new generation.

Pack-derived sprites (RIGHTS.md) are generated from text alone - no init
image - so the results are not derivatives of the CC BY-NC-SA pack.

Run order if regenerating everything: copy_assets.py, gen_art.py, then this
(it overwrites what gen_art.py wrote).
"""
from __future__ import annotations

import argparse
import base64
import colorsys
import io
import json
import math
import os
import shutil
import sys
import time
import urllib.error
import urllib.request
import zlib
from dataclasses import dataclass, field
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SPRITES = ROOT / "assets" / "sprites"
WORK = Path(__file__).resolve().parent / "pixellab"
REF = WORK / "ref"
RAW = WORK / "raw"

API_URL = os.environ.get("PIXELLAB_API_URL", "https://api.pixellab.ai/v1")
PX = 2                       # game pixels per art pixel
MIN_SIDE = 32                # pixflux minimum area is 32x32
MAX_AREA = 400 * 400

# One look for the whole game. Values are PixelLab's enums.
STYLE = {
    "outline": "selective outline",
    "shading": "basic shading",
    "detail": "medium detail",
}
NEGATIVE = "blurry, gradient background, text, watermark, frame, border, multiple objects"


@dataclass
class Spec:
    name: str                     # raw cache key
    out: str                      # path under assets/sprites/
    prompt: str
    init: bool = True             # use the reference as init image
    view: str | None = "low top-down"
    white: bool = False           # greyscale-to-white: tinted in-engine
    align: str = "center"         # "center" or "bottom" within the ref footprint
    background: bool = False      # opaque output (ground tiles)
    strength: int = 300           # init_image_strength, 1-999
    extra: dict = field(default_factory=dict)


def S(name, prompt, **kw) -> Spec:
    out = kw.pop("out", f"gen/{name}.png")
    return Spec(name, out, prompt, **kw)


PACK = dict(init=False)           # pack-derived: text-only generation
PROP = dict(align="bottom")
ICON = dict(white=True, view=None, align="center",
            extra={"outline": "single color outline"})
EYES = dict(view=None)

SPECS: list[Spec] = [
    # -- characters ---------------------------------------------------------
    S("slime_body", "cute round green slime blob, glossy jelly body with a "
      "light highlight spot, no eyes, no face, no mouth", out="slime_body.png", **PACK),
    S("slime_face", "two small black dot eyes and a tiny smile, cute face "
      "only, nothing else", out="slime_face.png", **PACK, **EYES),
    S("boo_body", "white rounded square ghost blob body, soft and squishy, "
      "plain white, no face", out="boo_body.png", white=True, **PACK),
    S("boo_face", "two big black eyes with white shine and a small happy "
      "mouth, cute face only, nothing else", out="boo_face.png", **PACK, **EYES),
    S("eyes_angry", "two angry dark green slanted slit eyes, face only", **EYES),
    S("eyes_dead", "two dark green X eyes, knocked out, face only", **EYES),
    S("eyes_boss", "two dark slanted eyes with glowing yellow pupils, face only", **EYES),
    *[S(f"elite_crown_{c}", f"spiky golden crown with a {c} gem in the middle, "
        "wide and low", align="bottom")
      for c in ("green", "red", "blue", "yellow", "purple", "orange")],

    # -- bosses -------------------------------------------------------------
    S("boss_bramble_body", "angry thorny bramble bush monster, round brown "
      "seed body wrapped in green thorny vines, on short root legs", **PROP),
    S("boss_bramble_eyes", "two round glowing green eyes, face only", **EYES),
    S("boss_toad_body", "giant fat green toad boss with dark spots and pale "
      "belly, sitting, front view", **PROP),
    S("boss_toad_eyes", "two big yellow toad eyes with vertical black slit "
      "pupils, face only", **EYES),
    S("boss_wisp_body", "purple ghost wisp spirit with a glowing orb on top "
      "and wavy tentacle bottom, two floating hands"),
    S("boss_wisp_eyes", "two white eyes with purple pupils, face only", **EYES),
    S("boss_oak_body", "huge ancient oak tree monster boss, thick trunk, wide "
      "green canopy, gnarled root legs", **PROP),
    S("boss_oak_eyes", "two big round orange glowing eyes with dark rims, "
      "face only", **EYES),
    S("boss_sovereign_body", "giant purple slime king boss wearing a golden "
      "crown with blue gems, glowing purple spots on body", **PROP),
    S("boss_sovereign_eyes", "two large round black eyes with yellow glowing "
      "rings, face only", **EYES),

    # -- forest props -------------------------------------------------------
    S("pine_tree", "tall green pine tree with short brown trunk",
      out="pine_tree.png", **PACK, **PROP),
    S("tree_round_a", "round leafy green deciduous tree with brown trunk", **PROP),
    S("tree_round_b", "round leafy green oak tree, slightly lopsided canopy, "
      "brown trunk", **PROP),
    S("tree_dead", "dead leafless brown tree with bare twisted branches", **PROP),
    S("bush_a", "round green leafy bush", **PROP),
    S("bush_b", "green berry bush with small red berries", **PROP),
    S("bush_c", "small round green shrub", **PROP),
    S("rock_a", "grey boulder rock", **PROP),
    S("rock_b", "large flat grey rock", **PROP),
    S("rock_c", "small grey stone", **PROP),
    S("log_a", "fallen brown tree log lying on its side", **PROP),
    S("log_b", "fallen mossy tree log with green moss on top", **PROP),
    S("stump", "cut tree stump with rings on top", **PROP),
    S("fern", "green fern plant", **PROP),
    S("flower_a", "small yellow flower", **PROP),
    S("flower_b", "small pink flower", **PROP),
    S("grass_a", "small tuft of green grass", **PROP),
    S("grass_b", "small tuft of tall green grass blades", **PROP),
    S("grass_c", "small sparse tuft of green grass", **PROP),
    S("mushroom", "two small red mushrooms with white spots", **PROP),
    S("pebbles", "cluster of three small grey pebbles", **PROP),
    S("lilypad", "green lily pad floating, top view", view="high top-down"),
    S("reeds", "cattail reeds, tall thin green stems with brown tops", **PROP),
    S("campfire", "small campfire with orange flame on crossed logs", **PROP),
    S("shop_lantern", "wooden post lantern with glowing warm yellow light", **PROP),

    # -- weapons, projectiles, pickups --------------------------------------
    S("pistol", "chunky blue toy blaster pistol, side view, pointing right",
      out="pistol.png", view="side", **PACK),
    S("projectile", "glowing yellow-orange energy bullet streaking right, "
      "side view", out="projectile.png", view="side", **PACK),
    S("muzzle_flash", "bright yellow muzzle flash burst pointing right",
      out="muzzle_flash.png", view="side", **PACK),
    S("thorn", "green thorn spike projectile pointing right", view="side"),
    S("boss_orb", "glowing purple magic orb"),
    S("essence", "purple crystal gem shard", view="side"),
    S("coin", "shiny gold coin, front view", out="gen/coin_strip.png", view="side"),
    *[S(f"potion_{c}", f"small round glass potion bottle with {c} liquid and a "
        "cork", view="side", **PACK)
      for c in ("red", "blue", "purple", "green", "yellow")],

    # -- UI (white, tinted by UITheme.icon) ---------------------------------
    S("crosshair", "aiming crosshair reticle, circle with four ticks", **ICON),
    S("icon_ammo", "bullet ammo icon", **ICON),
    S("icon_coin", "coin with a vertical slot icon", **ICON),
    S("icon_dash", "three forward chevron arrows dash icon", **ICON),
    S("icon_decoy", "little ghost decoy icon", **ICON),
    S("icon_essence", "diamond crystal icon", **ICON),
    S("icon_grenade", "round bomb grenade with fuse icon", **ICON),
    S("icon_heal", "plus cross healing icon", **ICON),
    S("icon_heart", "heart icon", **ICON),
    S("icon_lifesteal", "heart with a fang bite icon", **ICON),
    S("icon_lightning", "lightning bolt icon", **ICON),
    S("icon_nova", "radial starburst explosion icon", **ICON),
    S("icon_orbital", "small orb orbiting a ring icon", **ICON),
    S("icon_rapidfire", "three bullets in a row rapid fire icon", **ICON),
    S("icon_shield", "shield icon", **ICON),
    S("icon_timeslow", "hourglass icon", **ICON),

    # -- particles ----------------------------------------------------------
    S("leaf_0", "small light green leaf", view=None),
    S("leaf_1", "small green leaf", view=None),
    S("leaf_2", "small yellow-brown autumn leaf", view=None),

    # -- ground: one quadrant, mirrored into a seamless tile ----------------
    *[S(n, f"{d}, top-down ground texture, fills the whole image, no objects",
        view="high top-down", background=True, strength=500)
      for n, d in (("ground_grass", "dark green forest grass"),
                   ("ground_clearing", "light green meadow grass"),
                   ("ground_path", "brown dirt path"),
                   ("ground_water", "blue pond water with small ripples"))],

    # -- app icon (generated at 1/4, the pack slime it used to show is gone) -
    S("app_icon", "cute green slime with two black dot eyes and a smile, "
      "sitting on a dark green round badge, game app icon", view=None, **PACK),
]

# Sprites made from another generated sprite instead of their own call.
# enemy colour -> (target hue deg, saturation mul, value mul); same table as
# gen_art.ENEMY_TINTS so "colour is a promise" still holds.
ENEMY_TINTS = {
    "green": (101, 1.00, 1.00),
    "red": (357, 1.00, 0.94),
    "blue": (207, 0.96, 1.02),
    "yellow": (46, 1.00, 1.06),
    "purple": (280, 0.90, 0.98),
    "orange": (24, 1.02, 1.02),
}

# Soft white textures that are tinted, scaled and faded in-engine. A model has
# nothing to add to a white circle, so these are redrawn on the pixel grid.
PROCEDURAL = ["glow", "ring", "shockwave", "spark", "spark_square", "orb",
              "ground_shadow", "impact_circle"]


# --------------------------------------------------------------------------
# helpers
# --------------------------------------------------------------------------
def seed_for(name: str) -> int:
    return zlib.crc32(name.encode()) % 1_000_000


def gen_size(spec: Spec, ref: Image.Image) -> tuple[int, int]:
    scale = 4 if spec.name == "app_icon" else PX
    if spec.name.startswith("ground_"):
        scale = PX * 2                      # a quadrant: tile is mirrored 2x2
    if spec.name == "coin":
        w, h = math.ceil(30 / PX), math.ceil(30 / PX)   # one frame
    else:
        w, h = math.ceil(ref.width / scale), math.ceil(ref.height / scale)
    w, h = max(w, MIN_SIDE), max(h, MIN_SIDE)
    while w * h > MAX_AREA:
        w, h = math.ceil(w * 0.9), math.ceil(h * 0.9)
    return w, h


def ref_for(spec: Spec) -> Image.Image:
    return Image.open(REF / spec.out).convert("RGBA")


def init_image(spec: Spec, ref: Image.Image, size: tuple[int, int]) -> Image.Image:
    """The reference shrunk onto the generation canvas, same relative layout."""
    if spec.name == "coin":
        ref = ref.crop((0, 0, 30, 30))
    if spec.background:                     # the quadrant that gets mirrored
        return ref.crop((0, 0, ref.width // 2, ref.height // 2)).resize(size, Image.LANCZOS)
    k = max(ref.width / size[0], ref.height / size[1])
    small = ref.resize((max(1, round(ref.width / k)), max(1, round(ref.height / k))),
                       Image.LANCZOS)
    canvas = Image.new("RGBA", size, (0, 0, 0, 0))
    canvas.alpha_composite(small, ((size[0] - small.width) // 2,
                                   (size[1] - small.height) // 2))
    return canvas


def b64png(img: Image.Image) -> str:
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    return base64.b64encode(buf.getvalue()).decode()


def call_pixflux(spec: Spec, size, init: Image.Image | None, key: str) -> Image.Image:
    body = {
        "description": spec.prompt,
        "negative_description": NEGATIVE,
        "image_size": {"width": size[0], "height": size[1]},
        "text_guidance_scale": 8,
        "no_background": not spec.background,
        "seed": seed_for(spec.name),
        **STYLE,
        **spec.extra,
    }
    if spec.view:
        body["view"] = spec.view
    if init is not None:
        body["init_image"] = {"type": "base64", "base64": b64png(init)}
        body["init_image_strength"] = spec.strength

    data = json.dumps(body).encode()
    for attempt in range(6):
        req = urllib.request.Request(
            f"{API_URL}/generate-image-pixflux", data=data, method="POST",
            headers={"Authorization": f"Bearer {key}",
                     "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=180) as resp:
                payload = json.load(resp)
            break
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")[:400]
            if e.code in (429, 500, 502, 503, 504, 529) and attempt < 5:
                wait = 2 ** (attempt + 1)
                print(f"    {e.code}, retrying in {wait}s")
                time.sleep(wait)
                continue
            raise SystemExit(f"PixelLab {e.code} on {spec.name}: {detail}")
    b64 = payload["image"]["base64"]
    if b64.startswith("data:"):
        b64 = b64.split(",", 1)[1]
    usd = payload.get("usage", {}).get("usd")
    if usd is not None:
        print(f"    ${usd:.4f}")
    return Image.open(io.BytesIO(base64.b64decode(b64))).convert("RGBA")


def crisp(img: Image.Image) -> Image.Image:
    """Binary alpha - pixel art has no half-transparent edge pixels."""
    r, g, b, a = img.split()
    a = a.point(lambda v: 255 if v >= 128 else 0)
    return Image.merge("RGBA", (r, g, b, a))


def trimmed(img: Image.Image) -> Image.Image:
    box = img.getchannel("A").getbbox()
    return img.crop(box) if box else img


def to_white(img: Image.Image) -> Image.Image:
    """Keep the shading as luminance, brightest pixel pure white."""
    lum = img.convert("L")
    hi = max(1, lum.getextrema()[1])
    lum = lum.point(lambda v: min(255, round(v * 255 / hi)))
    return Image.merge("RGBA", (lum, lum, lum, img.getchannel("A")))


def place(art: Image.Image, ref: Image.Image, align: str, scale: int = PX) -> Image.Image:
    """Blow art up by an integer factor and sit it on the ref's footprint."""
    canvas = Image.new("RGBA", ref.size, (0, 0, 0, 0))
    box = ref.getchannel("A").getbbox() or (0, 0, ref.width, ref.height)
    k = scale
    while k > 1 and (art.width * k > ref.width or art.height * k > ref.height):
        k -= 1
    big = art.resize((art.width * k, art.height * k), Image.NEAREST)
    if big.width > ref.width or big.height > ref.height:   # still too big at 1x
        f = min(ref.width / big.width, ref.height / big.height)
        big = big.resize((max(1, int(big.width * f)), max(1, int(big.height * f))),
                         Image.NEAREST)
    cx = (box[0] + box[2]) // 2
    x = min(max(0, cx - big.width // 2), ref.width - big.width)
    if align == "bottom":
        y = box[3] - big.height
    else:
        y = (box[1] + box[3]) // 2 - big.height // 2
    y = min(max(0, y), ref.height - big.height)
    canvas.alpha_composite(big, (x, y))
    return canvas


def dominant_hue(img: Image.Image) -> float:
    xs, ys = 0.0, 0.0
    for r, g, b, a in img.get_flattened_data():
        if a < 128:
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        w = s * v
        xs += math.cos(h * math.tau) * w
        ys += math.sin(h * math.tau) * w
    return (math.atan2(ys, xs) / math.tau) % 1.0


def recolor(src: Image.Image, src_hue: float, hue_deg: float, sm: float, vm: float):
    delta = hue_deg / 360.0 - src_hue
    out = []
    for r, g, b, a in src.get_flattened_data():
        if a == 0:
            out.append((0, 0, 0, 0))
            continue
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        nr, ng, nb = colorsys.hsv_to_rgb((h + delta) % 1.0, min(1.0, s * sm), min(1.0, v * vm))
        out.append((round(nr * 255), round(ng * 255), round(nb * 255), a))
    img = Image.new("RGBA", src.size)
    img.putdata(out)
    return img


def save(img: Image.Image, rel: str):
    path = SPRITES / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    img.save(path)


# --------------------------------------------------------------------------
# post-processing: raw PixelLab output -> game sprite(s)
# --------------------------------------------------------------------------
def apply(spec: Spec, raw: Image.Image):
    ref = ref_for(spec)
    if spec.background:
        q = raw.convert("RGBA").resize((raw.width * PX, raw.height * PX), Image.NEAREST)
        tile = Image.new("RGBA", (q.width * 2, q.height * 2))
        tile.paste(q, (0, 0))
        tile.paste(q.transpose(Image.FLIP_LEFT_RIGHT), (q.width, 0))
        tile.paste(q.transpose(Image.FLIP_TOP_BOTTOM), (0, q.height))
        tile.paste(q.transpose(Image.ROTATE_180), (q.width, q.height))
        save(tile.resize(ref.size, Image.NEAREST), spec.out)
        return

    art = trimmed(crisp(raw))
    if spec.white:
        art = to_white(art)

    if spec.name == "coin":
        fw, n = 30, 6
        frame_ref = ref.crop((0, 0, fw, ref.height))
        strip = Image.new("RGBA", ref.size, (0, 0, 0, 0))
        for i in range(n):
            sx = max(1 / art.width, abs(math.cos(math.pi * i / n)))
            squashed = art.resize((max(1, round(art.width * sx)), art.height), Image.NEAREST)
            strip.alpha_composite(place(squashed, frame_ref, "center"), (i * fw, 0))
        save(strip, spec.out)
        return

    if spec.name == "app_icon":
        icon = place(art, ref, "center", scale=4)
        save(icon, spec.out)
        icon.save(SPRITES / "gen" / "slimer.ico",
                  sizes=[(s, s) for s in (16, 32, 48, 64, 128, 256)])
        write_icns(icon)
        return

    save(place(art, ref, spec.align), spec.out)

    if spec.name == "slime_body":
        body = Image.open(SPRITES / spec.out).convert("RGBA")
        hue = dominant_hue(body)
        for colour, (h, sm, vm) in ENEMY_TINTS.items():
            save(recolor(body, hue, h, sm, vm), f"gen/enemy_{colour}_body.png")


def write_icns(icon: Image.Image):
    import subprocess

    iconset = SPRITES / "gen" / "slimer.iconset"
    shutil.rmtree(iconset, ignore_errors=True)
    iconset.mkdir()
    for s in (16, 32, 128, 256, 512):
        icon.resize((s, s), Image.NEAREST).save(iconset / f"icon_{s}x{s}.png")
        icon.resize((s * 2, s * 2), Image.NEAREST).save(iconset / f"icon_{s}x{s}@2x.png")
    try:
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o",
                        str(SPRITES / "gen" / "slimer.icns")],
                       check=True, capture_output=True)
    except (FileNotFoundError, subprocess.CalledProcessError) as exc:
        print(f"    (no .icns: {exc}) - kept the existing slimer.icns")
    shutil.rmtree(iconset, ignore_errors=True)


def gen_procedural():
    """Pixel-grid versions of the white FX textures. No API calls."""
    def pixel_disc(size, rx, ry, inner=0.0, alpha_steps=None):
        w, h = math.ceil(size[0] / PX), math.ceil(size[1] / PX)
        img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        px = img.load()
        for y in range(h):
            for x in range(w):
                d = math.hypot((x + 0.5 - w / 2) / (rx / PX), (y + 0.5 - h / 2) / (ry / PX))
                if d > 1.0 or d < inner:
                    continue
                a = 255
                if alpha_steps:
                    t = (1.0 - d) ** 2.2
                    a = round(round(t * alpha_steps) / alpha_steps * 255)
                    if a == 0:
                        continue
                px[x, y] = (255, 255, 255, a)
        return img.resize((w * PX, h * PX), Image.NEAREST).crop((0, 0, *size))

    save(pixel_disc((128, 128), 64, 64, alpha_steps=5), "gen/glow.png")
    save(pixel_disc((160, 160), 78, 78, inner=66 / 78), "gen/ring.png")
    save(pixel_disc((192, 192), 94, 94, inner=72 / 94), "gen/shockwave.png")
    save(pixel_disc((16, 16), 7, 7), "gen/spark.png")
    sq = Image.new("RGBA", (14, 14), (0, 0, 0, 0))
    ImageDraw.Draw(sq).rectangle([2, 2, 11, 11], fill=(255, 255, 255, 255))
    save(sq, "gen/spark_square.png")
    orb = pixel_disc((28, 28), 12, 12)
    ImageDraw.Draw(orb).rectangle([8, 8, 11, 11], fill=(255, 255, 255, 255))
    save(orb, "gen/orb.png")
    save(pixel_disc((64, 64), 30, 30), "impact_circle.png")
    shadow = pixel_disc((84, 52), 40, 24)
    r, g, b, a = shadow.split()
    zero = Image.new("L", shadow.size, 0)
    save(Image.merge("RGBA", (zero, zero, zero, a)), "ground_shadow.png")


# --------------------------------------------------------------------------
def snapshot_refs():
    """Copy the pre-remake sprites into ref/ once, so reruns stay stable."""
    n = 0
    for spec in SPECS:
        dst = REF / spec.out
        if dst.exists():
            continue
        src = SPRITES / spec.out
        if not src.exists():
            raise SystemExit(f"missing reference sprite {src}")
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        n += 1
    if n:
        print(f"snapshotted {n} reference sprites -> {REF.relative_to(ROOT)}")


def contact_sheet(specs: list[Spec], path: Path):
    """Before/after pairs, for eyeballing a run."""
    cell = 160
    rows = []
    for spec in specs:
        before, after = REF / spec.out, SPRITES / spec.out
        if before.exists() and after.exists():
            rows.append((spec.name, Image.open(before).convert("RGBA"),
                         Image.open(after).convert("RGBA")))
    cols = 4
    sheet = Image.new("RGBA", (cols * cell * 2, math.ceil(len(rows) / cols) * (cell + 12)),
                      (70, 74, 82, 255))
    d = ImageDraw.Draw(sheet)
    for i, (name, a, b) in enumerate(rows):
        x0, y0 = (i % cols) * cell * 2, (i // cols) * (cell + 12)
        for j, im in enumerate((a, b)):
            im = im.copy()
            im.thumbnail((cell - 6, cell - 6), Image.NEAREST)
            sheet.alpha_composite(im, (x0 + j * cell + 3, y0 + 3))
        d.text((x0 + 3, y0 + cell - 2), name, fill=(255, 255, 255, 255))
    sheet.save(path)
    print(f"comparison sheet -> {path}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--only", nargs="+", metavar="NAME", help="spec names to process")
    ap.add_argument("--force", action="store_true", help="regenerate even if raw/ has it")
    ap.add_argument("--dry-run", action="store_true",
                    help="no API calls: write init images to pixellab/dryrun/")
    ap.add_argument("--list", action="store_true", help="print the manifest and exit")
    ap.add_argument("--sheet", type=Path, help="write a before/after contact sheet here")
    args = ap.parse_args()

    specs = SPECS
    if args.only:
        known = {s.name for s in SPECS}
        unknown = set(args.only) - known
        if unknown:
            raise SystemExit(f"unknown spec(s): {', '.join(sorted(unknown))}")
        specs = [s for s in SPECS if s.name in args.only]

    snapshot_refs()

    if args.list:
        total = 0.0
        for s in specs:
            size = gen_size(s, ref_for(s))
            total += 0.007 + 0.0000003 * size[0] * size[1]   # rough, from the price table
            src = "init" if s.init else "text"
            print(f"{s.name:22} {size[0]:>3}x{size[1]:<3} {src:4}  {s.out}")
        print(f"{len(specs)} generations, roughly ${total:.2f} if none are cached; "
              f"plus {len(ENEMY_TINTS)} enemy recolours and {len(PROCEDURAL)} procedural FX")
        return

    key = os.environ.get("PIXELLAB_API_KEY", "")
    RAW.mkdir(parents=True, exist_ok=True)
    pending = [s for s in specs if args.force or not (RAW / f"{s.name}.png").exists()]
    if pending and not key and not args.dry_run:
        raise SystemExit(f"{len(pending)} sprite(s) need generating: set PIXELLAB_API_KEY "
                         "(pixellab.ai/account) or use --dry-run")

    for spec in specs:
        raw_path = RAW / f"{spec.name}.png"
        if spec in pending:
            ref = ref_for(spec)
            size = gen_size(spec, ref)
            init = init_image(spec, ref, size) if spec.init else None
            if args.dry_run:
                dry = WORK / "dryrun"
                dry.mkdir(exist_ok=True)
                if init is not None:
                    init.save(dry / f"{spec.name}.png")
                print(f"  would generate {spec.name} at {size[0]}x{size[1]}")
                continue
            print(f"  generating {spec.name} at {size[0]}x{size[1]}")
            call_pixflux(spec, size, init, key).save(raw_path)
        if raw_path.exists():
            apply(spec, Image.open(raw_path))

    if not args.only and not args.dry_run:
        gen_procedural()
        print("  procedural FX")
    if args.sheet:
        contact_sheet(specs, args.sheet)


if __name__ == "__main__":
    sys.exit(main())
