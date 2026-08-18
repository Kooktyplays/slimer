extends Node
## Music director and SFX playback.
##
## Music: two decks (MusicA / MusicB) crossfade between cues so a transition is
## never a hard cut. The four supplied tracks are the whole musical identity of
## the game; the extra cues the design needs - wave escalation, mini-boss,
## major boss - are derived from "Normal Music" by shifting playback rate,
## engaging bus distortion, and stacking a tempo-matched percussion layer.
##
## SFX: a fixed ring of players, so a hectic wave can never spawn unbounded
## AudioStreamPlayer nodes.

const MUSIC_DIR := "res://assets/music/"
const SFX_DIR := "res://assets/sfx/"
const SFX_VOICES := 24
const CROSSFADE := 1.4
const DUCKED_CUTOFF := 760.0
const OPEN_CUTOFF := 20500.0

enum Cue { NONE, MENU, COMBAT, ESCALATION, MINI_BOSS, MAJOR_BOSS, LOW_HEALTH, SHOP, DEATH, RESULTS }

## cue -> track, playback rate, distortion drive, percussion layer
const CUES := {
	Cue.MENU:       {"track": "lobby_music",     "rate": 1.00, "drive": 0.0, "layer": ""},
	Cue.SHOP:       {"track": "lobby_music",     "rate": 1.00, "drive": 0.0, "layer": ""},
	Cue.COMBAT:     {"track": "normal_music",    "rate": 1.00, "drive": 0.0, "layer": ""},
	Cue.ESCALATION: {"track": "normal_music",    "rate": 1.06, "drive": 0.0, "layer": "layer_escalation"},
	Cue.MINI_BOSS:  {"track": "normal_music",    "rate": 0.92, "drive": 0.22, "layer": "layer_mini"},
	Cue.MAJOR_BOSS: {"track": "normal_music",    "rate": 0.84, "drive": 0.40, "layer": "layer_major"},
	Cue.LOW_HEALTH: {"track": "low_health_music", "rate": 1.00, "drive": 0.0, "layer": ""},
	Cue.DEATH:      {"track": "low_health_music", "rate": 0.88, "drive": 0.0, "layer": ""},
	Cue.RESULTS:    {"track": "happy_ending",    "rate": 1.00, "drive": 0.0, "layer": ""},
}

var current_cue: int = Cue.NONE

var _decks: Array[AudioStreamPlayer] = []
var _deck_buses := ["MusicA", "MusicB"]
var _active_deck := 0
var _layer_player: AudioStreamPlayer
var _sfx_voices: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_cache: Dictionary = {}
var _sfx_cache: Dictionary = {}
var _fade_tween: Tween
var _duck_tween: Tween
var _music_enabled := true
var _last_played: Dictionary = {}     # sfx name -> last play time, for throttling


func _exit_tree() -> void:
	# Drop the cached streams explicitly. Autoloads are torn down after the
	# resource system starts shutting down, and holding these to the very end
	# is what produces the "resources still in use at exit" warning.
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	# stop() before clearing: a playing stream is still referenced by its
	# active playback, so nulling it while it plays releases nothing
	for deck: AudioStreamPlayer in _decks:
		deck.stop()
		deck.stream = null
	_layer_player.stop()
	_layer_player.stream = null
	for voice: AudioStreamPlayer in _sfx_voices:
		voice.stop()
		voice.stream = null
	_music_cache.clear()
	_sfx_cache.clear()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = _deck_buses[i]
		p.volume_db = -80.0
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_decks.append(p)

	_layer_player = AudioStreamPlayer.new()
	_layer_player.bus = "Layers"
	_layer_player.volume_db = 0.0
	_layer_player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_layer_player)

	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_voices.append(p)

	apply_settings()


