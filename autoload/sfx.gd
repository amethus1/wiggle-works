extends Node
## Sound effects from res://audio/sfx/*.wav and the music loops in
## res://audio/music/ (all made by tools/gen_audio.py). Autoloaded as `Sfx`;
## plays nothing in headless runs (tests, servers) unless a test calls wake().
##
## Effects: a little random pitch on impacts (never on the UI clicks or the
## jingles), quieter with distance from the camera, panned left or right, and
## played on a pool of POOL voices. A free voice is used first; when all are
## busy the least important sound gives way (PRIORITY), so gunfire or
## footsteps never cut off a nuke, a victory tune or a sticker. Bumps, gunfire
## and booms each play at most every few milliseconds (gap_ms), unless the new
## one is much louder (a hit next to you right after one far away).
##
## Buses: SFX (the 🔊 Sound slider, with a gentle compressor) and Music (🎵),
## both into Master, which has a limiter so a 24-voice battle never clips.
## Panned effects go through little "SFX L1".."SFX R3" buses into SFX.
## The music follows what's on screen (mood_now: title, 2D sandbox, building a
## 3D battle, fighting) and crossfades from one loop to the next.

const POOL := 24
const MAX_PER_NAME_PER_FRAME := 2
const SFX_BUS := "SFX"
const MUSIC_BUS := "Music"
const LIMIT_DB := -1.0       # Master's limiter: nothing goes louder than this
# things bumping into things: a pile of blocks or a domino run can hit
# hundreds of times a second, so each of these plays at most every 35 ms
const COLLISION_SOUNDS := ["thud", "clink", "boing", "tink", "squish", "metal_hit"]
const COLLISION_GAP_MS := 35
# a machine-gun line or a chain of barrels the same way (milliseconds)
const GAP_MS := {
	"gun_mg": 30, "gun_pistol": 40, "gun_rifle": 40, "gun_laser": 40, "gun_shotgun": 60, "gun_sniper": 60,
	"bow": 35, "rocket": 50, "bazooka": 70, "cannon": 70,
	"boom": 80, "mega_boom": 140, "firework_burst": 60, "nuke": 400,
	# a tank flattening a fence, a forest catching fire, axes on a tower, a pond full of zaps
	"wood_crunch": 60, "crackle": 120, "chop": 45, "zap_buzz": 90, "plat_crash": 90, "ice_crunch": 60,
}
const LOUDER := 1.5          # ...but one this many times louder than the last still plays
const QUIET := 0.02          # quieter than this (far away): not worth a voice

# how much each sound matters when every voice is busy (higher wins)
const P_LOW := 0             # bumps, hops, swishes: the first to give way
const P_NORMAL := 1          # gunfire, hits, footstep stomps and most things
const P_HIGH := 2            # booms, knock-outs, animal calls, alarms
const P_TOP := 3             # never cut off by anything less: nuke, jingles, roar, UI
const PRIORITY := {
	"thud": P_LOW, "clink": P_LOW, "boing": P_LOW, "tink": P_LOW, "squish": P_LOW, "metal_hit": P_LOW,
	"hop": P_LOW, "grab": P_LOW, "paint": P_LOW, "bubble": P_LOW, "swing": P_LOW,
	"crackle": P_LOW, "land_puff": P_LOW,
	"boom": P_HIGH, "mega_boom": P_HIGH, "ko": P_HIGH, "crumble": P_HIGH, "charge": P_HIGH,
	"alarm": P_HIGH, "plane": P_HIGH, "whistle": P_HIGH, "growl": P_HIGH, "screech": P_HIGH,
	"trumpet": P_HIGH, "moo": P_HIGH, "bark": P_HIGH, "cluck": P_HIGH, "heal": P_HIGH,
	"firework_burst": P_HIGH, "party": P_HIGH, "magic": P_HIGH, "rumble": P_HIGH, "wind": P_HIGH,
	"rain": P_HIGH, "spawn": P_HIGH, "split": P_HIGH, "merge": P_HIGH, "yay": P_HIGH,
	"eject": P_HIGH, "ice_crunch": P_HIGH, "plat_crash": P_HIGH, "swoop": P_HIGH, "grumble": P_HIGH,
	"thwack": P_HIGH,
	"nuke": P_TOP, "victory": P_TOP, "defeat": P_TOP, "roar": P_TOP, "sticker": P_TOP,
	"battle_start": P_TOP, "click": P_TOP, "ding": P_TOP, "undo": P_TOP, "nope": P_TOP,
}
# (chute_open, wood_crunch, chop, laser_ping and zap_buzz are P_NORMAL)
# if a sound's file is missing, play this one instead, at this pitch (the
# sound it had before it got its own: nothing breaks if a file goes astray)
const FALLBACK := {
	"chute_open": ["whoosh", 1.6], "eject": ["pop", 1.0], "wood_crunch": ["crumble", 1.0],
	"crackle": ["flame", 1.0], "chop": ["thud", 1.0], "land_puff": ["boing", 1.3],
	"laser_ping": ["clang", 1.5], "ice_crunch": ["glass", 0.8], "plat_crash": ["crumble", 1.0],
	"zap_buzz": ["zap", 1.0], "swoop": ["screech", 1.0], "grumble": ["trumpet", 0.8], "thwack": ["punch", 0.8],
	"defeat": ["dizzy", 1.0],
}
# the UI and musical jingles keep their pitch (no random wobble: they'd sound out of tune)
const NO_JITTER := ["click", "tick", "ding", "sticker", "victory", "defeat", "battle_start", "charge", "undo", "nope"]
const JITTER := 0.07         # everything else: up to 7% higher or lower each time

