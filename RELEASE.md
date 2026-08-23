# Release checklist

Ordered. Each step assumes the one before it passed.

## 1. Verify

Run from `game/`. All four must be clean — the boot check alone is not enough,
because it only loads the main menu and will happily miss a parse error in a
script the run scene owns.

```bash
./tools/check.sh
```

```bash
~/Downloads/Godot.app/Contents/MacOS/Godot --headless --path game -- tests
```

- `-- tests` — logic suite
- `-- sim` — headless 22-wave playthrough. Refuses to run with Dash equipped:
  that is the permanent guard on the bug that made Dash mandatory
- `-- perf` — p95 frame time against the 16.6 ms budget
- `-- visual` — screenshot pass with behaviour assertions. Runs **windowed**,
  not headless, and needs the window focused; a background window is throttled
  and the real-time assertions get flaky

## 2. Play it

The suites prove the game runs, not that it is worth playing. At minimum: one
run to wave 10 on Normal and one on Nightmare, and one boss killed on each.

## 3. Version

Bump `config/version` in `game/project.godot`, and the `desc` line in
`game/steam/app_build.vdf` to match.

## 4. Build and sign

```bash
cd game && ./tools/build.sh
```

`build.sh` codesigns the macOS `.app` and verifies the signature before
shipping. Do not skip the verification: Godot's "ad-hoc signed" export only
linker-signs the Mach-O and leaves no `_CodeSignature`, which is why v2.0.0
first shipped a macOS build that reported itself as damaged.

## 5. Check the licence text still matches reality

If any art changed, confirm `game/LICENSE-ASSETS.md`, `RIGHTS.md`, `README.md`,
`STEAM.md` and the in-game credits screen all still describe what is actually
in the build. The credits screen ships to players; a stale notice there is a
false statement about the game's own licence.

## 6. Publish

- GitHub: tag, then upload the three platform zips as release assets
- Steam: `cd game && ./tools/steam_build.sh <steam-login>` — needs the App ID
  and depot IDs filled into `game/steam/*.vdf` first, and the achievements from
  `game/steam/ACHIEVEMENTS.md` entered in the Steamworks UI
- Website: update `site/` to describe the new version, then deploy

## 7. Update the Notion handover

Known bugs, outstanding items, and what actually shipped.