# --------------------------------------------------------------------------
# settings
# --------------------------------------------------------------------------
func apply_settings() -> void:
	_set_bus_volume("Master", float(Save.settings["master_volume"]))
	_set_bus_volume("Music", float(Save.settings["music_volume"]) * 0.55)
	_set_bus_volume("SFX", float(Save.settings["sfx_volume"]))
	_set_bus_volume("UI", float(Save.settings["sfx_volume"]) * 0.8)


func _set_bus_volume(bus_name: String, linear: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(linear, 0.0001)))
	AudioServer.set_bus_mute(idx, linear <= 0.001)


# --------------------------------------------------------------------------
# music
# --------------------------------------------------------------------------
func play_cue(cue: int, force_restart: bool = false) -> void:
	if not _music_enabled:
		return
	if cue == current_cue and not force_restart:
		return
	if not CUES.has(cue):
		stop_music()
		return

	var spec: Dictionary = CUES[cue]
	var stream := _load_music(spec["track"])
	if stream == null:
		return

	var from_deck := _decks[_active_deck]
	_active_deck = 1 - _active_deck
	var to_deck := _decks[_active_deck]

	# Reuse the same playhead when only the treatment changes (combat ->
	# escalation -> mini-boss all ride "Normal Music"), so escalating mid-wave
	# feels like the track leaning in rather than restarting.
	var carry_position := 0.0
	var same_track: bool = (
		current_cue != Cue.NONE
		and CUES.has(current_cue)
		and CUES[current_cue]["track"] == spec["track"]
		and from_deck.playing
	)
	if same_track:
		carry_position = from_deck.get_playback_position()

	to_deck.stream = stream
	to_deck.pitch_scale = float(spec["rate"])
	to_deck.volume_db = -80.0
	to_deck.play(carry_position)

	_set_deck_drive(_active_deck, float(spec["drive"]))
	_start_layer(spec["layer"])

	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	_fade_tween.tween_property(to_deck, "volume_db", 0.0, CROSSFADE)
	if from_deck.playing:
		_fade_tween.tween_property(from_deck, "volume_db", -80.0, CROSSFADE)
		_fade_tween.chain().tween_callback(from_deck.stop)

	current_cue = cue


func stop_music(fade: float = 0.6) -> void:
	current_cue = Cue.NONE
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween().set_parallel(true)
	for deck: AudioStreamPlayer in _decks:
		if deck.playing:
			_fade_tween.tween_property(deck, "volume_db", -80.0, fade)
	_fade_tween.chain().tween_callback(func() -> void:
		for deck: AudioStreamPlayer in _decks:
			deck.stop()
		_layer_player.stop()
		_set_layer_volume(-80.0))


## Muffle the music without stopping it - used for pause and low health.
func set_ducked(ducked: bool, amount: float = 1.0) -> void:
	var idx := AudioServer.get_bus_index("Music")
	if idx < 0:
		return
	var effect := AudioServer.get_bus_effect(idx, 0)
	if effect is not AudioEffectLowPassFilter:
		return
	var target: float = lerpf(OPEN_CUTOFF, DUCKED_CUTOFF, amount) if ducked else OPEN_CUTOFF
	if _duck_tween != null and _duck_tween.is_valid():
		_duck_tween.kill()
	_duck_tween = create_tween()
	_duck_tween.tween_method(
		func(v: float) -> void: (effect as AudioEffectLowPassFilter).cutoff_hz = v,
		(effect as AudioEffectLowPassFilter).cutoff_hz, target, 0.45)


func set_music_enabled(enabled: bool) -> void:
	_music_enabled = enabled
	if not enabled:
		stop_music(0.2)


func _set_deck_drive(deck_index: int, drive: float) -> void:
	var idx := AudioServer.get_bus_index(_deck_buses[deck_index])
	if idx < 0:
		return
	var effect := AudioServer.get_bus_effect(idx, 0)
	if effect is AudioEffectDistortion:
		(effect as AudioEffectDistortion).drive = drive
		# a little make-up gain, since distortion at these settings loses level
		(effect as AudioEffectDistortion).post_gain = drive * 3.0
	AudioServer.set_bus_effect_enabled(idx, 0, drive > 0.001)


