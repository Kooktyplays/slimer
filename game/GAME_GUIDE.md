# Slimer — complete guide

Everything in the game, and how the pieces fit together.

---

## 1. The loop

```
Main menu → pick 2 abilities → forest generates from a fresh seed
      ↓
   Wave 1 … 4        ordinary waves
   Wave 5            MINI-BOSS  → shop
   Wave 6 … 9
   Wave 10           MINI-BOSS  → shop
   Wave 15           MINI-BOSS  → shop
   Wave 20           MAJOR BOSS → shop
      ↓
   … forever. Mini-boss every 5, major every 20, no ending.
      ↓
   Death → run results → Essence → permanent upgrades → new run
```

Death wipes money, gun upgrades and stat boosts. **Essence** is the only thing
that survives, and it buys permanent unlocks between runs.

---

## 2. Controls

| Action | Key |
| --- | --- |
| Move | WASD / arrows |
| Aim | Mouse |
| Shoot | Left click (hold) |
| Reload | R (automatic when empty) |
| Ability 1 | Space / Right click |
| Ability 2 | Shift / E |
| Continue past shop | F |
| Pause | Esc |
| Screenshot | F9 |

**Twelve game states**, all real states in `autoload/game.gd`: Main Menu,
Loadout, Permanent Upgrades, Run, and within a run the Intermission / Wave /
Mini-Boss / Major Boss / Shop phases, plus Death, Results, and the Pause and
Settings overlays.

---

## 3. The forest

Rebuilt from a new seed every run by `world/forest_generator.gd`, on a
4800 × 3700 arena.

1. Scatter 9–13 **clearings** with a minimum separation, then relax them apart.
2. Connect them with **paths** using a minimum spanning tree, plus three extra
   edges so the map has loops to circle-strafe rather than dead ends.
3. Stamp 2–4 **ponds**, never on a clearing or a path.
4. Scatter trees, rocks, logs, bushes, grass and flowers on a jittered grid
   (blue-noise-ish spacing), with a solid tree wall around the border.
5. Rasterise every blocker into a **64 px walkable grid**, inflated by the
   actor radius — so "open cell" already means "a slime fits".
6. **Validate**: flood-fill from the spawn. Every clearing, the shop and every
   loot point must be reachable, and no clearing may be below a minimum open
   area. Failures widen chokepoints, then reseed.

This is what makes the brief's "impossible situations" structurally
impossible. `tests/test_forest.gd` proves it over **200 seeds** — all pass on
the first attempt, ~74 ms each.

**Readability rule the whole forest obeys: brown and grey stop you, green does
not.** Trees, rocks, logs and stumps block. Grass, bushes and ferns are cover
you run through.

Ambience: swaying foliage, drifting leaves and motes, rippling ponds. All of
it freezes on pause (see §11).

---

## 4. The six enemy colours

Colour, behaviour and stats are declared in one entry in
`data/enemy_types.gd`, so a colour can never lie about what it does.

| Colour | Name | HP | Speed | Behaviour | Pays | From |
| --- | --- | --- | --- | --- | --- | --- |
| 🟢 Green | Slime | 30 | 110 | Straight at you, in packs | 4–7 | Wave 1 |
| 🔵 Blue | Darter | 20 | 215 | Fast; swings wide, then commits | 6–10 | Wave 4 |
| 🔴 Red | Brute | 110 | 62 | Slow, relentless, 20 contact damage | 12–18 | Wave 6 |
| 🟣 Purple | Spitter | 38 | 95 | Holds ~420 px, strafes, shoots | 10–16 | Wave 9 |
| 🟡 Yellow | Hoarder | 45 | 145 | Runs away; pays 5× | 34–52 | Wave 11 |
| 🟠 Orange | Bloater | 34 | 130 | Closes and detonates for 26 AoE | 11–17 | Wave 15 |

Two quality-of-life rules on top:

- **Catch-up** — anything more than 1100 px away speeds up to 2.1×, so the end
  of a wave is never a walk across the map. Yellows are exempt; fleeing is
  their job.
- **Finisher mode** — once the wave has spawned everything and ≤ 4 remain,
  every survivor commits. Hoarders stop fleeing, Spitters stop kiting.