const PAN_MAX := 0.6         # how far to the side a sound goes (1 would be one speaker only)
const PAN_STEPS := 3         # panning buses on each side (0.2 apart)
const FP_NEAR := 5.0         # first person: full volume this close (metres)...
const FP_FLOOR := 0.08       # ...then quieter with distance, down to this

const MUSIC_DIR := "res://audio/music/"
## Which loop plays where: the title menu, the 2D sandbox, building a 3D
## battle (and 🌊 Wave Defense between waves), and the fighting.
const MOODS := {"title": "wiggle_loop", "sandbox": "calm_loop", "build": "ready_loop", "battle": "battle_loop"}
const XFADE := 1.5           # seconds to crossfade from one loop to the next
const MOOD_HOLD := 0.35      # a new mood has to last this long before the music changes

var enabled := true
var listener_pos := Vector2.ZERO   # 2D: camera centre in world space (view/cam.gd)
var listener_zoom := 1.0
var mood := ""                     # what the music is playing for (a MOODS key)
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _prio := PackedInt32Array()    # each voice: the priority of what it's playing...
var _ends := PackedInt64Array()    # ...when that ends (ms)...
var _names := PackedStringArray()  # ...and its name
var _played_this_frame := {}
var _cooldown := {}                # sound -> when it last played (ms)
var _cool_vol := {}                # ...and how loud
var _loops := {}                   # music file name -> stream
var _mus: Array[AudioStreamPlayer] = []   # two music players, for crossfading
var _gain := PackedFloat32Array([0.0, 0.0])
var _cur := 0                      # the one playing the current mood (the other fades out)
var _music: AudioStreamPlayer      # (= _mus[_cur])
var _music_on := true              # the 🎵 slider isn't all the way down
var _want_t := 0.0
var _last_us := 0


func _ready() -> void:
	setup_buses()
	set_volume(Settings.volume)
	enabled = DisplayServer.get_name() != "headless"
	if enabled:
		wake()
	set_music(Settings.music)   # (the music starts once there's a mood, unless Music is all the way down)
	_last_us = Time.get_ticks_usec()


## Loads every sound and music loop and makes the voices. Done at start-up,
## except in headless runs, where a test can call it to check the playing.
func wake() -> void:
	enabled = true
	if not _players.is_empty():
		return
	var dir := DirAccess.open("res://audio/sfx")
	if dir:
		for f in dir.get_files():
			# exported builds list ".wav.import"; load by the original name
			var fname := f.trim_suffix(".import")
			if fname.ends_with(".wav") and not _streams.has(fname.get_basename()):
				var s: Resource = load("res://audio/sfx/" + fname)
				if s is AudioStream:
					_streams[fname.get_basename()] = s
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = SFX_BUS
		add_child(p)
		_players.append(p)
	_prio.resize(POOL)
	_ends.resize(POOL)
	_names.resize(POOL)
	for f: String in MOODS.values():
		var path := MUSIC_DIR + f + ".wav"
		var m: Resource = load(path) if ResourceLoader.exists(path) else null
		if m is AudioStreamWAV:
			loop_whole(m)
		if m is AudioStream:
			_loops[f] = m
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = MUSIC_BUS
		add_child(p)
		_mus.append(p)
	_music = _mus[0]
	_music.stream = _loops.get(MOODS.title)
	set_music(Settings.music)