func _start_layer(layer_name: String) -> void:
	if layer_name.is_empty():
		if _layer_player.playing:
			var t := create_tween()
			t.tween_method(_set_layer_volume, _layer_volume(), -80.0, 0.8)
			t.tween_callback(_layer_player.stop)
		return
	var stream := _load_sfx(layer_name)
	if stream == null:
		return
	if stream is AudioStreamWAV:
		(stream as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(stream as AudioStreamWAV).loop_end = (stream as AudioStreamWAV).data.size() / 2
	if _layer_player.stream != stream:
		_layer_player.stream = stream
		_layer_player.play()
	_set_layer_volume(-80.0)
	var t := create_tween()
	t.tween_method(_set_layer_volume, -80.0, -7.0, 1.2)


func _layer_volume() -> float:
	var idx := AudioServer.get_bus_index("Layers")
	return AudioServer.get_bus_volume_db(idx) if idx >= 0 else -80.0


func _set_layer_volume(db: float) -> void:
	var idx := AudioServer.get_bus_index("Layers")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)


# --------------------------------------------------------------------------
# sfx
# --------------------------------------------------------------------------
## Play a one-shot. `pitch_jitter` keeps repeated sounds (gunfire, hits) from
## turning into a machine-gun of identical samples.
func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.06,
		bus: String = "SFX") -> void:
	var stream := _load_sfx(sfx_name)
	if stream == null:
		return
	var voice := _next_voice()
	voice.stream = stream
	voice.bus = bus
	voice.volume_db = volume_db
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


## Play, but never more often than `min_interval` seconds for this sound.
##
## Some events fire in bursts that a one-shot-per-event rule turns into noise:
## a kill drops up to five coins, a multi-projectile shot lands nine hits at
## once, a fast gun fires eighteen times a second. Layering a dozen copies of
## the same short sample is what makes a sound effect grating - it stops
## reading as feedback and starts reading as a buzz. Dropping the duplicates
## costs nothing, because they were inaudible as distinct events anyway.
func play_throttled(sfx_name: String, min_interval: float,
		volume_db: float = 0.0, pitch_jitter: float = 0.06) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sfx_name, -999.0)) < min_interval:
		return
	_last_played[sfx_name] = now
	play(sfx_name, volume_db, pitch_jitter)


func play_ui(sfx_name: String, volume_db: float = 0.0) -> void:
	play(sfx_name, volume_db, 0.0, "UI")


## Round-robin, but prefer a voice that has finished so we don't cut a long
## sound (boss spawn, explosion) short while short blips are free.
func _next_voice() -> AudioStreamPlayer:
	for i in SFX_VOICES:
		var idx := (_sfx_next + i) % SFX_VOICES
		if not _sfx_voices[idx].playing:
			_sfx_next = (idx + 1) % SFX_VOICES
			return _sfx_voices[idx]
	var v := _sfx_voices[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_VOICES
	return v


# --------------------------------------------------------------------------
# loading
# --------------------------------------------------------------------------
func _load_music(track: String) -> AudioStream:
	if _music_cache.has(track):
		return _music_cache[track]
	var path := MUSIC_DIR + track + ".mp3"
	if not ResourceLoader.exists(path):
		push_warning("Slimer: missing music track %s" % path)
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	_music_cache[track] = stream
	return stream


func _load_sfx(sfx_name: String) -> AudioStream:
	if _sfx_cache.has(sfx_name):
		return _sfx_cache[sfx_name]
	var path := SFX_DIR + sfx_name + ".wav"
	if not ResourceLoader.exists(path):
		push_warning("Slimer: missing sfx %s" % path)
		_sfx_cache[sfx_name] = null
		return null
	var stream: AudioStream = load(path)
	_sfx_cache[sfx_name] = stream
	return stream
