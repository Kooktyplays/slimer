class_name Balance
extends RefCounted
## Every tuning number in the game, in one file.
##
## Difficulty deliberately does NOT scale by inflating HP forever. Per-wave
## stat growth is mild and hard-capped; the real escalation comes from the
## threat budget buying more enemies, nastier types, and elite modifiers.

# --- player -----------------------------------------------------------------
const PLAYER_MAX_HP := 100.0
const PLAYER_SPEED := 265.0
const PLAYER_ACCEL := 3600.0
const PLAYER_FRICTION := 3000.0
const PLAYER_RADIUS := 22.0
## Invulnerability after taking a hit. Raised from 0.55: being hit once in a
## crowd used to roll straight into being hit again before you could react, and
## the crowd is exactly what the threat budget spends its money on.
const PLAYER_IFRAMES := 0.78

## Grace after landing a dash or a leap. Was 0.12, which is barely a frame and a
## half at 60fps - long enough to be technically true and too short to be felt.
## Landing in a crowd should not immediately cost a contact hit.
const LANDING_GRACE := 0.34

## Damage taken while Surge is up.
##
## Surge is the movement ability with NO invulnerability - that is its whole
## identity, and the headless sim runs a Surge loadout specifically to prove the
## bosses are beatable without blinking. Widening Dash and Vault's grace without
## touching Surge would quietly make it a trap pick and bring back the bug the
## movement-slot rework existed to fix. So it gets flat damage reduction
## instead: still no i-frames, still literally true, sim guard still meaningful.
const SURGE_DAMAGE_REDUCTION := 0.35
const LOW_HEALTH_FRACTION := 0.30

# --- starting gun -----------------------------------------------------------
const GUN_BASE := {
	"damage": 12.0,
	"fire_rate": 5.0,          # shots per second
	"projectile_speed": 1000.0,
	"projectile_count": 1.0,
	"crit_chance": 0.05,
	"crit_damage": 2.0,
	"magazine": 12.0,
	"reload_time": 1.10,
	"range": 900.0,
	"spread": 3.5,             # degrees of cone, lower is more accurate
	"penetration": 0.0,        # extra enemies a bullet passes through
	"knockback": 130.0,
}
## Hard ceilings so a lucky run can't reach absurd values.
const GUN_CAPS := {
	"fire_rate": 18.0,
	"crit_chance": 0.75,
	"crit_damage": 5.0,
	"projectile_count": 9.0,
	"penetration": 6.0,
	"reload_time": 0.22,       # floor, not ceiling
	"spread": 0.5,             # floor
}

# --- wave pacing ------------------------------------------------------------
const WAVE_INTERMISSION := 3.0
const MINI_BOSS_EVERY := 5
const MAJOR_BOSS_EVERY := 20

## The run's ending.
##
## Wave 21 enters Heartwood, the last biome, so wave 25 means you have descended
## through all five and then face what the forest grew around. It is deliberately
## *reachable*: the Sovereign's own rotation slot is wave 40, which the headless
## sim has never come close to and most players never will, and an ending nobody
## gets is most of why the game did not have one that mattered.
##
## Beating it does not end the run - it shows the ending and offers to continue,
## so the endless tail, the boss repeat system and the deepest-biome-holds-
## forever design all stay alive.
const FINALE_WAVE := 25
const FINALE_BOSS := "sovereign"

## The finale's own health, rather than whatever the major curve says at wave 25.
##
## The major curve was shaped for wave 40, where the Sovereign used to live. Run
## at wave 25 it produces 20,150 - 1.42x the wave-20 major, only five waves
## later - and the headless sim simply could not kill it: the run reached the
## ending and ground to a halt on it, which is a worse outcome than having no
## ending at all.
##
## Pinned just above the wave-20 major, which past sims have cleared. It should
## be the hardest fight in the game, not an unreachable one.
## Sized against measured damage, not against the major curve.
##
## The headless sim clears the wave-20 major (14,200) but only just - that is
## roughly a four-minute fight at the ~60 dps a run actually has at that depth.
## The finale carries Devour on top, which heals, so raw parity with the Oak
## would make it far longer than the Oak rather than merely harder.
##
## 8,000 is aimed at a two-minute fight: the hardest in the game, and one that
## ends. The wave-20 major being close to the sim's stall watchdog is a real
## tuning risk in its own right, flagged for play-testing rather than re-tuned
## blind here.
const FINALE_HP := 8000.0


