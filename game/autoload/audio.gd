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
## Licensed tracks (Epidemic Sound) that override the ones in MUSIC_DIR, plus
## one theme per boss, named BOSS_TRACK_PREFIX + the boss id.
##
## This directory is gitignored: the repository is public, and a stock-audio
## licence covers shipping the music inside the game, not handing out the raw
## files. tools/licensed_audio.json records what belongs here so it can be
## fetched again. A clone without it falls back to MUSIC_DIR and plays the
## original tracks, so nothing about the game depends on it being present.
##
## WAV rather than MP3: Godot compresses it with QOA on import, and a WAV loop
## is sample-exact where MP3's encoder padding leaves a gap at the seam.
const LICENSED_MUSIC_DIR := "res://assets/music_licensed/"
const BOSS_TRACK_PREFIX := "boss_"
const SFX_DIR := "res://assets/sfx/"
const SFX_VOICES := 24
## Positional voices, for sounds that happen somewhere rather than to you.
##
## Fewer than the flat ring on purpose: these are world events - a slime dying
## across the clearing, a boss landing a slam - and a wave never has two dozen
## of them audible at once. Anything closer than SFX_VOICES would just be
## reserving nodes that never speak.
const SFX_2D_VOICES := 12
## Past this the sound is inaudible and the voice is better spent.
const SFX_2D_MAX_DISTANCE := 1600.0
const SFX_2D_ATTENUATION := 1.4
const CROSSFADE := 1.4

## Reverb per biome: room size, damping.
##
## The forest is the only room in the game, and it is a different room five
## times. Greenwood is open canopy; the Hollow is the one the design calls
## "where the light stops", so it is the long dark tail; Ashfall is burnt out
## and dead, which is a short reverb, not a long one - fire strips a place of
## the soft surfaces that ring. Fenland is damp and close. Heartwood is inside
## something.
const SPACES := {
	"greenwood": {"room": 0.55, "damp": 0.42},
	"fenland":   {"room": 0.46, "damp": 0.62},
	"ashfall":   {"room": 0.34, "damp": 0.30},
	"hollow":    {"room": 0.78, "damp": 0.28},
	"heartwood": {"room": 0.66, "damp": 0.50},
}
const SPACE_FADE := 2.5
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
## The boss fight in progress has its own theme; "" means use the CUES entry.
var boss_track := ""
var _current_track := ""

var _decks: Array[AudioStreamPlayer] = []
var _deck_buses := ["MusicA", "MusicB"]
var _active_deck := 0
var _layer_player: AudioStreamPlayer
var _sfx_voices: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _sfx_2d_voices: Array[AudioStreamPlayer2D] = []
var _sfx_2d_next := 0
var _reverb: AudioEffectReverb = null
var _space_tween: Tween
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
	if _space_tween != null and _space_tween.is_valid():
		_space_tween.kill()
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
	for voice2: AudioStreamPlayer2D in _sfx_2d_voices:
		voice2.stop()
		voice2.stream = null
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

	# Positional ring. These live on this autoload rather than being parented to
	# whatever made the sound, deliberately: an enemy that dies is released to
	# the pool on the same frame, and a voice parented to it would be cut off
	# mid-death-squelch or, worse, follow the node when it was handed out again.
	for i in SFX_2D_VOICES:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = SFX_2D_MAX_DISTANCE
		p2.attenuation = SFX_2D_ATTENUATION
		p2.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p2)
		_sfx_2d_voices.append(p2)

	_grab_reverb()
	Events.biome_changed.connect(_on_biome_changed)
	Events.boss_spawned.connect(_on_boss_spawned)
	Events.boss_defeated.connect(_on_boss_defeated)

	apply_settings()


## Hold the live AudioEffectReverb instance off the SFX bus.
##
## Fetched once and cached: AudioServer.get_bus_effect returns the actual
## resource the mix is using, so tweening its properties changes the sound
## without rebuilding the bus. A null here is not fatal - set_space just
## becomes a no-op and the dry mix plays - so the game never depends on the
## bus layout having been saved with the effect attached.
func _grab_reverb() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	if idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(idx):
		var fx := AudioServer.get_bus_effect(idx, i)
		if fx is AudioEffectReverb:
			_reverb = fx as AudioEffectReverb
			return


func _on_biome_changed(biome_id: String, _display_name: String) -> void:
	set_space(biome_id)


## Move the room to match the biome, over SPACE_FADE seconds.
##
## Tweened rather than set, because the biome boundary is a shop closing and the
## forest rebuilding around you - a reverb that snapped would be the one thing
## in that transition that announced itself as a setting being changed.
func set_space(biome_id: String) -> void:
	if _reverb == null:
		return
	var spec: Dictionary = SPACES.get(biome_id, SPACES["greenwood"])
	if _space_tween != null and _space_tween.is_valid():
		_space_tween.kill()
	_space_tween = create_tween().set_parallel(true)
	_space_tween.tween_property(_reverb, "room_size", float(spec["room"]), SPACE_FADE)
	_space_tween.tween_property(_reverb, "damping", float(spec["damp"]), SPACE_FADE)


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

	# Leaving the run drops the theme, so a run that ended mid-fight cannot
	# carry it into the next one's first boss wave. LOW_HEALTH keeps it: the
	# fight resumes its theme when the player recovers.
	if cue == Cue.MENU or cue == Cue.DEATH or cue == Cue.RESULTS:
		boss_track = ""
	var spec := cue_spec(cue, boss_track)
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
		and _current_track == spec["track"]
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
	_current_track = spec["track"]


