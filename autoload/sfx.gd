extends Node
## Sound effects from res://audio/sfx/*.wav (made by tools/gen_audio.py), with
## random pitch variation, distance fade from the camera, and a voice pool.
## Also plays the background music loop. Autoloaded as `Sfx`; does nothing
## in headless runs (tests, servers).

const POOL := 24
const MAX_PER_NAME_PER_FRAME := 2

var enabled := true
var listener_pos := Vector2.ZERO   # camera centre in world space
var listener_zoom := 1.0
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _played_this_frame := {}
var _cooldown := {}
var _music: AudioStreamPlayer


func _ready() -> void:
	enabled = DisplayServer.get_name() != "headless"
	if not enabled:
		return
	var dir := DirAccess.open("res://audio/sfx")
	if dir:
		for f in dir.get_files():
			# exported builds list ".wav.import"; load by the original name
			var fname := f.trim_suffix(".import")
			if fname.ends_with(".wav") and not _streams.has(fname.get_basename()):
				var s = load("res://audio/sfx/" + fname)
				if s:
					_streams[fname.get_basename()] = s
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	var m = load("res://audio/music/wiggle_loop.wav") if ResourceLoader.exists("res://audio/music/wiggle_loop.wav") else null
	if m:
		if m is AudioStreamWAV:
			m.loop_mode = AudioStreamWAV.LOOP_FORWARD
			m.loop_begin = 0
			m.loop_end = m.data.size() / 2   # 16-bit mono frames
		_music.stream = m
		_music.volume_db = _db(Settings.music * 0.5)
		_music.play()
	set_volume(Settings.volume)


func _process(_d: float) -> void:
	_played_this_frame.clear()


func set_volume(v: float) -> void:
	if not enabled:
		return
	AudioServer.set_bus_volume_db(0, _db(v))


func set_music(v: float) -> void:
	if _music:
		_music.volume_db = _db(v * 0.5)
		if v <= 0.01:
			_music.stop()
		elif not _music.playing and _music.stream:
			_music.play()


static func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 1.0))


func has(sound: String) -> bool:
	return _streams.has(sound)


## Plays `sound` (file name without .wav). `at` (world position) fades it with
## distance from the camera; strength 0..1+ scales volume.
func play(sound: String, at = null, strength := 1.0, pitch := 1.0) -> void:
	if not enabled or not _streams.has(sound):
		return
	var n: int = _played_this_frame.get(sound, 0)
	if n >= MAX_PER_NAME_PER_FRAME:
		return
	var now := Time.get_ticks_msec()
	if now - int(_cooldown.get(sound, 0)) < 35 and sound.begins_with("impact"):
		return
	_cooldown[sound] = now
	_played_this_frame[sound] = n + 1
	var vol := clampf(strength, 0.05, 1.6)
	if at is Vector2:
		var d := ((at as Vector2) - listener_pos).length() * listener_zoom
		vol *= clampf(1.25 - d / 1800.0, 0.15, 1.0)
	var p := _players[_next]
	_next = (_next + 1) % POOL
	p.stream = _streams[sound]
	p.volume_db = linear_to_db(vol) - 4.0
	p.pitch_scale = pitch * randf_range(0.93, 1.07)
	p.play()
