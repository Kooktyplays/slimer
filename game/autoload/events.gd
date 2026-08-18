extends Node
## Global signal bus.
##
## Actors emit here instead of holding references to the HUD, the audio
## director or the run controller. That keeps pooled objects free of dangling
## references when they're recycled, and lets the UI exist (or not) without
## anything else caring.

# --- combat -----------------------------------------------------------------
signal enemy_spawned(enemy: Node2D)
signal enemy_damaged(enemy: Node2D, amount: float, is_crit: bool, at: Vector2)
signal enemy_died(enemy: Node2D, at: Vector2)
signal player_damaged(amount: float, from: Vector2)
signal player_healed(amount: float)
signal player_died()
signal shot_fired(from: Vector2, dir: Vector2)
signal enemy_shot_fired(enemy: Node2D)
signal reload_started(duration: float)
signal reload_finished()

# --- economy ----------------------------------------------------------------
signal money_changed(total: int, delta: int)
signal essence_changed(total: int, delta: int)
signal pickup_collected(kind: String, at: Vector2)
signal potion_used(kind: String)

# --- run flow ---------------------------------------------------------------
signal wave_started(wave: int, depth: int)
signal wave_cleared(wave: int)
signal boss_spawned(boss: Node2D, display_name: String, is_major: bool)
signal boss_phase_changed(boss: Node2D, phase: int)
signal boss_defeated(boss: Node2D)
signal shop_opened()
signal shop_closed()
signal run_started(seed_value: int)
signal run_ended(stats: Dictionary)

# --- upgrades / abilities ---------------------------------------------------
signal gun_upgraded(stat: String, new_value: float)
signal ability_used(slot: int, id: String)
signal ability_ready(slot: int, id: String)
signal ability_equipped(slot: int, id: String)
signal unlock_granted(kind: String, id: String)

# --- presentation -----------------------------------------------------------
signal screen_shake(strength: float, duration: float)
signal hit_stop(duration: float)
signal toast(text: String, color: Color)
signal tutorial_hint(id: String, text: String)
signal state_changed(from: int, to: int)