static func finale_boss_hp() -> float:
	return FINALE_HP
const WAVES_PER_DEPTH := 5
const MAX_CONCURRENT_ENEMIES := 68
const SPAWN_MIN_DISTANCE := 620.0
const SPAWN_MAX_DISTANCE := 1250.0

# --- nightmare ---------------------------------------------------------------
## Nightmare is one flag on the run, not a second code path.
##
## Three knobs, all of which already take the wave as their only input, so the
## difficulty threads through without duplicating any curve: a fatter threat
## budget, the whole enemy roster available from wave 1 instead of unlocking
## over 15 waves, and enemies that hit materially harder.
const NIGHTMARE_BUDGET_MULTIPLIER := 1.55
const NIGHTMARE_DAMAGE_MULTIPLIER := 1.6
const NIGHTMARE_SPAWN_RATE_MULTIPLIER := 1.3
## Nightmare has to pay, or it is a penalty with no reason to pick it.
const NIGHTMARE_ESSENCE_MULTIPLIER := 2.2


## Threat budget for a wave. Quadratic so late waves get genuinely crowded.
##
## Raised about 28% when the movement slot was added: a third ability is roughly
## +50% uptime, and the forest has to push back or the extra slot just makes the
## run easier rather than more interesting.
static func wave_budget(wave: int, nightmare: bool = false) -> float:
	var base := 5.0 + 2.7 * wave + 0.098 * wave * wave
	return base * (NIGHTMARE_BUDGET_MULTIPLIER if nightmare else 1.0)

## How fast the spawner feeds the budget in, in threat per second.
##
## Deliberately raised in step with the budget. Lifting the budget alone would
## make every wave 28% *longer* rather than denser, which reads as padding - the
## extra threat has to arrive as pressure. Both curves still reach their cap
## around wave 35, so the shape of the ramp is unchanged.
static func spawn_rate(wave: int, nightmare: bool = false) -> float:
	var base := minf(1.4 + 0.23 * wave, 9.5)
	return base * (NIGHTMARE_SPAWN_RATE_MULTIPLIER if nightmare else 1.0)

# --- enemy scaling (capped on purpose) --------------------------------------
static func hp_scale(wave: int) -> float:
	return minf(1.0 + 0.055 * (wave - 1), 3.2)

static func damage_scale(wave: int, nightmare: bool = false) -> float:
	var base := minf(1.0 + 0.035 * (wave - 1), 2.4)
	return base * (NIGHTMARE_DAMAGE_MULTIPLIER if nightmare else 1.0)

static func speed_scale(wave: int) -> float:
	return minf(1.0 + 0.012 * (wave - 1), 1.45)

## Money paid out grows more slowly than costs, so choices stay tight.
static func money_scale(wave: int) -> float:
	return 1.0 + 0.055 * (wave - 1)

## Slime contact leaves a lingering poison as well as its instant hit.
##
## Late runs stack max HP faster than contact damage can scale - hard-capped at
## 2.4x - and with Bloom healing on top, a wall of slimes stopped being a threat
## and became scenery you walked through. Raising contact_damage instead would
## have made wave 3 brutal to fix a wave 30 problem.
##
## Poison scales with how many slimes reach you rather than with the wave
## number, so the pressure arrives exactly when the threat budget is buying
## crowds, and it keeps ticking through a burst heal instead of being erased by
## one. Damage per stack per second, as a fraction of the slime's contact hit.
const CONTACT_POISON_FRACTION := 0.42
const CONTACT_POISON_DURATION := 3.5
const CONTACT_POISON_INTERVAL := 0.5
const CONTACT_POISON_MAX_STACKS := 6

# --- elites -----------------------------------------------------------------
const ELITE_UNLOCK_WAVE := 13
const ELITE_THREAT_MULTIPLIER := 2.1
const ELITE_HP_MULTIPLIER := 2.6
const ELITE_DAMAGE_MULTIPLIER := 1.5
const ELITE_MONEY_MULTIPLIER := 3.0
const ELITE_SCALE := 1.32

