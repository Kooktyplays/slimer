# Slimer — handover

Everything a fresh session needs to continue work on this project. Written
2026-08-17.

---

## 1. What this is

A complete, playable, procedurally generated top-down forest roguelike built in
**Godot 4.4.1**, from a brief asking for a full game (not a prototype) using an
existing asset pack and four music tracks the user supplied.

**Project root:** `/Users/tanavyedlapalli/Desktop/Slimer/`

```
Slimer/
├── 2d-project-assets/    ORIGINAL GDQuest pack — READ ONLY, never modify
├── *.mp3 (4)             user's music — READ ONLY, never modify
├── game/                 the Godot project (this is the work)
├── build/                exported builds (macos, windows, linux, web)
├── RIGHTS.md             asset licensing — READ THIS BEFORE ANY SHIP TALK
├── STEAM.md              Steam release walkthrough
└── HANDOVER.md           this file
```

Scale: **60 GDScript files, ~11,400 lines, 26 scenes**, 88 generated sprites,
46 synthesized sound effects.

Loose files at `Slimer/` root (`Slimer.app`, `Slimer.exe`, `slimer.html`,
`Slimer.pck`, `Slimer.console.exe`, `Slimer-macos.zip`) are **stale artifacts
from an early export** before the `build/` layout existed. They are not
referenced by anything and can be deleted.

---

## 2. Environment gotchas — read before running anything

| Thing | Reality |
| --- | --- |
| Godot binary | `/Users/tanavyedlapalli/Downloads/Godot.app/Contents/MacOS/Godot` (not in `/Applications`, not on PATH) |
| `timeout` command | **Does not exist on macOS.** Run in background and poll with a `for` loop, or the call hangs |
| Export templates | 4.4.1.stable, all platforms installed including web |
| Python | 3.14 with Pillow + numpy available |
| `--import` | Does **not** surface GDScript parse errors. Only *booting* does — use `tools/check.sh` |
| `class_name` scripts | Need a `--import` pass before `--script` runs can resolve them (global class cache) |
| Godot editor | **Rewrites `project.godot` and `export_presets.cfg` while running.** It has renamed presets and flipped settings mid-session. Don't trust CLI edits to those two files to survive |
| Exit warning | `1 resource still in use at exit` (the music stream) is a benign shutdown-order artifact. `tools/check.sh` filters it and fails on anything else |

---

## 3. Architecture

```
game/
├── autoload/   Events, Save, Pools, Audio, Game, DebugCapture  (in that order)
├── data/       all tuning + content tables, no nodes
├── world/      forest_generator, forest, wave_controller, run, prop_catalog, tutor
├── actors/     player, enemy, pickup, game_camera, bosses/
├── weapons/    gun, projectile
├── abilities/  ability_controller + grenade/orbital/decoy scenes
├── ui/         hud, menus, shop, ability_picker, keybinds_menu, credits, ui_theme
├── fx/         pooled impact/muzzle/burst/damage_number/ring_pulse
├── tests/      run_tests, sim_harness, visual_pass, perf_test, test_forest
└── tools/      gen_art.py, gen_sfx.py, copy_assets.py, build.sh, steam_build.sh, check.sh
```

**Load-bearing ideas — do not undo these without understanding why:**

- **`Game` owns state, `main.gd` owns nodes.** Game decides *what* state; Main
  listens to `Events.state_changed` and swaps scenes. This separation is what
  makes the headless sim possible (it drives real state with no UI).
- **`Events` is a global signal bus.** Actors never hold references to the HUD
  or run controller. Required for pooling to be safe.
- **Difficulty is a threat budget, not HP scaling.** `Balance.wave_budget(w)`;
  each enemy type costs threat. Stat growth is hard-capped (HP ×3.2 max). The
  brief explicitly rejected HP-sponge scaling.
- **Colour is a promise.** `data/enemy_types.gd` declares colour + behaviour +
  stats in one entry so they can't drift.
- **Everything in `data/` is pure data/static** — no nodes, so it's testable
  headlessly.

---

## 4. Bugs found and fixed — DO NOT REGRESS THESE

