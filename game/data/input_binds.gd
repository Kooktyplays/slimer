class_name InputBinds
extends RefCounted
## The single source of truth for controls: which actions exist, what they are
## bound to by default, how to save a binding, and what to call it on screen.
##
## Defaults live here rather than in project.godot so that "reset to defaults"
## has something to reset *to*, and so the rebinding screen, the pause-menu
## control list and the HUD hotkey captions all read the same list and can
## never disagree with each other.

const DEVICE_KBM := "kbm"
const DEVICE_PAD := "pad"

const GROUP_MOVEMENT := "Movement"
const GROUP_COMBAT := "Combat"
const GROUP_ABILITIES := "Abilities"
const GROUP_INTERFACE := "Interface"

## Displayed in this order, grouped in this order.
const ACTIONS: Array[Dictionary] = [
	{"action": "move_up", "label": "Move up", "group": GROUP_MOVEMENT},
	{"action": "move_down", "label": "Move down", "group": GROUP_MOVEMENT},
	{"action": "move_left", "label": "Move left", "group": GROUP_MOVEMENT},
	{"action": "move_right", "label": "Move right", "group": GROUP_MOVEMENT},
	{"action": "shoot", "label": "Shoot", "group": GROUP_COMBAT},
	{"action": "reload", "label": "Reload", "group": GROUP_COMBAT},
	{"action": "ability_movement", "label": "Movement ability", "group": GROUP_ABILITIES},
	{"action": "ability_1", "label": "Ability 1", "group": GROUP_ABILITIES},
	{"action": "ability_2", "label": "Ability 2", "group": GROUP_ABILITIES},
	{"action": "interact", "label": "Continue / interact", "group": GROUP_INTERFACE},
	{"action": "pause", "label": "Pause", "group": GROUP_INTERFACE},
]

## Right-stick aiming. Not rebindable - it is an axis pair, not a button, and
## exposing it in the rebinder would mean supporting a second kind of row for
## no real benefit.
const AIM_ACTIONS: Array[String] = ["aim_left", "aim_right", "aim_up", "aim_down"]

const JOY_DEADZONE := 0.35

# Godot key constants, spelled out so this file reads without a lookup table.
const _KEY_W := 87
const _KEY_A := 65
const _KEY_S := 83
const _KEY_D := 68
const _KEY_E := 69
const _KEY_R := 82
const _KEY_F := 70
const _KEY_SPACE := 32
const _KEY_SHIFT := 4194325
const _KEY_ESCAPE := 4194305
const _KEY_UP := 4194320
const _KEY_DOWN := 4194322
const _KEY_LEFT := 4194319
const _KEY_RIGHT := 4194321

## action -> array of serialised events. Keyboard/mouse first, gamepad second;
## the UI shows the first of each kind.
const DEFAULTS := {
	"move_up": [
		{"type": "key", "physical": _KEY_W},
		{"type": "key", "physical": _KEY_UP},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_Y, "dir": -1},
		{"type": "pad_button", "button": JOY_BUTTON_DPAD_UP},
	],
	"move_down": [
		{"type": "key", "physical": _KEY_S},
		{"type": "key", "physical": _KEY_DOWN},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_Y, "dir": 1},
		{"type": "pad_button", "button": JOY_BUTTON_DPAD_DOWN},
	],
	"move_left": [
		{"type": "key", "physical": _KEY_A},
		{"type": "key", "physical": _KEY_LEFT},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_X, "dir": -1},
		{"type": "pad_button", "button": JOY_BUTTON_DPAD_LEFT},
	],
	"move_right": [
		{"type": "key", "physical": _KEY_D},
		{"type": "key", "physical": _KEY_RIGHT},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_X, "dir": 1},
		{"type": "pad_button", "button": JOY_BUTTON_DPAD_RIGHT},
	],
	"shoot": [
		{"type": "mouse", "button": MOUSE_BUTTON_LEFT},
		{"type": "pad_axis", "axis": JOY_AXIS_TRIGGER_RIGHT, "dir": 1},
	],
	"reload": [
		{"type": "key", "physical": _KEY_R},
		{"type": "pad_button", "button": JOY_BUTTON_X},
	],
	"ability_movement": [
		{"type": "key", "physical": _KEY_SPACE},
		{"type": "mouse", "button": MOUSE_BUTTON_RIGHT},
		{"type": "pad_button", "button": JOY_BUTTON_A},
	],
	"ability_1": [
		{"type": "key", "physical": _KEY_SHIFT},
		{"type": "pad_button", "button": JOY_BUTTON_B},
	],
	"ability_2": [
		{"type": "key", "physical": _KEY_E},
		{"type": "pad_button", "button": JOY_BUTTON_LEFT_SHOULDER},
	],
	"interact": [
		{"type": "key", "physical": _KEY_F},
		{"type": "pad_button", "button": JOY_BUTTON_Y},
	],
	"pause": [
		{"type": "key", "physical": _KEY_ESCAPE},
		{"type": "pad_button", "button": JOY_BUTTON_START},
	],
	"aim_left": [{"type": "pad_axis", "axis": JOY_AXIS_RIGHT_X, "dir": -1}],
	"aim_right": [{"type": "pad_axis", "axis": JOY_AXIS_RIGHT_X, "dir": 1}],
	"aim_up": [{"type": "pad_axis", "axis": JOY_AXIS_RIGHT_Y, "dir": -1}],
	"aim_down": [{"type": "pad_axis", "axis": JOY_AXIS_RIGHT_Y, "dir": 1}],
}

