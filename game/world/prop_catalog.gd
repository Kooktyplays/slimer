class_name PropCatalog
extends RefCounted
## Every scatterable object in the forest.
##
## Readability rule the whole forest obeys: brown and grey things stop you,
## green things do not. Trees, rocks, logs and stumps block; grass, bushes,
## ferns and flowers are cover you can run through. The player learns this in
## the first thirty seconds and never has to think about it again.

## `blockers` are circles in sprite-local space, offset from the ground anchor.
## `anchor` is how far above the sprite's bottom edge the ground point sits.
const DEFS := {
	# ---- blocking ----------------------------------------------------------
	"tree_round_a": {
		"texture": "gen/tree_round_a", "blocks": true, "anchor": 14,
		"blockers": [{"offset": Vector2(0, -6), "radius": 30.0}],
		"sway": 0.55, "layer": "canopy",
	},
	"tree_round_b": {
		"texture": "gen/tree_round_b", "blocks": true, "anchor": 14,
		"blockers": [{"offset": Vector2(0, -6), "radius": 30.0}],
		"sway": 0.55, "layer": "canopy",
	},
	"pine_tree": {
		"texture": "pine_tree", "blocks": true, "anchor": 8,
		"blockers": [{"offset": Vector2(0, -6), "radius": 26.0}],
		"sway": 0.40, "layer": "canopy",
	},
	"tree_dead": {
		"texture": "gen/tree_dead", "blocks": true, "anchor": 10,
		"blockers": [{"offset": Vector2(0, -6), "radius": 20.0}],
		"sway": 0.18, "layer": "canopy",
	},
	"stump": {
		"texture": "gen/stump", "blocks": true, "anchor": 8,
		"blockers": [{"offset": Vector2(0, -10), "radius": 24.0}],
		"sway": 0.0, "layer": "ground_prop",
	},
	"rock_a": {
		"texture": "gen/rock_a", "blocks": true, "anchor": 6,
		"blockers": [{"offset": Vector2(0, -12), "radius": 22.0}],
		"sway": 0.0, "layer": "ground_prop",
	},
	"rock_b": {
		"texture": "gen/rock_b", "blocks": true, "anchor": 6,
		"blockers": [{"offset": Vector2(0, -16), "radius": 32.0}],
		"sway": 0.0, "layer": "ground_prop",
	},
	"rock_c": {
		"texture": "gen/rock_c", "blocks": true, "anchor": 5,
		"blockers": [{"offset": Vector2(0, -9), "radius": 15.0}],
		"sway": 0.0, "layer": "ground_prop",
	},
	"log_a": {
		"texture": "gen/log_a", "blocks": true, "anchor": 10,
		"blockers": [
			{"offset": Vector2(-38, -14), "radius": 19.0},
			{"offset": Vector2(0, -14), "radius": 19.0},
			{"offset": Vector2(38, -14), "radius": 19.0},
		],
		"sway": 0.0, "layer": "ground_prop",
	},
	"log_b": {
		"texture": "gen/log_b", "blocks": true, "anchor": 8,
		"blockers": [
			{"offset": Vector2(-32, -13), "radius": 18.0},
			{"offset": Vector2(0, -13), "radius": 18.0},
			{"offset": Vector2(32, -13), "radius": 18.0},
		],
		"sway": 0.0, "layer": "ground_prop",
	},

	# ---- walk-through cover ------------------------------------------------
	"bush_a": {"texture": "gen/bush_a", "blocks": false, "anchor": 8, "sway": 0.9, "layer": "ground_prop"},
	"bush_b": {"texture": "gen/bush_b", "blocks": false, "anchor": 8, "sway": 0.9, "layer": "ground_prop"},
	"bush_c": {"texture": "gen/bush_c", "blocks": false, "anchor": 6, "sway": 1.0, "layer": "ground_prop"},
	"fern": {"texture": "gen/fern", "blocks": false, "anchor": 4, "sway": 1.2, "layer": "detail"},
	"mushroom": {"texture": "gen/mushroom", "blocks": false, "anchor": 4, "sway": 0.3, "layer": "detail"},

	# ---- flat ground detail (drawn below everything, never sorted) ---------
	"grass_a": {"texture": "gen/grass_a", "blocks": false, "anchor": 3, "sway": 1.6, "layer": "detail"},
	"grass_b": {"texture": "gen/grass_b", "blocks": false, "anchor": 3, "sway": 1.6, "layer": "detail"},
	"grass_c": {"texture": "gen/grass_c", "blocks": false, "anchor": 3, "sway": 1.6, "layer": "detail"},
	"flower_a": {"texture": "gen/flower_a", "blocks": false, "anchor": 2, "sway": 1.4, "layer": "detail"},
	"flower_b": {"texture": "gen/flower_b", "blocks": false, "anchor": 2, "sway": 1.4, "layer": "detail"},
	"pebbles": {"texture": "gen/pebbles", "blocks": false, "anchor": 4, "sway": 0.0, "layer": "detail"},

	# ---- water edging ------------------------------------------------------
	"reeds": {"texture": "gen/reeds", "blocks": false, "anchor": 4, "sway": 1.5, "layer": "ground_prop"},
	"lilypad": {"texture": "gen/lilypad", "blocks": false, "anchor": 0, "sway": 0.4, "layer": "detail"},

	# ---- landmarks ---------------------------------------------------------
	"shop_lantern": {
		"texture": "gen/shop_lantern", "blocks": true, "anchor": 8,
		"blockers": [{"offset": Vector2(0, -8), "radius": 14.0}],
		"sway": 0.0, "layer": "canopy",
	},
	"campfire": {
		"texture": "gen/campfire", "blocks": false, "anchor": 8,
		"sway": 0.0, "layer": "ground_prop",
	},
}