**Elite modifiers** (from wave 13, up to 30% chance) wear a gold crown:
*Shielded* absorbs a burst first, *Enraged* is faster and speeds up further
below half health, *Splitter* breaks into two smaller slimes on death.

Enemies also have stuck-handling — a short steering nudge, and a silent
relocation if one is genuinely pinned on terrain far from the player. Without
it a wedged slime can stall a wave forever.

---

## 5. Waves — a threat budget, not an HP multiplier

`world/wave_controller.gd`. Each wave gets a budget:

```
budget(w) = 4 + 2.1w + 0.075w²
```

Each enemy type costs threat (green 1.0 … red 3.0). The spawner buys from the
types unlocked so far until the budget is spent. Elites cost 2.1× — so a wave
that rolls elites automatically contains fewer bodies.

Per-wave stat growth is **hard-capped**: HP ×3.2 max, damage ×2.4, speed ×1.45.
A wave-40 enemy is a few times tougher than a wave-1 one, not a thousand times.
The difficulty comes from *more enemies, worse combinations, and elites*.

Newly unlocked colours get a temporary spawn-weight boost so you meet them
clearly instead of losing one in a crowd, and green thins out as the roster
fills. Concurrent enemies are capped at 55; the rest are held back.

Spawns are placed 620–1250 px away, on open ground, never on top of you.

---

## 6. Bosses

Five archetypes in `data/boss_db.gd`, each with its own sprite and silhouette
— none of them is a scaled-up slime.

**Minis** (rotate on waves 5, 10, 15, 25, …):
- **Bramble Warden** — thorny root creature. Charges and fires thorn volleys.
- **The Toadfather** — bloated toad. Slams, spits, summons bloaters.
- **The Wisp Choir** — floating spectral cluster. Spirals and blink-bursts.

**Majors** (waves 20, 40, …):
- **The Ancient Oak** — treant. Rains, summons, shockwaves.
- **The Slime Sovereign** — crowned colossus. Everything, plus elite adds.

**Eight shared attacks**: slam, radial burst (always with a gap you can walk
through), aimed volley, telegraphed line charge, summon, rotating spiral,
staggered rain, expanding shockwave, and a blink-then-burst.

**Every attack telegraphs.** A ground marker fills from the centre outward
over the wind-up, ending exactly at the radius the hit will cover, with a
distinct sound. A boss that could hurt you without warning would be survivable
only by luck.

Phases are evenly spaced health thresholds. Crossing one interrupts the
current attack, so a phase change is a visible reset rather than something to
infer from the bar. Minis have 2 phases, majors 3 — and each repeat of an
archetype in the endless run adds another phase and widens its attack list.

Bosses get clearance-aware placement and their own stuck handling: one wedged
between trees is unreachable *and* unshootable, which is an unwinnable run.

---

## 7. The gun

One gun for the whole run. There is no weapon inventory — every shop purchase
edits the numbers it reads, so an upgrade applies on the very next shot.

Twelve stats: damage, fire rate, projectile count / speed / penetration, crit
chance and damage, magazine, reload, range, spread, knockback. All capped
(fire rate 18/s, crit 75%, 9 projectiles, reload floor 0.22 s) so a lucky run
can't reach absurd values.

The shop pool supports three recognisable builds:

- **Damage** — Hollow Points, Heavy Slugs, Weak Point Optics, Fracture Rounds,
  Piercing Core.
- **Rapid fire** — Tuned Action, Runaway Sear, Extended Drum, Quick Hands.
- **Projectile** — Split Barrel (+1 shot, −15% damage), Hot Loads, Rifled Bore.

Bullets do their own swept collision rather than using Area2D entry events —
see §11.

---

## 8. Abilities — one movement, two general

Fifteen exist in `data/abilities_db.gd`, in two classes. **Slot 0 is a movement
slot** and only takes a movement ability; slots 1 and 2 are general.

The split is not decoration. Dash used to compete for one of two general slots
and won every time — it is the only source of invulnerability in the game, and
several boss attacks (slam most of all) cannot be walked out of at all, so "pick
two" really meant "pick one, plus Dash". Giving movement its own slot is what
makes the general pair an actual argument between burst, control and sustain.