Each was subtle, took real work to find, and is easy to reintroduce.

### 4.1 Shop softlock (game-breaking)
`Game.leave_shop()` emitted `shop_closed` **before** clearing the SHOP phase.
Listeners queue the next wave on that signal, and the queue refuses to run
while phase is SHOP. The run parked forever after **every** shop.
**Fix:** set phase first, then emit. Order matters.

### 4.2 Enemy hitboxes were half their sprite size
`radius` was being multiplied by the visual `scale`, producing collision
circles ~half the drawn slime. Bullets visibly passed through enemies.
**Fix:** `radius` in `enemy_types.gd` / `boss_db.gd` is now the **final
world-space hit radius** and is explicitly NOT scaled. There are comments
saying so. Elites multiply by `ELITE_SCALE` only.

### 4.3 Bosses wedging on terrain (unwinnable runs)
A radius-130 boss jams between trees; it can't reach the player and the player
can't shoot through the trees pinning it.
**Fix:** `ForestGenerator.has_clearance()` / `nearest_open_for()` for
clearance-aware placement, plus stuck detection + reposition in `boss.gd`.
Enemies have the same (quieter) treatment.

### 4.4 Pause did nothing (reported 3×, two wrong fixes first)
`main.gd` sets `process_mode = ALWAYS` so it can read Escape while paused.
**`process_mode` INHERITS** — so `ScreenHolder` and the entire run scene under
it also became ALWAYS and ignored `get_tree().paused`. Menu appeared, world
kept playing.
**Fix:** `_screen_holder.process_mode = PAUSABLE` explicitly in `Main._ready()`.
Two earlier fixes were real but incomplete (shader `TIME` and GPU particles also
ignore pause independently — both still needed and still in).

### 4.5 Spitters fired 6× too fast
`_try_shoot` subtracted a fixed `LOD_FAR_INTERVAL` (0.1) per call, assuming
10 Hz. But `_think()` runs **every physics frame** within `LOD_NEAR` (900 px),
so the timer drained at 6/sec. 2.1 s cooldown became ~0.35 s.
**Fix:** `_attack_timer` decrements once per frame in `_physics_process` on
real scaled delta; `_try_shoot` only checks and resets.

### 4.6 Purple potion did nothing
Mechanism worked, design wasted it: both starting abilities refill in 3–7 s, so
you were always topped up and the potion was consumed for a "FULL" message.
**Fix:** `refill_all()` (all charges, both slots, cooldowns cleared) and
`Pickup._is_useful()` gates collection *and* the magnet — an unusable potion
dims, pauses its expiry, and waits. Same rule applied to red at full health.

### 4.7 Time-scale leak
Hit-stop set `Engine.time_scale = 0.25` and restored it via a tween owned by
the run node. Dying during hit-stop freed that node → game stuck at quarter
speed forever.
**Fix:** restore in `run.gd._exit_tree()`, use an `ignore_time_scale` scene
timer, and a 0.45 s cooldown so a swarm can't re-trigger it 20×/sec (that alone
made a crowded fight run in permanent slow motion).

### 4.8 Pooled physics bodies unparented mid-callback
~99 errors/run. Godot forbids reparenting a `CollisionObject2D` during a
physics callback, and bullets park themselves from `body_entered`.
**Fix:** `Pools.release()` marks inactive immediately but defers the unparent.
`release(node, immediate=true)` for teardown only.

### 4.9 UI panels never filled the screen
`set_anchors_preset()` recomputes offsets from the control's **current** size,
which is zero during `_ready()`. Panels baked zero-width offsets and never grew.
**Fix:** every UI file uses `set_anchors_and_offsets_preset()`. Don't switch back.

### 4.10 Potion sprites drew as a 3×3 grid
The pack's potion PNGs are 3×3 sprite sheets, not single bottles.
**Fix:** `gen_art.py::gen_potions()` slices the fullest 16×16 cell and scales 2×.

---

## 5. Two non-obvious implementation choices