## Weighted sets the generator draws from, by region.
const FOREST_TREES := {
	"tree_round_a": 1.0, "tree_round_b": 1.0, "pine_tree": 1.2, "tree_dead": 0.30,
}
const FOREST_SCATTER := {
	"bush_a": 1.0, "bush_b": 0.7, "bush_c": 1.0,
	"rock_a": 0.6, "rock_b": 0.35, "rock_c": 0.7,
	"log_a": 0.28, "log_b": 0.25, "stump": 0.30, "fern": 0.8, "mushroom": 0.45,
}
const CLEARING_SCATTER := {
	"grass_a": 1.0, "grass_b": 1.0, "grass_c": 1.0,
	"flower_a": 0.45, "flower_b": 0.40, "pebbles": 0.35, "rock_c": 0.16,
}
const DETAIL_SCATTER := {
	"grass_a": 1.0, "grass_b": 1.0, "grass_c": 1.0,
	"flower_a": 0.25, "flower_b": 0.22, "pebbles": 0.30, "fern": 0.30,
}
const WATER_EDGE := {"reeds": 1.0, "lilypad": 0.55, "pebbles": 0.5}


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


static func texture_path(id: String) -> String:
	return "res://assets/sprites/%s.png" % DEFS[id]["texture"]


static func blocks(id: String) -> bool:
	return bool(DEFS[id].get("blocks", false))


static func blockers(id: String) -> Array:
	return DEFS[id].get("blockers", [])


## Largest blocker radius, used to size the generator's spacing checks.
static func block_radius(id: String) -> float:
	var r := 0.0
	for b: Dictionary in blockers(id):
		r = maxf(r, float(b["radius"]) + absf(float(b["offset"].x)))
	return r


static func pick(rng: RandomNumberGenerator, table: Dictionary) -> String:
	var total := 0.0
	for k: String in table:
		total += float(table[k])
	var roll := rng.randf() * total
	for k: String in table:
		roll -= float(table[k])
		if roll <= 0.0:
			return k
	return table.keys()[0]