Movement abilities are three answers to *"I need to not be standing here"*:
Dash is the panic button, Surge trades invulnerability for duration, Vault turns
the escape into an opener.

| Ability | Class | Effect | Cooldown |
| --- | --- | --- | --- |
| **Dash** ★ | movement | Blink with i-frames, 2 charges | 3.2 s |
| **Surge** | movement | x1.95 speed for 3.5 s, no i-frames | 9 s |
| **Vault** | movement | 380 px leap, invulnerable, 45 dmg on landing | 7 s |
| **Grenade** ★ | general | Lobbed 90 damage in a 190 radius | 7 s |
| **Nova** ★ | general | 70 damage + heavy knockback around you | 11 s |
| **Thornwall** | general | A 260 px barrier for 6 s that blocks everything | 15 s |
| **Cinders** | general | Burning ground: 8 dmg / 0.25 s for 5 s | 13 s |
| **Bulwark** | Absorbs the next 120 damage for 6 s | 14 s |
| **Bloom** | Heal 35% of max | 26 s |
| **Stormcall** | Chain lightning across 7 enemies | 9 s |
| **Torpor** | Everything hostile to 35% speed for 4 s | 18 s |
| **Frenzy** | Triple fire rate + free reloads, 5 s | 20 s |
| **Satellites** | 3 orbiting orbs for 12 s | 22 s |
| **Effigy** | A lure enemies chase, then it bursts | 16 s |
| **Leech** | 18% lifesteal for 8 s | 24 s |

★ = unlocked from the start. The rest cost Essence.

Swap them at any forest rest (the shop). Charges refill on cooldown; the
purple potion grants one directly.

---

## 9. Economy

**Money** drops from every kill, scaled by colour (a Hoarder pays five times a
green slime). Coins scatter from the corpse and magnet in within 165 px — and
**when a wave clears, every coin on the ground flies straight to you**, so
finishing a fight collects the payout instead of leaving you to sweep the
clearing on foot.

**Potions** drop on a capped roll (max 22%) weighted by enemy type, wave and
your current health. Being hurt improves the odds — but a cooldown guard
switches that bonus off right after you pick a health potion up, so low HP
can't be farmed for sustain.

- ❤️ Red — restores 32% of max health
- ⚡ Blue — +45% movement speed for 9 s
- ✨ Purple — refills an ability charge

**The shop** opens after every boss. Six offers, priced so you can typically
afford two — it is a place to make a choice, not collect a reward. Buying the
same upgrade again costs 55% more each time, so stacking one stat has a real
cost against breadth. Rerolls escalate in price. Offers you already own are
weighted down; a full heal is weighted up the more hurt you are.

---

## 10. Permanent progression

**Essence** is earned from every run (waves reached + bosses felled) and never
lost. Three categories in `data/meta_db.gd`:

- **New abilities** — nine of the eleven.
- **New shop entries** — Heavy Slugs, Runaway Sear, Split Barrel, Thirsting
  Grip, Deep Reserves join the pool once bought.
- **Starting bonuses** — small, stacking: +health, seed money, +2 damage,
  +1 ability charge, +25% Essence, a free reroll.

Deliberately weighted towards *variety* over *power*. Run twenty should have
more possible shapes than run one, not be easier — the passives are capped
well below the point where they'd trivialise wave 20.

---

## 11. How it's built

~10,000 lines of GDScript, 57 scripts, 25 scenes, Godot 4.4.1.

```
autoload/   Events, Save, Pools, Audio, Game, DebugCapture
data/       all tuning and content tables — balance, enemies, bosses,
            abilities, upgrades, meta, run state, combat services
world/      forest generation, wave controller, run controller, tutor
actors/     player, enemy, pickups, bosses
weapons/    gun and projectile
abilities/  ability controller + the three that need their own scenes
ui/         HUD, menus, shop, ability picker
fx/         pooled hit / death / telegraph effects
tests/      logic tests, headless sim, visual pass, perf test
tools/      Python asset generation, build and check scripts
```

**Event bus.** Actors emit on `Events` instead of holding references to the
HUD or run controller. Pooled objects can be recycled without leaving dangling
references, and the UI can be absent entirely — which is what makes the
headless sim possible.

