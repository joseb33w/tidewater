extends Node
## GLOBAL AUDIO — autoloaded as `AudioManager` (see project.godot [autoload]).
## Guarantees EVERY game is audible: ships baked CC0 default SFX + an ambient bed
## (res://audio/), pools SFX voices so overlapping sounds don't cut each other, and
## unlocks the Web AudioContext on the first user gesture (browser autoplay policy /
## iOS Safari) via a "Tap to play" overlay. CC0 audio is from the Ninja Adventure pack;
## the broader library lives at <origin>/godot-assets/audio/ (manifest "audio" section).
##
## Use:
##   AudioManager.play_sfx("hit")                                  # baked: attack/hit/hurt/death/pickup/ui/door
##   AudioManager.register_sfx("boom", load("res://audio/boom.wav"))   # extra SFX you curled from the library
##   AudioManager.play_music(load("res://audio/music_village.ogg"))    # loops; style-match the game (see audio.md)
##   AudioManager.play_ambient(load("res://audio/waves.ogg"))          # per-biome bed; loops

const SFX_VOICES := 8

var _sfx: Array[AudioStreamPlayer] = []
var _i := 0
var _music: AudioStreamPlayer
var _ambient: AudioStreamPlayer
var _bank := {}
var _unlocked := false
var _overlay: CanvasLayer = null
var _world_loops: Array[AudioStreamPlayer3D] = []   # positional loops queued before the web unlock gesture


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS   # audio keeps working while the tree is paused (menus/dialogue)
	for _n in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)
	_music = AudioStreamPlayer.new(); _music.bus = "Music"; add_child(_music)
	_ambient = AudioStreamPlayer.new(); _ambient.bus = "Music"; add_child(_ambient)
	_load_defaults()
	if not OS.has_feature("web"):
		_unlocked = true
		play_default_ambient()
	# On web, playback waits for a user gesture (browser autoplay policy / iOS Safari).
	# The game triggers it ONE of two ways: show_tap_overlay() if it has no start screen
	# (the RPG streaming starter calls this), or unlock() from its own start gate (the
	# 3D/2D starters' "Tap to start" handler calls this).


func _load_defaults() -> void:
	# Neutral CC0 (Kenney) defaults ship as .ogg; .wav kept as a fallback.
	for n in ["attack", "hit", "hurt", "death", "pickup", "ui", "door", "thunder"]:
		for ext in ["ogg", "wav"]:
			var p := "res://audio/%s.%s" % [n, ext]
			if ResourceLoader.exists(p):
				_bank[n] = load(p)
				break


func register_sfx(sname: String, stream: AudioStream) -> void:
	if stream != null:
		_bank[sname] = stream


func has_sfx(sname: String) -> bool:
	return _bank.has(sname)


# Fire a one-shot SFX by name on a free pooled voice. Unknown name = silent no-op.
func play_sfx(sname: String, vol_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = _bank.get(sname, null)
	if s == null:
		return
	var p := _sfx[_i]
	_i = (_i + 1) % _sfx.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.play()


func _loopify(s: AudioStream) -> void:
	if s is AudioStreamOggVorbis:
		(s as AudioStreamOggVorbis).loop = true
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD


# Looping background music on the Music bus. Replaces any current track. Starts once unlocked.
func play_music(stream: AudioStream, vol_db := -7.0) -> void:
	if stream == null:
		return
	_loopify(stream)
	_music.stream = stream
	_music.volume_db = vol_db
	if _unlocked:
		_music.play()


# Looping ambient bed (waves/wind/rain) on the Music bus, quieter than music.
func play_ambient(stream: AudioStream, vol_db := -12.0) -> void:
	if stream == null:
		return
	_loopify(stream)
	_ambient.stream = stream
	_ambient.volume_db = vol_db
	if _unlocked:
		_ambient.play()


# A POSITIONAL looping world sound anchored to a node/spot — a fountain, the road, an
# NPC, a machine. It attenuates with distance + pans, so the soundscape is LOCALIZED to
# its source instead of a global wash. Reserve play_ambient() for WEATHER + at most ONE
# subtle biome bed; everything that belongs to a PLACE or a CHARACTER goes through here
# (a busy city = many quiet localized sources, not one loud omnipresent loop). Returns
# the player; it is freed automatically when its parent node is freed (e.g. cell evict).
func attach_loop(parent: Node3D, stream: AudioStream, vol_db := -8.0, max_distance := 18.0, unit_size := 5.0) -> AudioStreamPlayer3D:
	if parent == null or stream == null:
		return null
	_loopify(stream)
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.bus = "SFX"
	p.volume_db = vol_db
	p.max_distance = max_distance
	p.unit_size = unit_size
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	parent.add_child(p)
	if _unlocked:
		p.play()
	else:
		_world_loops.append(p)   # web autoplay is gated until the first gesture
	return p


# Baked fallback bed so a game is never dead-silent before it sets its own ambient.
func play_default_ambient() -> void:
	if _ambient.stream != null:
		return
	var p := "res://audio/ambient.wav"
	if ResourceLoader.exists(p):
		play_ambient(load(p))


# Web AudioContext starts suspended until a user gesture. Godot's web driver resumes
# on the first canvas input; we ALSO start queued music/ambient here so sound begins
# the moment the player taps.
func unlock() -> void:
	if _unlocked:
		return
	_unlocked = true
	if _ambient.stream == null:
		play_default_ambient()
	if _ambient.stream != null and not _ambient.playing:
		_ambient.play()
	if _music.stream != null and not _music.playing:
		_music.play()
	for wl in _world_loops:
		if is_instance_valid(wl) and not wl.playing:
			wl.play()
	_world_loops.clear()


func set_music_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), db)


func set_sfx_volume_db(db: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("SFX"), db)


func show_tap_overlay() -> void:
	if not OS.has_feature("web") or _unlocked or _overlay != null:
		return
	_overlay = CanvasLayer.new()
	_overlay.layer = 200
	add_child(_overlay)
	var dim := ColorRect.new()
	dim.color = Color(0.04, 0.05, 0.08, 1.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_overlay.add_child(dim)
	var lbl := Label.new()
	lbl.text = "Tap to play"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 42)
	lbl.add_theme_color_override("font_color", Color(0.95, 0.93, 0.85))
	lbl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.add_child(lbl)
	dim.gui_input.connect(_on_overlay_input)


func _on_overlay_input(event: InputEvent) -> void:
	var pressed := (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
		or (event is InputEventKey and (event as InputEventKey).pressed)
	if pressed:
		unlock()
		if _overlay != null:
			_overlay.queue_free()
			_overlay = null
