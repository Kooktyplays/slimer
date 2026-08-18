# Slimer

An endless, procedurally generated top-down forest roguelike, built in
**Godot 4.4.1**. Six enemy colours, five bosses, eleven abilities of which you
carry two, and a forest generated fresh from a seed every run.

**Free — may be shared, not sold.** See [Licensing](#licensing).

| | |
| --- | --- |
| Play in your browser | *(link added when the site is deployed)* |
| Download | [Releases](../../releases/latest) — macOS, Windows, Linux |
| Engine | Godot 4.4.1 |
| Scale | 60 GDScript files, ~11,400 lines, 26 scenes, 88 sprites, 46 sound effects |

## What it is

You start with one pistol and exactly two abilities. Waves of coloured slimes
come for you; every fifth wave is a mini-boss and every twentieth a major boss,
and each boss is followed by a shop where your coins buy upgrades you cannot all
afford. Death takes the money and the upgrades — only Essence survives, and that
unlocks new options for the next run. There is no final wave.

A few ideas the whole design hangs on:

- **Difficulty is a threat budget, not HP scaling.** Each wave gets
  `4 + 2.1w + 0.075w²` threat to spend, while per-enemy stats are hard capped
  (HP ×3.2, damage ×2.4, speed ×1.45). Late waves are a bigger, nastier crowd,
  not the same slime with a longer health bar.
- **Colour is a promise.** Each colour's behaviour and stats live in one table
  entry so they cannot drift apart. Learn a colour once and it means the same
  thing at wave 40.
- **Brown and grey stop you, green does not.** Trees, rocks and logs block;
  grass, bushes and ferns are cover you run through. You never have to test a
  bush to find out.
- **Every heavy attack is telegraphed**, and the radial burst always leaves a
  gap. A perfect ring is a damage tax; a ring with a seam is a decision.

## Repository layout

```
game/     the Godot project — this is the work
site/     the website: a WebGL explainer plus the playable browser build
```

`build/`, `2d-project-assets/` and the generated site assets are gitignored;
see `.gitignore` for why.

## Running it

```bash
G="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
cd game

$G --path .                                          # play
$G --editor --path .                                 # edit

./tools/check.sh                                     # boots clean, 0 errors
$G --headless --path . -- tests                      # 1452 logic assertions
$G --headless --path . --script res://tests/test_forest.gd   # 200-seed sweep
$G --headless --fixed-fps 60 --path . -- sim         # plays 22 waves headless
$G --path . --resolution 1600x900 -- perf            # frame timing
$G --path . --resolution 1600x900 -- visual          # screenshots + assertions

./tools/build.sh                                     # export all four platforms
```

Assets are generated, not hand-drawn, and regenerate deterministically:

```bash
python3 tools/copy_assets.py && python3 tools/gen_art.py && python3 tools/gen_sfx.py
```

## Testing

The suite asserts effects rather than flags, which is how several real bugs were
found. The pause test used to assert `get_tree().paused == true` — which was
true the entire time the world kept moving; it now samples enemy and player
positions and asserts they do not change.

- boot: 0 errors
- logic: 1452 assertions
- forest: 200 seeds, all valid on the first attempt, ~74 ms each
- sim: 22 waves headless with real input, through three mini-bosses, the wave-20
  major, four shops, the elite unlock and every enemy colour
- perf: 55 enemies + a major boss + 1251 props at p95 4.2 ms against a 16.6 ms
  budget

`game/GAME_GUIDE.md` walks through every system. `HANDOVER.md` documents the
environment, the load-bearing architectural decisions and ten fixed bugs that
are easy to reintroduce.

## Known gaps

- Gamepad support is implemented but has only ever been tested in code, never on
  physical hardware.
- Steamworks is not integrated — no achievements, overlay or cloud saves.
- macOS builds are ad-hoc signed but not notarised, so Gatekeeper will block a
  downloaded copy until you right-click → Open.

## Licensing

**The code is MIT. The art is not.**

Some sprites derive from GDQuest's *Your First 2D Game With Godot 4 — 2D project
assets*, licensed **CC BY-NC-SA 4.0**. NonCommercial covers modified assets too,
so the six hue-rotated enemy colours are as restricted as the original slime.

**This game may be shared freely but may not be sold**, and may not carry ads or
any other monetisation, while those assets remain in the build. Free
distribution — including free on Steam — is fine and compliance is already done.

Ten files are pack-derived. Everything else — all five bosses, every other prop,
the ground tiles, every UI icon, and all 46 sound effects — is original generated
work and carries no such restriction.

[`game/LICENSE-ASSETS.md`](game/LICENSE-ASSETS.md) carries the required
attribution block, the per-file statement of changes, and the full breakdown.
The in-game credits screen carries the visible attribution the licence demands;
there is a comment in `ui/credits_screen.gd` asking you not to trim it.
