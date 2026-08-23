# Steam achievements

The 10 achievement ids Slimer emits, for pasting into
**Steamworks → your app → Stats & Achievements → Achievements**.

The **API Name** column must match exactly. These ids are also what the game
stores in its save file, so renaming one silently revokes the achievement for
every player who already has it — add a new id instead.

| API Name | Display name | Description |
| --- | --- | --- |
| `first_blood` | First Blood | Defeat any boss. |
| `grove_tyrant` | Grove Tyrant | Defeat a major boss. |
| `clean_sweep` | Clean Sweep | Defeat every boss in the forest at least once. |
| `deep_woods` | Deep Woods | Reach wave 20. |
| `the_long_dark` | The Long Dark | Survive 100 waves. |
| `no_gods` | No Gods, No Slimes | Reach wave 40 on Nightmare. |
| `unmaker` | Unmaker | Survive 100 waves on Nightmare. |
| `pacifist_run` | Light Touch | Reach wave 10 without buying a single upgrade. |
| `hoarder` | Hoarder Hoarder | Earn 50,000 coins in total. |
| `exterminator` | Exterminator | Kill 10,000 slimes in total. |

Icons: the game draws its own from `assets/sprites/gen/`, but Steam wants a
64×64 achieved and unachieved pair uploaded per achievement in the web UI.

The game does not link against the Steamworks SDK yet, so nothing is reported
to Steam at runtime — `Save.check_achievements()` grants them locally and emits
`Events.achievement_unlocked`. Wiring that signal to `SetAchievement` is the
only game-side work left once the SDK is in.

Source of truth: `game/data/achievements_db.gd`.
