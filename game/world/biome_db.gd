class_name BiomeDB
extends RefCounted
## The five biomes the run descends through.
##
## The HUD has printed FOREST DEPTH since launch and it meant nothing - wave 1
## and wave 40 were the same four ground textures and the same prop tables.
## This is what makes the counter a promise the game keeps.
##
## Everything that varies together is declared together, for the same reason
## EnemyTypes declares colour and behaviour in one entry: a biome that could
## half-change - new ground, old props - would read as a bug rather than as a
## place.
##
## Balance.WAVES_PER_DEPTH is 5 and MINI_BOSS_EVERY is 5, so depth increments
## exactly on boss waves. One biome per depth means all five are seen by wave
## 21, a player who dies at wave 15 still meets three, and Heartwood arrives on
## the wave-20 major boss and then holds for the endless tail.

const GREENWOOD := "greenwood"
const FENLAND := "fenland"
const ASHFALL := "ashfall"
const HOLLOW := "hollow"
const HEARTWOOD := "heartwood"

## Shallowest first. Index is depth - 1, clamped.
const ORDER: Array[String] = [GREENWOOD, FENLAND, ASHFALL, HOLLOW, HEARTWOOD]

## Hazard ids. Every one of these must have a match arm in Run._tick_terrain
## (or, for gloom, a handler in the HUD) - the logic suite asserts it, because
## a biome naming a hazard nothing implements is a biome that quietly does
## nothing at all.
const HAZARD_NONE := ""
const HAZARD_WATER := "water_slow"
const HAZARD_FIRE := "fire"
const HAZARD_GLOOM := "gloom"
const HAZARD_BRAMBLE := "bramble"

