extends Node
## Sound effects from res://audio/sfx/*.wav (made by tools/gen_audio.py), with
## random pitch variation, distance fade from the camera, and a voice pool.
## Also plays the background music loop. Effects and music have their own
## buses (both feed Master), so the 🔊 Sound and 🎵 Music sliders are separate.
## Autoloaded as `Sfx`; plays nothing in headless runs (tests, servers).

const POOL := 24
const MAX_PER_NAME_PER_FRAME := 2
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
# things bumping into things: a pile of blocks or a domino run can hit
# hundreds of times a second, so each of these plays at most every 35 ms
const COLLISION_SOUNDS := ["thud", "clink", "boing", "tink", "squish", "metal_hit"]
const COLLISION_GAP_MS := 35

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
	_add_bus(SFX_BUS)
	_add_bus(MUSIC_BUS)
	set_volume(Settings.volume)
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
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.bus = MUSIC_BUS
	add_child(_music)
	var m = load("res://audio/music/wiggle_loop.wav") if ResourceLoader.exists("res://audio/music/wiggle_loop.wav") else null
	if m:
		if m is AudioStreamWAV:
			loop_whole(m)
		_music.stream = m
	set_music(Settings.music)   # starts it, unless Music is turned all the way down


## Makes `m` loop from its first sample to its last. loop_end counts samples;
## the file is imported compressed, so its size in bytes says nothing about that.
static func loop_whole(m: AudioStreamWAV) -> void:
	m.loop_mode = AudioStreamWAV.LOOP_FORWARD
	m.loop_begin = 0
	m.loop_end = int(round(m.get_length() * m.mix_rate))


## Adds bus `bus_name` (feeding Master) unless it's there already.
static func _add_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _process(_d: float) -> void:
	_played_this_frame.clear()


## 🔊 Sound: the effects bus only, so the music keeps its own level.
func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), _db(v))


## 🎵 Music: the music bus (at half the slider, under the effects). Stops the
## music at the bottom of the slider, and starts it again above that.
func set_music(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), _db(v * 0.5))
	if _music:
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
	if too_soon(sound, Time.get_ticks_msec()):
		return
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


## True if collision sound `sound` already played less than COLLISION_GAP_MS
## before `now` (milliseconds); otherwise remembers `now` as its last time.
func too_soon(sound: String, now: int) -> bool:
	if not COLLISION_SOUNDS.has(sound):
		return false
	if _cooldown.has(sound) and now - int(_cooldown[sound]) < COLLISION_GAP_MS:
		return true
	_cooldown[sound] = now
	return false
