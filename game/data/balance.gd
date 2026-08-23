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
const PLAYER_IFRAMES := 0.55
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
const WAVES_PER_DEPTH := 5
const MAX_CONCURRENT_ENEMIES := 68
const SPAWN_MIN_DISTANCE := 620.0
const SPAWN_MAX_DISTANCE := 1250.0

## Threat budget for a wave. Quadratic so late waves get genuinely crowded.
##
## Raised about 28% when the movement slot was added: a third ability is roughly
## +50% uptime, and the forest has to push back or the extra slot just makes the
## run easier rather than more interesting.
static func wave_budget(wave: int) -> float:
	return 5.0 + 2.7 * wave + 0.098 * wave * wave

## How fast the spawner feeds the budget in, in threat per second.
##
## Deliberately raised in step with the budget. Lifting the budget alone would
## make every wave 28% *longer* rather than denser, which reads as padding - the
## extra threat has to arrive as pressure. Both curves still reach their cap
## around wave 35, so the shape of the ramp is unchanged.
static func spawn_rate(wave: int) -> float:
	return minf(1.4 + 0.23 * wave, 9.5)

# --- enemy scaling (capped on purpose) --------------------------------------
static func hp_scale(wave: int) -> float:
	return minf(1.0 + 0.055 * (wave - 1), 3.2)

static func damage_scale(wave: int) -> float:
	return minf(1.0 + 0.035 * (wave - 1), 2.4)

static func speed_scale(wave: int) -> float:
	return minf(1.0 + 0.012 * (wave - 1), 1.45)

## Money paid out grows more slowly than costs, so choices stay tight.
static func money_scale(wave: int) -> float:
	return 1.0 + 0.055 * (wave - 1)

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
static func mini_boss_hp(wave: int) -> float:
	return 520.0 + 95.0 * wave

static func major_boss_hp(wave: int) -> float:
	return 1600.0 + 240.0 * wave

static func boss_damage_scale(wave: int) -> float:
	return 1.0 + 0.045 * wave

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
static func essence_for_run(wave_reached: int, minis: int, majors: int) -> int:
	return int(wave_reached * 2 + minis * 12 + majors * 60)

# --- feel -------------------------------------------------------------------
const SHAKE_SHOOT := 0.9
const SHAKE_HIT := 3.0
const SHAKE_EXPLOSION := 7.0
const SHAKE_BOSS_SLAM := 11.0
const SHAKE_MAX := 16.0            ## clamp so combat stays readable
const HIT_STOP_KILL := 0.035
const HIT_STOP_BOSS_PHASE := 0.18