const DEFS := {
	GREENWOOD: {
		"name": "Greenwood",
		"subtitle": "the shallows",
		# Ground texture set. Four keys, always: the base floor, clearings,
		# paths and water.
		"ground": {
			"grass": "ground_grass", "clearing": "ground_clearing",
			"path": "ground_path", "water": "ground_water",
		},
		"trees": {
			"tree_round_a": 1.0, "tree_round_b": 1.0, "pine_tree": 1.2,
			"tree_dead": 0.30,
		},
		"scatter": {
			"bush_a": 1.0, "bush_b": 0.7, "bush_c": 1.0,
			"rock_a": 0.6, "rock_b": 0.35, "rock_c": 0.7,
			"deadfall": 0.34, "log_a": 0.28, "log_b": 0.25, "stump": 0.30, "fern": 0.8,
			"mushroom": 0.45,
		},
		"clearing": {
			"grass_a": 1.0, "grass_b": 1.0, "grass_c": 1.0,
			"flower_a": 0.45, "flower_b": 0.40, "pebbles": 0.35, "rock_c": 0.16,
		},
		"detail": {
			"grass_a": 1.0, "grass_b": 1.0, "grass_c": 1.0,
			"flower_a": 0.25, "flower_b": 0.22, "pebbles": 0.30, "fern": 0.30,
		},
		"prop_tint": Color(1.0, 1.0, 1.0),
		"ambience": Color(1.0, 1.0, 1.0),
		# No hazard, deliberately. The first five waves are where the colour
		# language and the movement are taught, and a hazard here would be
		# teaching two things at once.
		"hazard": HAZARD_NONE,
		"ponds": Vector2i(2, 4),
	},
	FENLAND: {
		"name": "Fenland",
		"subtitle": "where the water starts",
		"ground": {
			"grass": "ground_fen", "clearing": "ground_fen_clearing",
			"path": "ground_fen_path", "water": "ground_water",
		},
		"trees": {
			"tree_round_a": 0.5, "tree_round_b": 0.5, "pine_tree": 0.6,
			"tree_dead": 1.0,
		},
		"scatter": {
			"bush_a": 0.5, "bush_c": 0.6, "reeds": 1.4, "fern": 1.2,
			"rock_a": 0.3, "deadfall": 0.34, "log_a": 0.6, "log_b": 0.55, "stump": 0.7,
			"mushroom": 0.6,
		},
		"clearing": {
			"grass_a": 0.8, "grass_b": 0.8, "reeds": 1.0, "lilypad": 0.5,
			"pebbles": 0.4,
		},
		"detail": {
			"grass_a": 0.7, "grass_c": 0.7, "reeds": 0.9, "fern": 0.5,
			"pebbles": 0.35,
		},
		"prop_tint": Color(0.86, 0.94, 0.90),
		"ambience": Color(0.90, 0.96, 1.0),
		"hazard": HAZARD_WATER,
		# More standing water, which is both the look and the hazard.
		"ponds": Vector2i(5, 8),
	},
	ASHFALL: {
		"name": "Ashfall",
		"subtitle": "what the fire left",
		"ground": {
			"grass": "ground_ash", "clearing": "ground_ash_clearing",
			"path": "ground_ash_path", "water": "ground_ash_water",
		},
		# Nothing green is still standing.
		"trees": {"tree_dead": 1.6, "stump": 0.9, "pine_tree": 0.25},
		"scatter": {
			"stump": 1.2, "deadfall": 0.34, "log_a": 0.9, "log_b": 0.8,
			"rock_a": 0.9, "rock_b": 0.7, "rock_c": 0.8, "pebbles": 0.6,
		},
		"clearing": {"pebbles": 1.0, "rock_c": 0.5, "grass_c": 0.25},
		"detail": {"pebbles": 1.0, "rock_c": 0.3, "grass_c": 0.2},
		"prop_tint": Color(0.62, 0.58, 0.56),
		"ambience": Color(1.0, 0.92, 0.85),
		"hazard": HAZARD_FIRE,
		# The "ponds" are ember pools here. They have to be common enough to
		# actually shape where you stand, or the hazard is a curiosity.
		"ponds": Vector2i(4, 7),
	},
	HOLLOW: {
		"name": "The Hollow",
		"subtitle": "where the light stops",
		"ground": {
			"grass": "ground_hollow", "clearing": "ground_hollow_clearing",
			"path": "ground_hollow_path", "water": "ground_hollow_water",
		},
		"trees": {"pine_tree": 1.8, "tree_dead": 0.8, "tree_round_b": 0.3},
		"scatter": {
			"deadfall": 0.34,
			"fern": 1.1, "mushroom": 1.0, "bush_c": 0.6, "stump": 0.5,
			"rock_a": 0.5, "rock_b": 0.4, "log_b": 0.4,
		},
		"clearing": {"grass_b": 0.8, "grass_c": 0.8, "mushroom": 0.5, "pebbles": 0.3},
		"detail": {"grass_b": 0.7, "fern": 0.6, "mushroom": 0.35},
		"prop_tint": Color(0.55, 0.60, 0.74),
		"ambience": Color(0.78, 0.82, 0.95),
		"hazard": HAZARD_GLOOM,
		"ponds": Vector2i(1, 3),
	},
	HEARTWOOD: {
		"name": "Heartwood",
		"subtitle": "what the forest grew around",
		"ground": {
			"grass": "ground_heart", "clearing": "ground_heart_clearing",
			"path": "ground_heart_path", "water": "ground_heart_water",
		},
		"trees": {"tree_round_a": 1.6, "tree_round_b": 1.6, "pine_tree": 0.5},
		"scatter": {
			"bush_a": 1.2, "bush_b": 1.0, "bush_c": 1.2, "fern": 1.3,
			"mushroom": 1.1, "deadfall": 0.34, "log_a": 0.5, "stump": 0.4, "rock_c": 0.4,
		},
		"clearing": {
			"grass_a": 1.0, "grass_b": 1.0, "flower_a": 0.7, "flower_b": 0.7,
			"mushroom": 0.5,
		},
		"detail": {"grass_a": 0.9, "grass_b": 0.9, "fern": 0.6, "flower_a": 0.4},
		"prop_tint": Color(0.82, 0.78, 0.96),
		"ambience": Color(0.92, 0.86, 1.0),
		"hazard": HAZARD_BRAMBLE,
		# Sap pools, which is what the violet water tile is.
		"ponds": Vector2i(3, 6),
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, DEFS[GREENWOOD])


## The biome at `depth`. Clamped at both ends: depth is 1-based, and the
## deepest biome holds forever because the run never finishes.
static func id_for_depth(depth: int) -> String:
	return ORDER[clampi(depth - 1, 0, ORDER.size() - 1)]


static func for_depth(depth: int) -> Dictionary:
	return get_def(id_for_depth(depth))


## Ground texture resource path for one of the four slots.
static func ground_path(id: String, slot: String) -> String:
	var ground: Dictionary = get_def(id)["ground"]
	return "res://assets/sprites/gen/%s.png" % String(ground[slot])