**Bullets do their own swept collision** (`weapons/projectile.gd`).
`Area2D.body_entered` only fires on *entry*, which silently drops point-blank
shots (bullet spawns already overlapping) and fast ones (steps over the target
in one frame). The projectile samples its circle along the segment it travels
each frame, every 28 px. It also turned out **faster** than 90 monitoring areas
in the broadphase — p95 went 9.1 ms → 4.2 ms.

**Foliage animates from a global `anim_time`, not shader `TIME`.** `TIME` keeps
running while the tree is paused. `Game._process` advances the shader global and
stops when paused. Declared in `project.godot` under `[shader_globals]`. Any new
animated shader must use it.

---

## 6. Licensing — the most important section

**The GDQuest asset pack is CC BY-NC-SA 4.0. The game CANNOT BE SOLD.**

GDQuest split it: **code MIT, game assets CC BY-NC-SA 4.0**. NonCommercial
covers **modified** assets too, so the six hue-rotated enemy colours are just as
restricted as the original slime.

- Free release (including free on Steam): fine, compliance is done.
- Selling, paid DLC, ads: **prohibited** while any pack art is in the build.

**Compliance already in place — do not remove:**
- `game/LICENSE-ASSETS.md` — the required LICENSE file, full attribution block,
  per-file table of changes, MIT text for the code portion.