## Chance a given spawn is upgraded to an elite, once elites are unlocked.
static func elite_chance(wave: int) -> float:
	if wave < ELITE_UNLOCK_WAVE:
		return 0.0
	return minf(0.06 + 0.012 * (wave - ELITE_UNLOCK_WAVE), 0.30)

# --- bosses -----------------------------------------------------------------
## Boss health has to be QUADRATIC, because a wave's health is.
##
## These were straight lines (520 + 95w, 1600 + 240w) while a wave's total pool
## is wave_budget(w) - already quadratic - multiplied again by hp_scale(w). The
## two diverged permanently, and measurably: a mini-boss was 1.14x a wave's
## whole health pool at wave 5, 0.48x by wave 15 and 0.22x by wave 30. Bosses
## were not tuned easy, they were on the wrong curve.
##
## And parity is not parity. A wave arrives as thirty-odd bodies from every
## direction with stacking contact poison; a boss is one target with attacks
## that are deliberately telegraphed and walkable. So the boss curve is aimed
## *above* the wave curve, not level with it.
##
## `_test_boss_curve` asserts the ratio never falls below its floor for any
## wave 1-100, so this can never quietly drift back into a straight line.
static func mini_boss_hp(wave: int) -> float:
	return 460.0 + 80.0 * wave + 12.0 * wave * wave

static func major_boss_hp(wave: int) -> float:
	return 1400.0 + 200.0 * wave + 22.0 * wave * wave

## Roughly what a whole wave is worth in enemy health, used to keep the boss
## curve honest. ~34 HP per point of threat is the roster average at base
## stats; the exact constant matters less than the shape, which has to match
## whatever wave_budget is doing.
const WAVE_HP_PER_THREAT := 34.0

static func wave_hp_pool(wave: int, nightmare: bool = false) -> float:
	return wave_budget(wave, nightmare) * WAVE_HP_PER_THREAT * hp_scale(wave)


## Also lifted off a straight line, for the same reason. A boss that hits for
## the same fraction of your health at wave 40 as at wave 5 is a boss you have
## outgrown.
static func boss_damage_scale(wave: int) -> float:
	return 1.0 + 0.045 * wave + 0.0016 * wave * wave

static func mini_boss_reward(wave: int) -> int:
	return int(180 + 26 * wave)

static func major_boss_reward(wave: int) -> int:
	return int(700 + 70 * wave)

# --- potions ----------------------------------------------------------------
const POTION_BASE_CHANCE := 0.045
const POTION_MAX_CHANCE := 0.22
const HEALTH_POTION_COOLDOWN := 12.0   ## anti-farm guard on the low-HP bonus
const HEALTH_POTION_RESTORE := 0.32    ## fraction of max HP
const SPEED_POTION_MULTIPLIER := 1.45
const SPEED_POTION_DURATION := 9.0
const ABILITY_POTION_CHARGE := 1

## Drop chance for one kill. Low HP nudges health potions up, but only if the
## player hasn't just picked one up - see RunState.health_potion_guard.
static func potion_chance(wave: int, hp_fraction: float, guarded: bool) -> float:
	var c := POTION_BASE_CHANCE + 0.0022 * wave
	if hp_fraction < 0.4 and not guarded:
		c += 0.055 * (1.0 - hp_fraction / 0.4)
	return minf(c, POTION_MAX_CHANCE)

# --- economy ----------------------------------------------------------------
const SHOP_OFFER_COUNT := 6
const SHOP_REROLL_BASE_COST := 60
const SHOP_REROLL_STEP := 45

# --- meta progression -------------------------------------------------------
## Essence is the only thing that survives death.
static func essence_for_run(wave_reached: int, minis: int, majors: int,
		nightmare: bool = false) -> int:
	var base := wave_reached * 2 + minis * 12 + majors * 60
	return int(base * (NIGHTMARE_ESSENCE_MULTIPLIER if nightmare else 1.0))

# --- feel -------------------------------------------------------------------
const SHAKE_SHOOT := 0.9
const SHAKE_HIT := 3.0
const SHAKE_EXPLOSION := 7.0
const SHAKE_BOSS_SLAM := 11.0
const SHAKE_MAX := 16.0            ## clamp so combat stays readable
const HIT_STOP_KILL := 0.035
const HIT_STOP_BOSS_PHASE := 0.18