## Menu navigation also needs gamepad bindings, or a controller cannot get past
## the title screen. These are added on top of Godot's built-in defaults.
const UI_EXTRA := {
	"ui_accept": [{"type": "pad_button", "button": JOY_BUTTON_A}],
	"ui_cancel": [{"type": "pad_button", "button": JOY_BUTTON_B}],
	"ui_up": [{"type": "pad_button", "button": JOY_BUTTON_DPAD_UP},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_Y, "dir": -1}],
	"ui_down": [{"type": "pad_button", "button": JOY_BUTTON_DPAD_DOWN},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_Y, "dir": 1}],
	"ui_left": [{"type": "pad_button", "button": JOY_BUTTON_DPAD_LEFT},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_X, "dir": -1}],
	"ui_right": [{"type": "pad_button", "button": JOY_BUTTON_DPAD_RIGHT},
		{"type": "pad_axis", "axis": JOY_AXIS_LEFT_X, "dir": 1}],
}


# ---------------------------------------------------------------------------
# serialisation
# ---------------------------------------------------------------------------
## InputEvent objects can't go in a JSON save, so bindings round-trip through
## small dictionaries instead.
static func serialize(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
		return {"type": "key", "physical": int(code)}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int((event as InputEventMouseButton).button_index)}
	if event is InputEventJoypadButton:
		return {"type": "pad_button",
			"button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"type": "pad_axis", "axis": int(motion.axis),
			"dir": 1 if motion.axis_value >= 0.0 else -1}
	return {}


static func deserialize(data: Dictionary) -> InputEvent:
	match String(data.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.physical_keycode = int(data["physical"])
			return key
		"mouse":
			var mb := InputEventMouseButton.new()
			mb.button_index = int(data["button"])
			return mb
		"pad_button":
			var pb := InputEventJoypadButton.new()
			pb.button_index = int(data["button"])
			return pb
		"pad_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(data["axis"])
			motion.axis_value = 1.0 if int(data["dir"]) >= 0 else -1.0
			return motion
	return null


static func is_gamepad(data: Dictionary) -> bool:
	var t := String(data.get("type", ""))
	return t == "pad_button" or t == "pad_axis"


# ---------------------------------------------------------------------------
# applying
# ---------------------------------------------------------------------------
## Push a full binding set into the live InputMap. `overrides` only needs to
## contain the actions the player actually changed; everything else falls back
## to DEFAULTS.
static func apply(overrides: Dictionary) -> void:
	for action: String in DEFAULTS:
		var events: Array = overrides.get(action, DEFAULTS[action])
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2 if action.begins_with("move_") else 0.5)
		InputMap.action_erase_events(action)
		for data: Variant in events:
			var event := deserialize(data)
			if event != null:
				InputMap.action_add_event(action, event)

	# gamepad menu navigation, added once on top of Godot's own defaults
	for action: String in UI_EXTRA:
		if not InputMap.has_action(action):
			continue
		for data: Variant in UI_EXTRA[action]:
			var event := deserialize(data)
			if event != null and not InputMap.action_has_event(action, event):
				InputMap.action_add_event(action, event)