## Makes music `m` loop. tools/gen_audio.py writes each loop with a short
## copy of its end before it and of its start after it, and the loop points
## in the file (Godot's mixer reads a little past both ends of a loop: with
## the loop from the file's first sample to its last, it clicked at the seam).
## A file without loop points loops from its first sample to its last
## (loop_end counts samples: it's imported compressed, so its size in bytes
## says nothing about that).
static func loop_whole(m: AudioStreamWAV) -> void:
	if m.loop_mode == AudioStreamWAV.LOOP_FORWARD and m.loop_end > m.loop_begin:
		return
	m.loop_mode = AudioStreamWAV.LOOP_FORWARD
	m.loop_begin = 0
	m.loop_end = int(round(m.get_length() * m.mix_rate))


## The buses (default_bus_layout.tres has the first three; this puts back
## anything missing): SFX and Music into Master, Master's limiter, the SFX
## compressor, and the panning buses into SFX.
static func setup_buses() -> void:
	_add_bus(SFX_BUS)
	_add_bus(MUSIC_BUS)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = LIMIT_DB
	lim.release = 0.12
	_ensure_fx(0, lim)
	var comp := AudioEffectCompressor.new()
	comp.threshold = -6.0
	comp.ratio = 3.0
	comp.attack_us = 2000.0
	comp.release_ms = 200.0
	_ensure_fx(AudioServer.get_bus_index(SFX_BUS), comp)
	for k in range(1, PAN_STEPS + 1):
		for side in [-1, 1]:
			var q := float(side * k) / PAN_STEPS * PAN_MAX
			var bus_name := pan_bus(q)
			if AudioServer.get_bus_index(bus_name) != -1:
				continue
			_add_bus(bus_name, SFX_BUS)
			var i := AudioServer.get_bus_index(bus_name)
			var pn := AudioEffectPanner.new()
			pn.pan = q
			AudioServer.add_bus_effect(i, pn)
			# Godot's panner moves the other side's sound over (louder in all):
			# this keeps the loudness the same wherever it is
			AudioServer.set_bus_volume_db(i, -10.0 * log(1.0 + q * q) / log(10.0))


## Adds bus `bus_name` (feeding `send`, which must be an earlier bus) unless it's there already.
static func _add_bus(bus_name: String, send := "Master") -> void:
	if AudioServer.get_bus_index(bus_name) != -1:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, send)


## Puts effect `fx` on bus `bus` unless one of its kind is there already.
static func _ensure_fx(bus: int, fx: AudioEffect) -> void:
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i).get_class() == fx.get_class():
			return
	AudioServer.add_bus_effect(bus, fx)


## The bus a sound panned `pan` (-PAN_MAX left .. PAN_MAX right) plays on.
static func pan_bus(pan: float) -> String:
	var k := clampi(roundi(pan / PAN_MAX * PAN_STEPS), -PAN_STEPS, PAN_STEPS)
	if k == 0:
		return SFX_BUS
	return "%s %s%d" % [SFX_BUS, "R" if k > 0 else "L", absi(k)]


func _process(_d: float) -> void:
	_played_this_frame.clear()
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.25)    # real time (slow motion doesn't slow the fades)
	_last_us = now
	_music_tick(dt)


## 🔊 Sound: the effects bus only, so the music keeps its own level.
func set_volume(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(SFX_BUS), _db(v))


## 🎵 Music: the music bus (at half the slider, under the effects). Stops the
## music at the bottom of the slider, and starts it again above that.
func set_music(v: float) -> void:
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MUSIC_BUS), _db(v * 0.5))
	_music_on = v > 0.01
	if _mus.is_empty():
		return
	if not _music_on:
		for i in _mus.size():
			_mus[i].stop()
			_gain[i] = 0.0
	elif not _music.playing and mood != "":
		_start_loop(mood)


static func _db(v: float) -> float:
	return linear_to_db(clampf(v, 0.0001, 1.0))


func has(sound: String) -> bool:
	return _streams.has(sound)


## How much `sound` matters when every voice is busy (P_LOW..P_TOP).
static func priority(sound: String) -> int:
	return int(PRIORITY.get(sound, P_NORMAL))


