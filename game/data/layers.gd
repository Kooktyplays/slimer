class_name Layers
extends RefCounted
## Physics layer bit values, mirroring the names in project.godot.
##
## Referring to Layers.ENEMY instead of a bare `4` is the difference between a
## collision bug you can read and one you have to decode.

const WORLD := 1 << 0
const PLAYER := 1 << 1
const ENEMY := 1 << 2
const PLAYER_BULLET := 1 << 3
const ENEMY_BULLET := 1 << 4
const PICKUP := 1 << 5
## Deadfall: stops BULLETS, not bodies.
##
## Its own bit rather than the dead PICKUP one, which is still named "pickup" in
## project.godot. The whole trick is that the player, every enemy, every boss
## and every enemy bullet mask WORLD and nothing else - so a body on a different
## layer is walked straight through by the entire cast with no edits to any of
## them, and only the projectile query has to learn about it.
const DEADFALL := 1 << 6
