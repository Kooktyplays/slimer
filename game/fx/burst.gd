extends Node2D
## One-shot particle burst for enemy deaths, explosions and pickups.
##
## Uses a CPUParticles2D rather than GPUParticles2D: these are small,
## short-lived, spawn in bursts of dozens, and CPU particles restart instantly
## on a pooled node without the one-frame GPU reset delay.

@onready var _particles: CPUParticles2D = $Particles

var _timer := 0.0


func play(at: Vector2, color: Color, count: int, power: float) -> void:
	global_position = at
	visible = true
	set_process(true)
	_particles.amount = maxi(count, 1)
	_particles.color = color
	_particles.initial_velocity_min = 90.0 * power
	_particles.initial_velocity_max = 320.0 * power
	_particles.scale_amount_min = 0.5 * power
	_particles.scale_amount_max = 1.25 * power
	_particles.lifetime = 0.42 + 0.16 * power
	_timer = _particles.lifetime + 0.1
	_particles.restart()
	_particles.emitting = true


func _process(delta: float) -> void:
	_timer -= delta
	if _timer <= 0.0:
		Pools.release(self)


func _pool_reset() -> void:
	_particles.emitting = false
	set_process(false)