## Plays `sound` (file name without .wav). `at` (a 2D world position) makes it
## quieter with distance from the camera and pans it by where it is on
## screen; 3D Battle works both out itself (B3Battle.hear) and passes `pan`
## (-PAN_MAX left .. PAN_MAX right). strength 0..1+ scales the volume.
func play(sound: String, at = null, strength := 1.0, pitch := 1.0, pan := 0.0) -> void:
	play_timed(sound, at, strength, pitch, pan, Time.get_ticks_msec())


## play() as if at time `now` (ms; tests pick it). Returns the voice it went
## to, or -1 if it didn't play.
func play_timed(sound: String, at: Variant, strength: float, pitch: float, pan: float, now: int) -> int:
	if not enabled:
		return -1
	if not _streams.has(sound):
		var fb: Array = FALLBACK.get(sound, [])
		if fb.size() != 2 or not _streams.has(String(fb[0])):
			return -1
		return play_timed(String(fb[0]), at, strength, pitch * float(fb[1]), pan, now)
	var vol := clampf(strength, 0.05, 1.6)
	var pn := pan
	if at is Vector2:
		var h := hear2d(at as Vector2, listener_pos, listener_zoom, get_viewport().get_visible_rect().size.x)
		vol *= h.x
		pn = h.y
	if vol < QUIET:
		return -1
	# (the limits go by how loud it is here, after the distance: a far-away
	# thud doesn't hold up the one right next to you)
	var n: int = _played_this_frame.get(sound, 0)
	if n >= MAX_PER_NAME_PER_FRAME:
		return -1
	if too_soon(sound, now, vol):
		return -1
	var pr := priority(sound)
	var i := _voice(pr)
	if i < 0:
		return -1
	_played_this_frame[sound] = n + 1
	var s: AudioStream = _streams[sound]
	var ps := pitch if NO_JITTER.has(sound) else pitch * randf_range(1.0 - JITTER, 1.0 + JITTER)
	var p := _players[i]
	p.stream = s
	p.bus = pan_bus(pn)
	p.volume_db = linear_to_db(vol) - 4.0
	p.pitch_scale = ps
	p.play()
	_prio[i] = pr
	_ends[i] = now + int(s.get_length() * 1000.0 / maxf(ps, 0.01))
	_names[i] = sound
	return i


## The voice for a new sound of priority `prio`.
func _voice(prio: int) -> int:
	var busy: Array[bool] = []
	busy.resize(_players.size())
	for i in _players.size():
		busy[i] = _players[i].playing
	return pick_voice(busy, _prio, _ends, prio)


## A free voice (busy[i] false) if there is one. Otherwise the busy one
## playing the least important sound (prios), the one ending soonest (ends)
## of those, but never one more important than `prio`: -1 means none (the
## new sound doesn't play).
static func pick_voice(busy: Array[bool], prios: PackedInt32Array, ends: PackedInt64Array, prio: int) -> int:
	var best := -1
	for i in busy.size():
		if not busy[i]:
			return i
		if prios[i] > prio:
			continue
		if best < 0 or prios[i] < prios[best] or (prios[i] == prios[best] and ends[i] < ends[best]):
			best = i
	return best


## What voice `i` is playing ("" when it's quiet).
func voice_sound(i: int) -> String:
	if i < 0 or i >= _players.size() or not _players[i].playing:
		return ""
	return _names[i]


## The pause between two of the same sound (ms; 0 for most sounds).
static func gap_ms(sound: String) -> int:
	if COLLISION_SOUNDS.has(sound):
		return COLLISION_GAP_MS
	return int(GAP_MS.get(sound, 0))


## True if `sound` (a bump, gunshot or boom: gap_ms) already played less than
## its gap before `now` (ms) and this one, at `vol`, isn't LOUDER times
## louder than that one. Otherwise remembers this one as the last.
func too_soon(sound: String, now: int, vol := 1.0) -> bool:
	var gap := gap_ms(sound)
	if gap <= 0:
		return false
	if _cooldown.has(sound):
		var since := now - int(_cooldown[sound])
		if since >= 0 and since < gap and vol <= float(_cool_vol.get(sound, 0.0)) * LOUDER:
			return true
	_cooldown[sound] = now
	_cool_vol[sound] = vol
	return false