## Kill shake, by combo tier: `SHAKE_KILL_BASE + SHAKE_KILL_PER_TIER * tier`.
##
## Every kill shakes now. It used to be gated above tier 0, so an ordinary kill
## produced no camera response at all and the feedback only existed once a
## chain was already running - which is backwards, because the single kill is
## the thing the player does thousands of times. The base is small on purpose;
## the tiers are what escalate. Tier 5 lands at 10.9, under SHAKE_MAX, and
## Game.shake() scales all of it by the accessibility slider.
const SHAKE_KILL_BASE := 1.4
const SHAKE_KILL_PER_TIER := 1.9
## The tier from which *reaching a new tier* buys a few frames of hit stop.
##
## Reaching one, not being on one. Firing on every kill at this tier or above
## was the first version and it was wrong twice over. _apply_hit_stop's own
## comment says it: re-triggering on everything "keeps the game in slow motion
## - which reads as the game lagging, not as impact", and its 0.45s cooldown
## only bounds that, it does not fix it. A dense wave past 30 kills would have
## stuttered every 0.45s from end to end.
##
## It also broke the headless sim. Hit stop restores on an ignore_time_scale
## timer - real seconds - while the sim is frame-deterministic at --fixed-fps
## 60, so how many frames the world spent at quarter speed depended on machine
## load. The same seed and class produced best combos of 34, 86 and 217 across
## three runs. A tier-up fires at most three times in a chain, which puts that
## back where it was.
## How long a finishing wave may fail to make progress before its stragglers
## are escalated. See Combat.hunt_mode.
##
## Long enough that an ordinary slow clear never trips it - a Spitter kiting at
## its preferred 420px while you close is normal play and takes a few seconds -
## and short enough that a genuine wedge is over before the player concludes the
## game is broken.
const STRAGGLER_HUNT_AFTER := 6.0
## Speed multiplier on an escalated straggler.
const STRAGGLER_HUNT_SPEED := 1.6

const HIT_STOP_COMBO_TIER := 3
## Extra shake on the frame a new tier is reached, on top of the kill shake.
## The chain levelling up is an event; a kill inside it is not.
const SHAKE_COMBO_TIER_UP := 3.2

## Payout multiplier by combo tier. Indexed directly by RunState.combo_tier(),
## so it must cover 0..COMBO_TIER_MAX.
##
## This is the reason to fight aggressively rather than kite: the chain was
## previously worth shake and a HUD number and nothing you could spend. Applied
## to the corpse's own payout before the coins are split, so a live chain
## visibly showers more coins rather than quietly crediting a bonus.
##
## This top figure was briefly trimmed to 1.9 to kill an earnings outlier. It
## did not: the outlier moved from 95,641 to 111,252, which is noise, and over
## thirty runs the tail turned out to be a long chain rather than a bug - the
## breaching runs had best combos of 146 and 72 against a typical 48. The trim
## was reverted because it cost an ordinary run about 7% of its payout in
## exchange for nothing at all.
##
## Flattening the whole curve to 1.0 still earns ~30,000 a run, so the chain is
## worth roughly +30% on normal play, which is the number to argue about.
##
## Unvalidated by human play, and it compounds with money_mul and with the
## Vampire's kill-spread. SimHarness.MAX_EARNED is a loose canary on that, not
## a tight bound - see the comment there before tightening it again.
const COMBO_MONEY_MUL: Array[float] = [1.0, 1.2, 1.45, 1.75, 2.05, 2.4]


## Payout multiplier for `tier`, clamped so a new tier can never index off the
## end of the table.
static func combo_money_mul(tier: int) -> float:
	return COMBO_MONEY_MUL[clampi(tier, 0, COMBO_MONEY_MUL.size() - 1)]


## What a corpse worth `money` pays on a tier-`tier` chain, given that `stolen`
## of that money was taken from the player in the first place.
##
## The split is not a rounding detail. A Thief's haul rides on its payout
## precisely so that killing it hands your own money back; multiply that and
## the player gets back *more than was taken*, which makes "let it rob me, then
## kill it on a tier-5 chain" a money printer. Only what the enemy was worth on
## its own is multiplied.
static func combo_payout(money: int, stolen: int, tier: int) -> int:
	var taken := clampi(stolen, 0, maxi(money, 0))
	var earned := maxi(money, 0) - taken
	return taken + int(round(earned * combo_money_mul(tier)))