- In-game **credits screen** carries the visible attribution the licence
  demands (asset name, 3 links, statement of changes, "may be shared, not
  sold"). There's a comment in `ui/credits_screen.gd` saying not to trim it.
- Unused pack files were deleted; pack sprites went **31 → 13**.

**Still pack-derived (10 files):** `slime_body`, `slime_face`, `boo_body`,
`boo_face`, `pistol`, `projectile`, `muzzle_flash`, `impact_circle`,
`pine_tree`, `ground_shadow`, + 3 potion bottles.

**Original and unrestricted (88 sprites, 46 sounds):** all five bosses, every
other prop, all ground tiles, every UI icon, coins, essence, particles, app
icons, all SFX.

**To enable selling:** replace those six sprite families. `gen_art.py` already
produces 88 sprites in that exact style, so it's bounded work. Or email GDQuest
for a commercial licence.

The author name **"Tanav Yedlapalli"** was inferred from the home directory
path. It appears in `ui/credits_screen.gd` (const `AUTHOR`) and
`LICENSE-ASSETS.md`. **Confirm it's correct** — it's part of a licence notice.

---

## 7. Commands

```bash
G="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"
cd ~/Desktop/Slimer/game

# run
$G --path .
$G --editor --path .

# verify (all of these should pass)
./tools/check.sh                                           # boots clean
$G --headless --path . -- tests                            # 1452 logic assertions
$G --headless --path . --script res://tests/test_forest.gd # 200-seed sweep
$G --headless --fixed-fps 60 --path . -- sim               # 22 waves, loop intact
$G --path . --resolution 1600x900 -- perf                  # frame timing
$G --path . --resolution 1600x900 -- visual                # screenshots + assertions

# regenerate assets (deterministic)
python3 tools/copy_assets.py && python3 tools/gen_art.py && python3 tools/gen_sfx.py

# build
./tools/build.sh              # all four platforms
./tools/steam_build.sh        # Steam depot layout
```

Screenshots land in
`~/Library/Application Support/Godot/app_userdata/Slimer/shots`.

**All test entry points set `Save.disable_writes = true`** — running them never
touches a real save.

### Current passing state
- boot: 0 errors
- logic: **1452/1452**
- forest: **200/200 seeds**, ~74 ms each, all first-attempt
- sim: **22 waves**, minis at 5/10/15, major at 20, 4 shops, clean reset
- perf: 55 enemies + boss + 1251 props, **p95 4.2 ms** (budget 16.6)
- visual: all behaviour assertions pass

---

## 8. Testing philosophy used here

This matters because several bugs were found *only* because a test asserted the
**effect** rather than the flag.

- The pause test originally asserted `get_tree().paused == true` — which was
  true the whole time the world kept moving. It now samples enemy and player
  positions and asserts they don't change.
- When adding a regression test, **prove it fails without the fix.** I did this
  for the pause fix by temporarily reverting it.
- `sim_harness.gd` gives the bot a **12× damage assist and health top-ups on
  purpose** — the test is about whether the loop wedges, not bot marksmanship.
  Target is wave 22 (past every distinct mechanic); it often reaches 26 but
  isn't reliable there.
- `visual_pass.gd` keeps the player alive via `_keep_alive` until the scripted
  death. Without it the player dies partway (18 enemies, never moves) and every
  later screenshot shows a corpse.
- `Input.action_press()` only sets polled state — it does **not** deliver events
  to `_input`/`_unhandled_input`. Use `Input.parse_input_event()` for anything
  event-driven (pause, abilities).

---

## 9. Build / export quirks

- **`build.sh` and `steam_build.sh` resolve preset names from the file**,
  because the editor renamed "Windows" → "Windows Desktop" once and broke them.
- **`build.sh` reports warnings, not just errors.** An earlier version only
  grepped `^ERROR` and reported "ok" for a build that warned about missing
  rcedit — it hid a real problem across two builds.
- **`enforce_windows_resources()`** in `build.sh` sets
  `application/modify_resources` based on whether Wine + `~/rcedit.exe` actually
  exist, because the editor keeps flipping it back on. Embedding an icon in a
  `.exe` needs rcedit (a Windows tool → needs Wine on macOS). Currently off, so
  the `.exe` has Godot's default file icon. The in-game window icon is fine
  (`config/icon`). See STEAM.md for turning it on.
- **macOS** is universal + **ad-hoc signed** (required — Apple Silicon refuses
  unsigned arm64). Not notarised, so downloaded copies hit Gatekeeper.
- **ETC2 ASTC** texture import is enabled in `project.godot` — **required** for
  universal/arm64 macOS export; Godot refuses the preset without it.
- Web preset has `vram_texture_compression/for_desktop=false` to keep the
  download at ~50 MB.

---

## 10. Balance quick reference

- Player: 100 HP, 265 px/s. Gun: 12 dmg, 5/s, 12 mag, 1.1 s reload.
- Waves: `budget = 4 + 2.1w + 0.075w²`. Enemy cap 55 concurrent.
- Unlocks: green 1, blue 4, red 6, purple 9, yellow 11, orange 15, elites 13.
- Bosses: mini every 5, major every 20, endless. 3 mini + 2 major archetypes,
  rotating with an extra phase per repeat.
- Mini HP `520 + 95w`; major `1600 + 240w`.
- Shop: 6 offers, repeat purchases +55% each time.
- Potions: max 22% drop, anti-farm guard on the low-HP health bonus.

---

## 11. Open items / possible next steps

1. **Decide free vs. commercial** (§6). If commercial: replace the six sprite
   families — offered, not yet done.
2. **Confirm the author name.**
3. **Steamworks SDK not integrated** — no achievements, overlay or cloud saves.
   Needs GodotSteam + a real App ID. Hooks exist (`Events.boss_defeated`,
   `Save.stats.best_wave`). Cloud saves would be easiest: one JSON at
   `user://slimer_save.json`.
4. **Steam VDFs have placeholder IDs** — `APPID_HERE`, `DEPOTID_*` in
   `game/steam/`.
5. **Gamepad tested only in code**, never with a physical controller. Right-
   stick aim, reticle, glyph prompts and menu focus are implemented but unverified
   on hardware.
6. **Delete stale root artifacts** (§1).
7. Sim harness is flaky past wave ~23 on bot skill, not game bugs.

---

## 12. Working style the user responded well to

- They report bugs from **actually playing the Windows `.exe`** — a fix isn't
  done until rebuilt with `./tools/build.sh`.
- They value **root-cause diagnosis over quick patches**. Pause took three
  attempts; the two wrong ones were wrong because I guessed instead of
  reproducing. When a bug can't be reproduced, **ask what they see** rather than
  guessing again.
- Be **explicit about what wasn't verified** (e.g. audio I can't hear, gamepad
  hardware) rather than implying it was.
- They asked for full detail in explanations and accepted long, thorough work.
- `GAME_GUIDE.md` in `game/` is a complete player+developer walkthrough of every
  system — good orientation, and worth keeping current.
