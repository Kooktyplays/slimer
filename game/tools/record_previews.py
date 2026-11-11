#!/usr/bin/env python3
"""Record the ability and ultimate preview clips shown in the game's menus.

Each clip is the real game, staged by tests/ability_reel.gd and recorded with
Godot's Movie Maker, then trimmed and encoded with ffmpeg:

    python3 tools/record_previews.py                 # every ability and ultimate
    python3 tools/record_previews.py nova ult:vampire

Needs: Godot 4.4 (GODOT=path, default `godot`), ffmpeg with libtheora, and a
display - on a headless box it wraps itself in xvfb-run.

Output: assets/previews/<ability>.ogv and assets/previews/ult_<class>.ogv,
640x360, silent, Theora (the format Godot's VideoStreamPlayer plays natively).
Ability clips are cropped around the player; ultimate clips keep the whole
frame, because the cutscene is composed for the whole screen.
"""
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "assets" / "previews"
FPS = 30
WINDOW = (1280, 720)      # the game draws at 2/3 scale; a 640x360 crop is 1:1
CLIP = (640, 360)


def ability_ids() -> list[str]:
    src = (ROOT / "data" / "abilities_db.gd").read_text()
    block = re.search(r"const ORDER: Array\[String\] = \[(.*?)\]", src, re.S).group(1)
    return re.findall(r'"([a-z_]+)"', block)


def class_ids() -> list[str]:
    src = (ROOT / "data" / "classes_db.gd").read_text()
    consts = dict(re.findall(r'^const ([A-Z]+) := "([a-z_]+)"', src, re.M))
    block = re.search(r"const ORDER: Array\[String\] = \[(.*?)\]", src, re.S).group(1)
    return [consts[name] for name in re.findall(r"[A-Z]+", block)]


def godot_cmd() -> list[str]:
    godot = os.environ.get("GODOT", "godot")
    cmd = [godot, "--path", str(ROOT), "--resolution", "%dx%d" % WINDOW,
           "--rendering-driver", "opengl3", "--fixed-fps", str(FPS)]
    if not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
        cmd = ["xvfb-run", "-a", "-s", "-screen 0 %dx%dx24" % WINDOW] + cmd
    return cmd


def record(reel_id: str, tmp: Path) -> Path:
    avi = tmp / (reel_id.replace(":", "_") + ".avi")
    proc = subprocess.run(godot_cmd() + ["--write-movie", str(avi), "--", "reel", reel_id],
                          capture_output=True, text=True, timeout=600)
    log = proc.stdout + proc.stderr
    begin = re.search(r"\[reel\] begin_frame=(\d+)", log)
    end = re.search(r"\[reel\] end_frame=(\d+)", log)
    if not (begin and end and avi.exists()):
        raise SystemExit(f"recording {reel_id} failed:\n{log[-1500:]}")
    out = OUT / (("ult_" + reel_id[4:]) if reel_id.startswith("ult:") else reel_id)
    out = out.with_suffix(".ogv")
    start = int(begin.group(1)) / FPS
    length = (int(end.group(1)) - int(begin.group(1))) / FPS
    if reel_id.startswith("ult:"):
        vf = "scale=%d:%d:flags=lanczos" % CLIP
    else:
        vf = "crop=%d:%d" % CLIP           # centred on the player
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-ss", f"{start:.3f}",
                    "-t", f"{length:.3f}", "-i", str(avi), "-an", "-vf", vf,
                    "-c:v", "libtheora", "-q:v", "4", "-r", str(FPS), str(out)],
                   check=True)
    return out


def main(argv: list[str]) -> None:
    ids = argv or ability_ids() + ["ult:" + c for c in class_ids()]
    OUT.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="slimer-reel-") as td:
        for reel_id in ids:
            out = record(reel_id, Path(td))
            print(f"  {reel_id:18} -> {out.relative_to(ROOT)}  "
                  f"({out.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main(sys.argv[1:])