**Game owns state, Main owns nodes.** `Game` decides *what* state the game is
in; `main.gd` listens and swaps scenes. Keeping them apart is why the sim can
drive real state transitions with no UI.

**Pooling.** Bullets, enemies, particles, damage numbers and pickups are all
pooled and parked out of the tree when idle. Unparenting is deferred, because
most releases happen inside a physics callback where Godot forbids it.

**AI level of detail.** Enemies near the player think every physics frame;
distant ones on a staggered 10 Hz tick. Steering is plain vector maths on the
coarse grid — no navmesh, no per-frame pathfinding.

Two decisions worth knowing before changing them:

- **Bullets sweep their own collision.** `Area2D.body_entered` only fires on
  *entry*, which silently drops point-blank shots (the bullet spawns already
  overlapping) and fast ones (it steps over the target in a single frame).
  `weapons/projectile.gd` samples its circle along the segment it travels each
  frame instead. It also turned out cheaper than 90 monitoring areas in the
  broadphase — p95 frame time went from 9.1 ms to 4.2 ms.
- **Foliage animates from `anim_time`, not shader `TIME`.** `TIME` keeps
  running while the SceneTree is paused, so a paused game still had every tree
  swaying. `Game` advances a shader global and stops when paused. Any new
  animated shader should use it.

  Relatedly: `Main` is `PROCESS_MODE_ALWAYS` so it can read Escape while
  paused, but process mode **inherits** — `ScreenHolder` is explicitly set
  back to `PAUSABLE`, or the entire run scene under it would ignore
  `get_tree().paused` and the world would keep moving behind the pause menu.

**Audio.** Two decks crossfade between cues; the four supplied MP3s are the
whole musical identity, and the extra cues the design needs (wave escalation,
mini-boss, major boss) are derived from *Normal Music* by shifting playback
rate, engaging bus distortion and layering tempo-matched percussion at 100 BPM.
46 sound effects are synthesised, not sampled. Repeating sounds are throttled
per-sound, because a kill dropping five coins used to play five copies of the
same blip on top of each other.

**Assets are generated by scripts**, not hand-placed binaries: `gen_art.py`
authors 87 sprites in the asset pack's flat-vector style (and slices the
pack's potion files, which are 3×3 sheets rather than single bottles);
`gen_sfx.py` synthesises every sound. Both are deterministic and re-runnable.

---

## 12. Tests

```bash
G="$HOME/Downloads/Godot.app/Contents/MacOS/Godot"

./tools/check.sh                                           # boots with no script errors
$G --headless --path . -- tests                            # ~1450 logic assertions
$G --headless --path . --script res://tests/test_forest.gd # 200-seed generation sweep
$G --headless --fixed-fps 60 --path . -- sim               # plays 22 waves, asserts the loop
$G --path . --resolution 1600x900 -- perf                  # frame timing under a full wave
$G --path . --resolution 1600x900 -- visual                # screenshots + behaviour checks
```

What each one actually proves:

- **logic** — boss cadence over 200 waves, budget curve monotonic, unlock
  gates, stat caps, economy, potion bounds, save round-trip, the slot and
  ability-class rules, the version-1 keybind migration, meta gating.
- **forest** — across 200 seeds: spawn never blocked, everything reachable, no
  clearing too cramped, a boss always has somewhere to stand.
- **sim** — drives the real run scene with real input through 22 waves, then
  kills the player and checks the run resets while unlocks survive. This is
  the softlock test; it found the shop deadlock, the wedged bosses and the
  half-size hitboxes.
- **perf** — 55 enemies + a major boss + 1251 props: p95 ~4 ms against a
  16.6 ms budget.
- **visual** — captures every screen, and asserts things a screenshot can't
  show: that pause actually freezes the world, and that coins fly in on wave
  clear.

All test entry points set `Save.disable_writes`, so running them never touches
a real save.

---

## 13. Building

```bash
./tools/build.sh          # macOS, Windows, Linux and web
./tools/build.sh macos    # or one at a time
```

macOS is a universal, ad-hoc signed `.app` (Apple Silicon refuses unsigned
arm64 code). Windows and Linux are single self-contained files. See the README
for the Gatekeeper / SmartScreen caveats when sharing them.
