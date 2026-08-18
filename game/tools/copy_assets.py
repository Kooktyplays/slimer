#!/usr/bin/env python3
"""Copy the pristine GDQuest asset pack + music into the game project.

The originals in ../2d-project-assets and the root .mp3 files are never
modified. Potion filenames in the pack are mojibaked Portuguese
("po‡ֶo vermelha meio vazia.png"); they get ASCII names here so Godot's
importer and res:// paths stay sane.
"""
from __future__ import annotations

import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent      # game/
SRC = ROOT.parent / "2d-project-assets"            # Desktop/Slimer/2d-project-assets
MUSIC_SRC = ROOT.parent                            # Desktop/Slimer
SPRITES = ROOT / "assets" / "sprites"
MUSIC = ROOT / "assets" / "music"
SHADERS = ROOT / "assets" / "shaders"

# (relative source path, destination filename)
SPRITE_COPIES = [
    ("characters/slime/slime_body.png",         "slime_body.png"),
    ("characters/slime/slime_face.png",         "slime_face.png"),
    ("characters/ground_shadow.png",            "ground_shadow.png"),
    ("characters/happy_boo/square_body.png",    "boo_body.png"),
    ("characters/happy_boo/square_face.png",    "boo_face.png"),
    ("trees/pine_tree.png",                     "pine_tree.png"),
    ("pistol/pistol.png",                       "pistol.png"),
    ("pistol/projectile.png",                   "projectile.png"),
    ("pistol/muzzle_flash/muzzle_flash.png",    "muzzle_flash.png"),
    ("pistol/impact/circle.png",                "impact_circle.png"),
]

# Portuguese fill levels -> our suffixes.
# Only the full bottles, and only the three colours the game uses. Every pack
# file that ships is one more asset under CC BY-NC-SA that has to be attributed
# and that blocks a commercial release - see RIGHTS.md.
FILL_SUFFIX = {"": "full"}
COLOR_DIRS = {
    "Red potions": ("vermelha", "red"),
    "Blue potions": ("azul", "blue"),
    "Purple potions": ("roxa", "purple"),
}


def copy_potions() -> int:
    """Match potion PNGs by the Portuguese colour word, ignoring mojibake bytes."""
    n = 0
    for dirname, (pt_word, en_word) in COLOR_DIRS.items():
        d = SRC / "All Potions" / dirname
        if not d.is_dir():
            print(f"  !! missing {d}")
            continue
        for path in d.iterdir():
            if path.suffix.lower() != ".png" or pt_word not in path.name:
                continue
            # Everything after the colour word is the fill descriptor.
            tail = path.name.split(pt_word, 1)[1].removesuffix(".png").strip()
            suffix = FILL_SUFFIX.get(tail)
            if suffix is None:
                continue    # half/empty variants are deliberately not shipped
            shutil.copy2(path, SPRITES / f"potion_{en_word}_{suffix}.png")
            n += 1
    return n


def main() -> None:
    for d in (SPRITES, MUSIC, SHADERS):
        d.mkdir(parents=True, exist_ok=True)

    print("sprites:")
    for rel, dest in SPRITE_COPIES:
        src = SRC / rel
        if not src.exists():
            raise SystemExit(f"missing source asset: {src}")
        shutil.copy2(src, SPRITES / dest)
        print(f"  {dest}")

    print("potions:")
    print(f"  {copy_potions()} files")

    print("music:")
    for mp3 in sorted(MUSIC_SRC.glob("*.mp3")):
        dest = mp3.name.lower().replace(" ", "_")
        shutil.copy2(mp3, MUSIC / dest)
        print(f"  {dest}")


if __name__ == "__main__":
    main()