## The bindings currently in force for an action, as serialised dictionaries.
static func current(overrides: Dictionary, action: String) -> Array:
	return overrides.get(action, DEFAULTS.get(action, []))


static func first_of_kind(overrides: Dictionary, action: String, gamepad: bool) -> Dictionary:
	for data: Variant in current(overrides, action):
		if is_gamepad(data) == gamepad:
			return data
	return {}


# ---------------------------------------------------------------------------
# display
# ---------------------------------------------------------------------------
const _PAD_BUTTON_NAMES := {
	JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
	JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	JOY_BUTTON_START: "Start", JOY_BUTTON_BACK: "Back",
	JOY_BUTTON_DPAD_UP: "D-Pad Up", JOY_BUTTON_DPAD_DOWN: "D-Pad Down",
	JOY_BUTTON_DPAD_LEFT: "D-Pad Left", JOY_BUTTON_DPAD_RIGHT: "D-Pad Right",
}
const _PAD_AXIS_NAMES := {
	JOY_AXIS_LEFT_X: "Left Stick", JOY_AXIS_LEFT_Y: "Left Stick",
	JOY_AXIS_RIGHT_X: "Right Stick", JOY_AXIS_RIGHT_Y: "Right Stick",
	JOY_AXIS_TRIGGER_LEFT: "LT", JOY_AXIS_TRIGGER_RIGHT: "RT",
}
const _MOUSE_NAMES := {
	MOUSE_BUTTON_LEFT: "Left Click", MOUSE_BUTTON_RIGHT: "Right Click",
	MOUSE_BUTTON_MIDDLE: "Middle Click",
	MOUSE_BUTTON_WHEEL_UP: "Wheel Up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel Down",
}


## Short human label for a serialised binding, e.g. "Space", "RT", "Left Stick".
static func describe(data: Dictionary) -> String:
	match String(data.get("type", "")):
		"key":
			return OS.get_keycode_string(int(data["physical"]))
		"mouse":
			return String(_MOUSE_NAMES.get(int(data["button"]),
				"Mouse %d" % int(data["button"])))
		"pad_button":
			return String(_PAD_BUTTON_NAMES.get(int(data["button"]),
				"Button %d" % int(data["button"])))
		"pad_axis":
			var axis := int(data["axis"])
			var base := String(_PAD_AXIS_NAMES.get(axis, "Axis %d" % axis))
			if axis == JOY_AXIS_TRIGGER_LEFT or axis == JOY_AXIS_TRIGGER_RIGHT:
				return base
			var vertical := axis == JOY_AXIS_LEFT_Y or axis == JOY_AXIS_RIGHT_Y
			var positive := int(data.get("dir", 1)) >= 0
			var arrow := ""
			if vertical:
				arrow = " Down" if positive else " Up"
			else:
				arrow = " Right" if positive else " Left"
			return base + arrow
	return "Unbound"


## Label for whichever device the player is currently using - what the HUD and
## the pause-menu control list show.
static func label_for_action(overrides: Dictionary, action: String,
		device: String) -> String:
	var data := first_of_kind(overrides, action, device == DEVICE_PAD)
	if data.is_empty():
		data = first_of_kind(overrides, action, device != DEVICE_PAD)
	return describe(data) if not data.is_empty() else "Unbound"


## Which action, if any, already uses this binding. Used to warn about and
## clear conflicts when rebinding.
static func conflicting_action(overrides: Dictionary, data: Dictionary,
		ignore: String) -> String:
	for entry: Dictionary in ACTIONS:
		var action: String = entry["action"]
		if action == ignore:
			continue
		for existing: Variant in current(overrides, action):
			if existing == data:
				return action
	return ""


static func display_name(action: String) -> String:
	for entry: Dictionary in ACTIONS:
		if entry["action"] == action:
			return entry["label"]
	return action
