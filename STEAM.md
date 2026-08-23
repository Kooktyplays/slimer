# Shipping Slimer on Steam

Everything from "I have a game" to "it is on the store", in order.

> ## Licensing: cleared
>
> Slimer's art was CC BY-NC-SA (GDQuest's pack) and could not be sold at any
> price. All thirteen pack sprites have been replaced with originals generated
> by `game/tools/gen_art.py`, and the pack is gone from the project.
>
> **A paid release is now permitted.** The only third-party material left is
> MIT — the engine, and tween choreography in two effect scripts.
>
> Before a paid launch, still worth checking: the name "Slimer" against the
> Ghostbusters trademark and the Steam catalogue, and the terms on anything
> your music was built from. See `RIGHTS.md`.

---

## 1. What Valve needs from you

These need your identity and your bank details, so they are yours to do — I
cannot do them for you.

1. **Steamworks account** — <https://partner.steamgames.com>. Sign the
   distribution agreement with a personal or company identity.
2. **Tax and banking** — a W-8BEN (outside the US) or W-9 (US), plus a bank
   account for payouts. Valve will not let you release without this, and the
   tax interview can take a few days to clear.
3. **$100 Steam Direct fee**, per app. Recoupable once the app earns $1,000
   in adjusted gross revenue. Non-refundable otherwise. Free games pay it too.
4. **App ID** — issued once the fee clears. Every step below needs it.
5. **The 30-day rule** — a store page must be public for at least 30 days
   before you are allowed to release. Plan for it; it is not waivable.

## 2. Store page assets

Steam is strict about sizes. Budget real time for these — a bad capsule costs
more wishlists than a bad trailer.

| Asset | Size | Notes |
| --- | --- | --- |
| Header capsule | 460 × 215 | The one everyone sees |
| Small capsule | 231 × 87 | Search results; must be legible tiny |
| Main capsule | 616 × 353 | Front-page features |
| Vertical capsule | 374 × 448 | Seasonal sales |
| Page background | 1438 × 810 | Optional |
| Library capsule | 600 × 900 | In the user's library |
| Library header | 460 × 215 | |
| Screenshots | 1920 × 1080 | At least 5. Gameplay, not menus. |
| Trailer | 1920 × 1080 | Gameplay in the first 3 seconds |

You already have a screenshot pipeline: `Godot --path game -- visual` writes
one PNG per game state to
`~/Library/Application Support/Godot/app_userdata/Slimer/shots`. Those are
1600 × 900; re-run with `--resolution 1920x1080` for store-ready ones.

For the capsules, `assets/sprites/gen/app_icon.png` and the boss sprites are
the strongest art in the project.

## 3. Building and uploading

The build layout Steam wants is already scripted:

```bash
cd ~/Desktop/Slimer/game
./tools/steam_build.sh
```

That exports each platform into its own depot content root:

```
build/steam/windows/Slimer.exe
build/steam/macos/Slimer.app
build/steam/linux/Slimer.x86_64
```

Then:

1. In Steamworks, create three depots (Windows, macOS, Linux). Depot IDs are
   conventionally your App ID + 1, + 2, + 3.
2. Fill in the real IDs in `game/steam/app_build.vdf` and the three
   `depot_*.vdf` files, replacing `APPID_HERE` and `DEPOTID_*`.
3. Install the Steamworks SDK and put `steamcmd` on your PATH.
4. Upload:

```bash
./tools/steam_build.sh <your-steam-login>
```

`app_build.vdf` ships with `"setlive" ""`, so the first upload goes to your
account but is **not** promoted to a live branch. Set it to `default` only when
you actually want players to get it. Set `"preview" "1"` for a dry run.

## 4. Per-platform notes

**Windows** — a single self-contained `.exe`, no console window. Unsigned, so
SmartScreen will show "Windows protected your PC" until the binary builds
reputation. A code-signing certificate (~$100–400/yr) removes it; most small
releases just live with it.

### The Windows .exe file icon

The `.exe` currently ships with Godot's default icon, and
`application/modify_resources` is set to `false` in `export_presets.cfg`.

That is deliberate. Embedding an icon and version block into a Windows
executable is done by **rcedit**, which is itself a Windows program — on macOS
Godot can only run it through Wine. With neither installed, leaving the option
on just makes every build emit two warnings and embed nothing.

What is *not* affected: the in-game window and taskbar icon while playing comes
from `config/icon` in `project.godot` and already uses the generated slime
icon. Steam uses your uploaded capsule art everywhere on the store and in the
library. So the only place the default icon shows is the raw `.exe` in
Explorer — worth fixing before release, but not a blocker.

Two ways to fix it when you want to:

**Build the Windows export on a Windows machine.** Godot runs rcedit natively
there, and it just works. Simplest option if you have access to one.

**Or install Wine + rcedit on macOS:**

```bash
brew install --cask --no-quarantine wine-stable
curl -L -o ~/rcedit.exe \
  https://github.com/electron/rcedit/releases/latest/download/rcedit-x64.exe
```

Then in Godot: *Editor → Editor Settings → Export → Windows*, set **rcedit** to
`~/rcedit.exe` and **wine** to the path from `which wine`. Finally flip
`application/modify_resources` back to `true` in the Windows preset.

`tools/build.sh` prints any export warnings rather than hiding them, so you
will see immediately whether it took effect.

**macOS** — universal (Intel + Apple Silicon), ad-hoc signed. Ad-hoc is enough
to *launch*, but not enough for Gatekeeper on a downloaded copy. Steam
distribution mostly sidesteps this, but if you also sell direct you will want
an Apple Developer account ($99/yr) to notarise.

**Linux / Steam Deck** — the x86_64 build runs under Proton and natively. For
Deck Verified you need controller support (done), readable text at 1280 × 800
(the UI scales, but check it), and no launcher. Test with
`--resolution 1280x800`.

## 5. What is deliberately not included

**No Steamworks SDK integration.** There are no achievements, no overlay, no
cloud saves, no leaderboards. That needs [GodotSteam](https://godotsteam.com)
as a GDExtension plus a real App ID to test against.

It is a good follow-up once the store page exists, and the game already has
natural achievement hooks — `Events.boss_defeated`, `Events.wave_started`,
`Save.stats.best_wave` — so wiring them later is a contained job rather than a
redesign.

Cloud saves are the one I would prioritise: the save is a single JSON file at
`user://slimer_save.json`, which maps onto Steam Cloud almost directly.

## 6. Rough order

1. Decide: free release, or replace the ten pack-derived files so you can sell.
2. Decide on the name (see the Ghostbusters note in `RIGHTS.md`).
3. Steamworks account, tax forms, $100.
4. Build the store page. Publish it. **The 30-day clock starts here.**
5. Capsules, screenshots, trailer.
6. `./tools/steam_build.sh` and upload to a private branch.
7. Test the Steam build on a real machine, on all three platforms if you can.
8. Set a release date, then promote the build to `default`.