## Volume (x, 0..1) and pan (y) of a 2D sound at `at`, with the camera centred
## on `ear`, zoomed `zoom`, the view `view_w` wide: quieter further away,
## panned by where it is across the screen.
static func hear2d(at: Vector2, ear: Vector2, zoom: float, view_w: float) -> Vector2:
	var off := (at - ear) * zoom
	var vol := clampf(1.25 - off.length() / 1800.0, 0.15, 1.0)
	var pan := clampf(off.x / maxf(view_w * 0.5, 1.0), -1.0, 1.0) * PAN_MAX
	return Vector2(vol, pan)


## Volume (x) and pan (y) of a 3D sound at `p` for a camera at `ear` facing
## along -basis.z (+basis.x is its right), by the real 3D distance (height
## counts). First person (`fp`): full volume within FP_NEAR metres, then
## quieter like a real sound (about half as loud twice as far), panned by the
## direction it comes from. Overhead (`fp` false, `ear` the ground in the
## middle of the view, `view` metres tall, `half_w` metres from the middle
## to the side): everything on screen stays loud, fading past the edges,
## panned by where it is across the screen.
static func hear3d(p: Vector3, ear: Vector3, basis: Basis, fp: bool, view := 36.0, half_w := 32.0) -> Vector2:
	var d := p - ear
	var dist := d.length()
	var side := d.dot(basis.x.normalized())
	var vol := 0.0
	var pan := 0.0
	if fp:
		vol = clampf(pow(FP_NEAR / maxf(dist, FP_NEAR), 0.85), FP_FLOOR, 1.0)
		pan = side / maxf(dist, 2.0)     # (right next to you it isn't all in one ear)
	else:
		vol = clampf(1.25 - dist / (maxf(view, 1.0) * 1.4), 0.12, 1.0)
		pan = side / maxf(half_w, 1.0)
	return Vector2(vol, clampf(pan, -1.0, 1.0) * PAN_MAX)


# ------------------------------------------------------------------- music
## What the music should be for right now (a MOODS key): the title menu,
## the 2D sandbox, or whatever the game says (B3Battle.music_mood: building
## or fighting).
func mood_now() -> String:
	var tree := get_tree()
	var main: Node = tree.current_scene if tree else null
	if main == null:
		return "title"
	var g: Variant = main.get("game")
	if not is_instance_valid(g) or not (g is Node) or (g as Node).is_queued_for_deletion():
		return "title"
	if (g as Node).has_method("music_mood"):
		return String((g as Node).call("music_mood"))
	return "sandbox"


## The music file for the mood now ("" before the first one).
func track() -> String:
	return String(MOODS.get(mood, ""))


func _music_tick(dt: float) -> void:
	var want := mood_now()
	if want == mood:
		_want_t = 0.0
	else:
		_want_t += dt
		if mood == "" or _want_t >= MOOD_HOLD:
			_want_t = 0.0
			set_mood(want)
	for i in _mus.size():
		var goal := 1.0 if i == _cur and _mus[i].playing else 0.0
		if _gain[i] == goal:
			continue
		_gain[i] = move_toward(_gain[i], goal, dt / XFADE)
		_mus[i].volume_db = _fade_db(_gain[i])
		if _gain[i] <= 0.0:
			_mus[i].stop()


## Equal-loudness crossfade: halfway through, both loops are at 71%.
static func _fade_db(g: float) -> float:
	return linear_to_db(maxf(sin(clampf(g, 0.0, 1.0) * PI * 0.5), 0.0001))


## Changes the music to mood `m` (see MOODS), crossfading from what's on.
func set_mood(m: String) -> void:
	mood = m
	if _mus.is_empty() or not _music_on:
		return
	_start_loop(m)


func _start_loop(m: String) -> void:
	var s: AudioStream = _loops.get(String(MOODS.get(m, "")))
	if s == null:
		return
	if _music.stream == s and _music.playing:
		return
	var other := 1 - _cur
	if _mus[other].stream == s and _mus[other].playing:
		_cur = other        # it was still fading out: it comes back from where it got to
	else:
		var p := _mus[other]
		p.stream = s
		_gain[other] = 0.0
		p.volume_db = _fade_db(0.0)
		p.play()
		_cur = other
	_music = _mus[_cur]


## How loud music player `i` is in the crossfade (0..1), for tests.
func music_gain(i: int) -> float:
	return _gain[i] if i >= 0 and i < _gain.size() else 0.0