## What a cue plays: its CUES entry, unless it is a boss cue and the fight has
## a theme of its own. A dedicated theme plays as written - no rate shift, no
## drive, and no percussion layer, which was tempo-matched to Normal Music and
## would drift against anything else.
static func cue_spec(cue: int, theme: String) -> Dictionary:
	if theme != "" and (cue == Cue.MINI_BOSS or cue == Cue.MAJOR_BOSS):
		return {"track": theme, "rate": 1.0, "drive": 0.0, "layer": ""}
	return CUES[cue]


## A boss with a theme on disk takes the music over as it lands; one without
## keeps the derived boss treatment of Normal Music.
func _on_boss_spawned(boss: Node2D, _display_name: String, _is_major: bool) -> void:
	var theme := BOSS_TRACK_PREFIX + String(boss.get("id"))
	boss_track = theme if music_path(theme) != "" else ""
	if boss_track != "" and (current_cue == Cue.MINI_BOSS or current_cue == Cue.MAJOR_BOSS):
		play_cue(current_cue, true)


func _on_boss_defeated(_boss: Node2D) -> void:
	boss_track = ""


func stop_music(fade: float = 0.6) -> void:
	current_cue = Cue.NONE
	_current_track = ""
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
## Loudness variance, in dB, applied alongside pitch jitter.
##
## Gated on pitch_jitter > 0 rather than on a parameter of its own. A caller
## passing 0.0 jitter is saying "this sound must be identical every time" - that
## is what play_ui does for menu clicks, where a wandering level would read as a
## fault. Everything else is a world sound heard hundreds of times a run, and a
## fixed level is a large part of why repetition registers as a loop.
const VOLUME_JITTER_DB := 1.5


func play(sfx_name: String, volume_db: float = 0.0, pitch_jitter: float = 0.10,
		bus: String = "SFX") -> void:
	var stream := _load_sfx(sfx_name)
	if stream == null:
		return
	var voice := _next_voice()
	voice.stream = stream
	voice.bus = bus
	voice.volume_db = volume_db + _volume_jitter(pitch_jitter)
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


func _volume_jitter(pitch_jitter: float) -> float:
	if pitch_jitter <= 0.0:
		return 0.0
	return randf_range(-VOLUME_JITTER_DB, VOLUME_JITTER_DB)


## Play `sfx_name` at a world position, so it arrives from somewhere.
##
## The flat ring makes a Spitter's shot at 1800 px exactly as loud and as centred
## as the one at 40 px, in a world 4800x3700 across. Anything that happens TO the
## player - their own gun, taking a hit, a pickup - stays on the flat ring on
## purpose: those are not events at a distance, and panning them would put the
## player's own weapon off to one side of their head.
func play_at(sfx_name: String, at: Vector2, volume_db: float = 0.0,
		pitch_jitter: float = 0.10) -> void:
	var stream := _load_sfx(sfx_name)
	if stream == null:
		return
	var voice := _next_2d_voice()
	voice.global_position = at
	voice.stream = stream
	voice.volume_db = volume_db + _volume_jitter(pitch_jitter)
	voice.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	voice.play()


## As play_throttled, but positional. Shares the same throttle table, so a
## sound cannot dodge its own rate limit by being played through the other ring.
func play_at_throttled(sfx_name: String, at: Vector2, min_interval: float,
		volume_db: float = 0.0, pitch_jitter: float = 0.10) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sfx_name, -999.0)) < min_interval:
		return
	_last_played[sfx_name] = now
	play_at(sfx_name, at, volume_db, pitch_jitter)


## Play, but never more often than `min_interval` seconds for this sound.
##
## Some events fire in bursts that a one-shot-per-event rule turns into noise:
## a kill drops up to five coins, a multi-projectile shot lands nine hits at
## once, a fast gun fires eighteen times a second. Layering a dozen copies of
## the same short sample is what makes a sound effect grating - it stops
## reading as feedback and starts reading as a buzz. Dropping the duplicates
## costs nothing, because they were inaudible as distinct events anyway.
func play_throttled(sfx_name: String, min_interval: float,
		volume_db: float = 0.0, pitch_jitter: float = 0.10) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last_played.get(sfx_name, -999.0)) < min_interval:
		return
	_last_played[sfx_name] = now
	play(sfx_name, volume_db, pitch_jitter)


func play_ui(sfx_name: String, volume_db: float = 0.0) -> void:
	play(sfx_name, volume_db, 0.0, "UI")


func _next_2d_voice() -> AudioStreamPlayer2D:
	for i in SFX_2D_VOICES:
		var idx := (_sfx_2d_next + i) % SFX_2D_VOICES
		if not _sfx_2d_voices[idx].playing:
			_sfx_2d_next = (idx + 1) % SFX_2D_VOICES
			return _sfx_2d_voices[idx]
	var v2 := _sfx_2d_voices[_sfx_2d_next]
	_sfx_2d_next = (_sfx_2d_next + 1) % SFX_2D_VOICES
	return v2


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
	var path := music_path(track)
	if path == "":
		push_warning("Slimer: missing music track %s" % track)
		return null
	var stream: AudioStream = load(path)
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# From the length, not data.size(): under QOA import data is the
		# compressed byte count, which is how the music layers came to loop
		# only their first second.
		wav.loop_end = int(wav.get_length() * wav.mix_rate)
	_music_cache[track] = stream
	return stream


## Where a track is loaded from: the licensed WAV if it is present, otherwise
## the original MP3, otherwise "".
static func music_path(track: String) -> String:
	for path in [LICENSED_MUSIC_DIR + track + ".wav", MUSIC_DIR + track + ".mp3"]:
		if ResourceLoader.exists(path):
			return path
	return ""


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
