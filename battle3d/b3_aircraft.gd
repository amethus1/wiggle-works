class_name B3Aircraft
extends B3Vehicle
## Helicopters and fighter planes. They're still B3Vehicles (team, damage
## shares, smoking wrecks, net state), but they fly:
##  - Helicopter: hovers at a height over the ground, slides about and turns
##    its nose anywhere. AI: circles its target with the nose on it, firing
##    the swivelling chin gun and rocket salvos from the stub-wing pods.
##  - Plane: always flies forward (it starts in the air). It steers by
##    turning, climbing and diving, and banks into turns. AI: strafing runs
##    with the wing guns and level bomb runs, then it pulls up, flies on and
##    comes round again. It hunts enemy aircraft first (dogfights!).
##  - Both turn back before the edge of the map (B3Defs.BOUNDS) and keep
##    clear of the ground.
##  - Shot down: it trails smoke and fire, spins and drops, then crashes and
##    blows apart into smoking pieces (B3Vehicle._wreck). It counts as
##    knocked out when it hits the ground.
## The body only turns about its vertical axis (like the other vehicles);
## pitch and bank are on the model (rig.rotation), which net_state() sends.
## Played by a person (player_drive):
##  - Helicopter, both views: Space / Shift climb and descend. Overhead: WASD
##    flies (c.move) and the nose follows the mouse. First person: W/S
##    forward and back, A/D sidestep, the mouse turns it. Click: machine gun,
##    right-click: rockets.
##  - Plane: first person, it smoothly steers to where you look and banks
##    into the turn; W/S is the throttle. Overhead: it flies to (and circles)
##    the mouse, Space / Shift change its height, and holding click on an
##    enemy dives at it. Click: guns, right-click: bomb.

const PLANE_MIN := 4.5      # lowest a plane flies over the ground (it pulls up)
const HELI_MIN := 0.3       # a played helicopter can come right down to land
const CEILING := 42.0

var plane := false
var falling := false            # shot down, on its way to the ground
var parked := false             # scenarios only: sitting on the ground, engine idling
var alt := 10.0                 # wanted height over the ground
var throttle := 0.55
var pitch := 0.0                # nose up (radians): plane = its climb angle
var bank := 0.0                 # rolled right (radians)
var air_spd := 0.0
var rotor := 1.0                # rotor / propeller speed 0..1
var _mode := ""                 # plane AI: "" attack run, "extend", "bomb"
var _mode_t := 0.0
var _want_dir := Vector3.FORWARD
var _want_yaw := 0.0
var _fire_guns := false
var _fire_alt := false          # rockets (helicopter) / bomb (plane)
var _gun_aim := Vector3.ZERO
var _push := Vector3.ZERO       # shoves from blasts, fading away
var _wob := 0.0
var _killer: B3Unit = null
var _fall_t := 0.0
var _spin_v := 0.0
var _bomb_cd := 0.0
var _rocket_cd := 0.0
var _gun_side := 0
var _circle := 0.0
var _circle_uid := -1
var _trail_t := 0.0
var _snd_t := 0.0
var _hv_last := Vector3.ZERO
var _lifting := false
var _next_bomb := false
var _ejected := false           # 🪂 the crew have bailed out (shot down: _eject)


func setup(b, k: String, t: String, p: String, seed_: int) -> void:
	super.setup(b, k, t, p, seed_)
	plane = style_is("plane")
	gravity_scale = 0.0
	center_of_mass = Vector3(0, aim_y, 0)
	angular_damp = 2.0
	disc.visible = false
	alt = rng.randf_range(14.0, 19.0) if plane else rng.randf_range(8.5, 11.5)
	throttle = 0.55
	rotor = 1.0
	_circle = rng.randf() * TAU
	_pitch_lo = -1.4            # the chin gun looks well down
	_pitch_hi = 0.4
	_yaw_lim = 1.9
	_rocket_cd = rng.randf_range(1.0, 3.0)
	_bomb_cd = rng.randf_range(0.5, 2.0)
	_snd_t = rng.randf_range(0.0, 2.0)


func _pose() -> void:
	if _posed or not is_inside_tree():
		return
	super._pose()
	var gh: float = battle.world.height_at(position.x, position.z)
	if parked:
		global_position.y = gh + 0.02
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	elif plane:
		# planes are placed already flying
		global_position.y = maxf(global_position.y, gh + alt)
		air_spd = speed
		linear_velocity = forward() * air_spd
	_want_yaw = facing
	_want_dir = forward()
	reset_physics_interpolation()


func _sync_facing() -> void:
	var f := global_basis.z
	f.y = 0.0
	if f.length_squared() > 0.01:
		facing = atan2(f.x, f.z)


## Where the plane's nose points.
func _nose() -> Vector3:
	return Vector3(sin(facing) * cos(pitch), sin(pitch), cos(facing) * cos(pitch))


# ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if dt <= 0.0 or dead or wrecked or puppet:
		return
	if not _posed:
		_pose()
	hurt_t += dt
	cd -= dt
	cd2 -= dt
	voice_t -= dt
	_clang_t -= dt
	_bomb_cd -= dt
	_rocket_cd -= dt
	_snd_t -= dt
	_mode_t -= dt
	var p := position
	if p.y < -20.0 or absf(p.x) > B3Defs.BOUNDS + 10.0 or absf(p.z) > B3Defs.BOUNDS + 10.0:
		if falling:
			_crash()      # shot down: still knocked out (the shooter gets it, a player moves on)
		else:
			battle.remove_unit(self, false)
		return
	if falling:
		_fall_tick(dt)
		return
	_hazards(dt)
	if dead or wrecked or falling:
		return
	if burn_t > 0.0:
		burn_t -= dt
		hp -= dt * 6.0 * _env_share(true)
		_burn_fx -= dt
		if _burn_fx <= 0.0:
			_burn_fx = 0.15
			battle.fx.flame(center() + Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0.0, 0.5), rng.randf_range(-0.6, 0.6)))
		if hp <= 0.0:
			_ko(Vector3.UP * 2.0, null)
			return
	if hp < max_hp * 0.35:
		_smoke_t -= dt
		if _smoke_t <= 0.0:
			_smoke_t = 0.1
			battle.fx.trail(center() + Vector3(rng.randf_range(-0.3, 0.3), 0.5, rng.randf_range(-0.3, 0.3)), 0.5)
	var vr := rig as B3VRig
	if parked and (battle.fighting or player):
		_unpark(vr)
	if parked:
		rotor = 0.12 if plane else 0.06
		_spd = 0.0
		if vr:
			vr.rotor_speed = rotor
			if vr.gear:
				vr.gear.visible = true
		return
	_fire_guns = false
	_fire_alt = false
	if held:
		_held_tick()
	elif player:
		B3Player.control(self, dt)       # -> player_drive
	elif battle.fighting:
		think_t -= dt
		if think_t <= 0.0:
			think_t = battle.think_period + rng.randf() * 0.12
			_think()
		if plane:
			_plane_ai()
		else:
			_heli_ai(dt)
	else:
		_idle()
	if not held:
		if plane:
			_fly_plane(dt)
		else:
			_fly_heli(dt)
	if not plane:
		_aim(dt)
	if battle.fighting or player:
		_air_fire()
	if vr:
		vr.rotor_speed = rotor
		if vr.bomb_node:
			vr.bomb_node.visible = _bomb_cd <= 0.0
	_engine_snd()


## A parked plane or helicopter takes off (the fight started, or someone's
## flying it).
func _unpark(vr: B3VRig) -> void:
	parked = false
	freeze = false
	if vr and vr.gear:
		vr.gear.visible = false
	var gh: float = battle.world.height_at(position.x, position.z)
	alt = rng.randf_range(14.0, 19.0) if plane else rng.randf_range(8.5, 11.5)
	if plane:
		global_position.y = gh + 1.0
		air_spd = speed * 0.9
		pitch = 0.35
		_want_dir = (forward() + Vector3.UP * 0.5).normalized()
	battle.snd("plane" if plane else "rumble", position, 0.6)


## Picked up with ✋ Grab: dangles (the tool moves it), engine still running.
func _held_tick() -> void:
	_push = Vector3.ZERO
	var gh: float = battle.world.height_at(position.x, position.z)
	alt = clampf(position.y - gh, HELI_MIN if not plane else PLANE_MIN + 2.0, CEILING)
	pitch = 0.0
	if plane:
		air_spd = maxf(air_spd, speed)


## Not fighting yet: planes circle where they were put, helicopters hover.
func _idle() -> void:
	if plane:
		_patrol(home, 24.0)
	else:
		want = Vector3.ZERO
		_want_yaw = facing


## Flies round a big circle about `c` at cruising height.
func _patrol(c: Vector3, r: float) -> void:
	var off := _flat(position - c)
	var dist := off.length()
	var tang := forward()
	if dist > 0.5:
		tang = Vector3(-off.z, 0, off.x).normalized() * _orbit
	var radial := Vector3.ZERO
	if dist > 0.5:
		radial = -off / dist * clampf((dist - r) / r, -1.0, 1.0) * 1.5
	var h := (tang + radial).normalized()
	var gh: float = battle.world.height_at(position.x, position.z)
	var dy := clampf((gh + alt - position.y) * 0.06, -0.4, 0.4)
	_want_dir = Vector3(h.x, dy, h.z).normalized()
	throttle = 0.5


# ------------------------------------------------------------------- flying
func _fly_plane(dt: float) -> void:
	_sync_facing()
	var gh: float = battle.world.height_at(position.x, position.z)
	var d := _want_dir
	if d.length_squared() < 0.001:
		d = _nose()
	d = _edge_steer(d.normalized())
	var want_yaw := atan2(d.x, d.z) if Vector2(d.x, d.z).length() > 0.05 else facing
	var want_pitch := asin(clampf(d.y, -1.0, 1.0))
	# keep clear of the ground: look a little ahead, and pull up in time for
	# how fast it's diving
	var ahead := position + forward() * maxf(8.0, air_spd * 0.9)
	var low := position.y - maxf(gh, battle.world.height_at(ahead.x, ahead.z))
	var need := _pull_up_height()
	var prate := 1.0
	if low < need:
		want_pitch = maxf(want_pitch, 0.35)
		prate = 1.7
	elif low < need + 5.0:
		want_pitch = maxf(want_pitch, lerpf(0.0, -0.8, (low - need) / 5.0))
	if position.y - gh > CEILING:
		want_pitch = minf(want_pitch, -0.15)
	want_pitch = clampf(want_pitch, -0.8, 0.65)
	var turn := float(vdef.get("turn", 1.2)) * (1.15 if player else 1.0)
	if _outward(B3Defs.BOUNDS - air_spd / maxf(0.3, turn) * 0.6):
		turn *= 2.0      # about to leave the map: a tight emergency turn
	var yaw_rate := clampf(angle_difference(facing, want_yaw) * 2.2, -turn, turn)
	pitch = move_toward(pitch, want_pitch, dt * prate)
	var bank_want := clampf(-yaw_rate / turn, -1.0, 1.0) * 0.95
	if cheer:
		bank += dt * 3.5 * _orbit       # victory rolls!
		bank = wrapf(bank, -PI, PI)
	else:
		bank = lerpf(bank, bank_want, minf(1.0, dt * 3.0))
	# speed: throttle, plus diving speeds it up and climbing slows it down
	var spd_want: float = lerpf(speed * 0.7, speed * 1.3, throttle) * battle.r_speed
	air_spd = move_toward(air_spd, spd_want, dt * 5.0)
	air_spd = clampf(air_spd - sin(pitch) * 9.8 * dt * 0.5, speed * 0.55, speed * 1.6)
	_push = _push.move_toward(Vector3.ZERO, dt * 10.0)
	linear_velocity = _wall(_nose() * air_spd + _push)
	angular_velocity = Vector3(0, yaw_rate, 0)
	_spd = air_spd
	fwd_spd = air_spd
	rotor = lerpf(rotor, 0.55 + throttle * 0.45, minf(1.0, dt * 2.0))
	_pose_model(dt, -pitch, bank)


func _fly_heli(dt: float) -> void:
	_sync_facing()
	var gh: float = battle.world.height_at(position.x, position.z)
	var w := _edge_push(want * battle.r_speed)
	var v := linear_velocity
	var hv := Vector3(v.x, 0, v.z).move_toward(Vector3(w.x, 0, w.z), 9.0 * dt)
	var a := clampf(alt, HELI_MIN, CEILING)
	var vy := lerpf(v.y, clampf((gh + a - position.y) * 1.8, -6.0, 6.0), minf(1.0, dt * 3.0))
	_push = _push.move_toward(Vector3.ZERO, dt * 10.0)
	linear_velocity = hv + Vector3(0, vy, 0) + _push
	var turn := float(vdef.get("turn", 2.0)) * (1.6 if player else 1.3)
	var wy := _want_yaw
	if cheer:
		wy = facing + 1.2
	angular_velocity = Vector3(0, clampf(angle_difference(facing, wy) * 4.0, -turn, turn), 0)
	# lean into the way it's going, like a real helicopter
	var fwd := forward()
	var right := Vector3(-fwd.z, 0, fwd.x)
	var acc := (hv - _hv_last) / dt
	_hv_last = hv
	var rx := clampf(hv.dot(fwd) / speed * 0.2 + acc.dot(fwd) * 0.02, -0.4, 0.4)
	var rz := clampf(hv.dot(right) / speed * 0.22 + acc.dot(right) * 0.02, -0.4, 0.4)
	pitch = lerpf(pitch, -rx, minf(1.0, dt * 4.0))
	bank = lerpf(bank, rz, minf(1.0, dt * 4.0))
	_spd = hv.length()
	fwd_spd = hv.dot(fwd)
	rotor = move_toward(rotor, 1.0, dt)
	_pose_model(dt, -pitch, bank)


## How high over the ground it must start pulling out of its dive (it
## drops a bit more while the nose comes up).
func _pull_up_height() -> float:
	var sink := maxf(0.0, -sin(pitch)) * air_spd
	return PLANE_MIN + sink * maxf(0.0, -pitch) * 0.35 + 1.0


## Tilts the model (pitch, bank) plus a wobble after being shoved.
func _pose_model(dt: float, rx: float, rz: float) -> void:
	_wob = maxf(0.0, _wob - dt * 0.8)
	var w := sin(battle.time * 9.0) * _wob * 0.35
	if rig:
		rig.rotation = Vector3(rx + w * 0.5, 0.0, rz + w)


## Planes turn back toward the middle before they reach the edge of the map:
## near an edge, if it wants to go further out, it heads for the middle.
func _edge_steer(d: Vector3) -> Vector3:
	var lim := B3Defs.BOUNDS
	var r := maxf(air_spd, speed * 0.7) / maxf(0.3, float(vdef.get("turn", 1.2)))
	var margin := minf(r * 1.1 + 6.0, lim * 0.8)
	var p := position
	var inward := Vector3.ZERO
	if p.x > lim - margin:
		inward.x -= 1.0
	elif p.x < -lim + margin:
		inward.x += 1.0
	if p.z > lim - margin:
		inward.z -= 1.0
	elif p.z < -lim + margin:
		inward.z += 1.0
	if inward == Vector3.ZERO:
		return d
	var fl := Vector3(d.x, 0, d.z)
	if fl.length() > 0.05 and fl.normalized().dot(inward.normalized()) > 0.3:
		return d       # already heading back in
	var mid := _flat(-p).normalized()
	return Vector3(mid.x, clampf(d.y, -0.3, 0.3), mid.z).normalized()


## True if it's past `edge` (x or z) and still heading further out.
func _outward(edge: float) -> bool:
	var f := forward()
	return (position.x > edge and f.x > 0.0) or (position.x < -edge and f.x < 0.0) \
		or (position.z > edge and f.z > 0.0) or (position.z < -edge and f.z < 0.0)


## The last resort: it can't fly out through the edge of the map at all.
func _wall(v: Vector3) -> Vector3:
	var lim := B3Defs.BOUNDS - 3.0
	var p := position
	if (p.x > lim and v.x > 0.0) or (p.x < -lim and v.x < 0.0):
		v.x = 0.0
	if (p.z > lim and v.z > 0.0) or (p.z < -lim and v.z < 0.0):
		v.z = 0.0
	return v


## Helicopters slow down and back off near the edge of the map.
func _edge_push(w: Vector3) -> Vector3:
	var lim := B3Defs.BOUNDS - 8.0
	var p := position
	if p.x > lim:
		w.x = minf(w.x, -(p.x - lim) * 1.5)
	elif p.x < -lim:
		w.x = maxf(w.x, (-lim - p.x) * 1.5)
	if p.z > lim:
		w.z = minf(w.z, -(p.z - lim) * 1.5)
	elif p.z < -lim:
		w.z = maxf(w.z, (-lim - p.z) * 1.5)
	return w


# -------------------------------------------------------------------- brain
## Planes go after enemy aircraft first (dogfights); helicopters would
## rather shoot at things on the ground (planes are hard to hit). One look
## at everyone: not B3Unit._think as well, whose pick (by distance across the
## ground) this would only throw away, and whose keeping apart from
## neighbours (`sep`) aircraft don't use. (A peaceful one never goes after
## anyone, but its gun still turns to the enemy it would pick.)
func _think() -> void:
	sep = Vector3.ZERO
	ally = null
	var best: B3Unit = null
	var bs := 1e18
	var gr := guard_radius()
	for u: B3Unit in battle.units:
		if u == self or u.down or not is_enemy(u):
			continue
		if pers == "defend" and _flat(u.position - home).length() > gr:
			continue
		var s := position.distance_squared_to(u.position)
		if plane and u.flying:
			s *= 0.3
		elif not plane and u is B3Aircraft and (u as B3Aircraft).plane:
			s *= 3.0
		if u == target:
			s *= 0.55
		if s < bs:
			bs = s
			best = u
	if best != target:
		target = best
		if target and voice_t <= 0.0 and pers != "peaceful":
			_voice()


func guard_radius() -> float:
	return float(wpn.range) + (12.0 if plane else 4.0)


func _has_target() -> bool:
	return target != null and is_instance_valid(target) and not target.down and not target.dead


func _plane_ai() -> void:
	throttle = 0.65
	if cheer or pers == "peaceful" or not _has_target():
		_mode = ""
		_patrol(home, 24.0)
		return
	if pers == "coward" and hp < max_hp * 0.5:
		fleeing = true
	if fleeing:
		var away := _flat(position - target.position).normalized()
		_want_dir = (away + Vector3.UP * 0.2).normalized()
		throttle = 1.0
		return
	var gh: float = battle.world.height_at(position.x, position.z)
	var tp := target.center()
	var to := tp - position
	var dist := to.length()
	var flat := _flat(to)
	var fd := flat.length()
	var air := target.flying
	var turn_r := air_spd / maxf(0.3, float(vdef.get("turn", 1.2)))
	match _mode:
		"extend":
			# fly on, back up to cruising height, then turn in for another go
			throttle = 0.95
			var fl := forward()
			var dy := clampf((gh + alt - position.y) * 0.06, -0.3, 0.45)
			_want_dir = Vector3(fl.x, dy, fl.z).normalized()
			if _mode_t <= 0.0:
				var bomb_run := _next_bomb and not air and pers != "berserk"
				# far enough away to line up (in low gravity bombs fall slowly,
				# so they're let go much further out)
				var lead := _flat(linear_velocity).length() * _bomb_fall_t(position.y - target.position.y)
				if bomb_run and fd < maxf(45.0, lead + 6.0):
					_mode_t = 0.5      # a bit further away first, to line up
				else:
					_mode = "bomb" if bomb_run else ""
					_mode_t = 12.0
		"bomb":
			# a level run over it; let go when the bomb will land on it
			var tf := _bomb_fall_t(position.y - target.position.y)
			var aimp := target.position + _flat(target.linear_velocity) * tf
			var fl2 := _flat(aimp - position)
			var hv := _flat(linear_velocity)
			var hs := maxf(hv.length(), 0.01)
			var hdir := hv / hs
			var along := fl2.dot(hdir)
			var across := (fl2 - hdir * along).length()
			var drop := hs * 0.95 * tf      # the bomb keeps most of the plane's speed
			var dy2 := clampf((gh + maxf(alt, 12.0) - position.y) * 0.06, -0.25, 0.3)
			var fn := fl2.normalized()
			_want_dir = Vector3(fn.x, dy2, fn.z).normalized()
			throttle = 0.7
			var lined := hdir.dot(fn) > 0.8
			if along > 0.0 and absf(along - drop) < 5.0 and across < 5.0:
				_fire_alt = true
				_extend(rng.randf_range(1.6, 2.4))
			elif _mode_t <= 0.0 or (lined and along < drop - 6.0):
				_extend(1.8)      # missed the moment: go round and try again
		_:
			# a strafing run (or a dogfight): nose on it, shoot when lined up.
			# On the ground it comes in at height, then dives on it.
			var lead := tp + target.linear_velocity * clampf(dist / 140.0, 0.0, 0.6)
			var to_l := lead - position
			var flat_l := _flat(to_l)
			var dir := to_l.normalized()
			throttle = 0.8
			_gun_aim = lead
			if air:
				_want_dir = dir
			elif atan2(-to_l.y, flat_l.length()) < 0.42:
				var fl3 := flat_l.normalized()
				var dy3 := clampf((gh + alt - position.y) * 0.06, -0.2, 0.3)
				_want_dir = Vector3(fl3.x, dy3, fl3.z).normalized()
			else:
				dir.y = maxf(dir.y, -0.72)
				_want_dir = dir.normalized()
			if _nose().angle_to(dir) < 0.3 and dist < float(wpn.range):
				_fire_guns = true
			if (not air and (fd < 6.0 or position.y - gh < _pull_up_height() + 1.5)) or (air and dist < 8.0):
				_extend(rng.randf_range(1.1, 1.7))
			elif fd < turn_r * 1.3 and absf(angle_difference(facing, atan2(flat.x, flat.z))) > 1.3:
				# it's inside our turning circle: fly on a bit and come round
				_extend(1.5)


## How long a bomb let go now takes to fall `h` metres (🌍 Gravity rule). It
## leaves already moving down a little (see _drop_bomb).
func _bomb_fall_t(h: float) -> float:
	var g := maxf(0.5, B3Proj.gravity("bomb"))
	var v0 := 1.0 - linear_velocity.y * 0.95
	return (sqrt(v0 * v0 + 2.0 * g * maxf(1.0, h)) - v0) / g


## Break off: fly on and climb for `t` seconds, then come round again
## (half the time for a bomb run, if the bomb is ready).
func _extend(t: float) -> void:
	_mode = "extend"
	_mode_t = t
	_next_bomb = _bomb_cd <= t + 1.0 and rng.randf() < 0.4


func _heli_ai(dt: float) -> void:
	want = Vector3.ZERO
	_want_yaw = facing
	if cheer:
		return
	if pers == "peaceful" or not _has_target():
		var to_home := _flat(home - position)
		if to_home.length() > 6.0:
			want = to_home.normalized() * speed * 0.4
		return
	if pers == "coward" and hp < max_hp * 0.5:
		fleeing = true
	var to := _flat(target.position - position)
	var dist := to.length()
	if fleeing:
		want = -to.normalized() * speed
		_want_yaw = atan2(-to.x, -to.z)
		return
	# circle round it with the nose pointing at it
	var ring := 15.0
	match pers:
		"ranged", "defend":
			ring = 19.0
		"berserk":
			ring = 8.0
	if target.flying:
		ring = 12.0
	if _circle_uid != target.uid:
		_circle_uid = target.uid
		_circle = atan2(position.z - target.position.z, position.x - target.position.x)
	_circle += dt * clampf(5.0 / ring, 0.15, 0.6) * _orbit
	var spot := target.position + Vector3(cos(_circle), 0, sin(_circle)) * ring
	if pers == "defend":
		spot = home + _flat(spot - home).limit_length(guard_radius() * 0.6)
	var mv := _flat(spot - position)
	if mv.length() > 0.3:
		want = mv.normalized() * minf(speed, mv.length() * 0.8)
	_want_yaw = atan2(to.x, to.z)
	if target.flying:
		var gh: float = battle.world.height_at(position.x, position.z)
		alt = clampf(target.position.y - gh, 6.0, 25.0)
	if aim_err < 0.25 and position.distance_to(target.center()) < float(wpn.range):
		_fire_guns = true
	var face_err := absf(angle_difference(facing, _want_yaw))
	if not target.flying and _rocket_cd <= 0.0 and face_err < 0.25 and dist > 7.0 and dist < 34.0:
		_fire_alt = true


# ------------------------------------------------------------------ weapons
func _air_fire() -> void:
	if pers == "peaceful" and not player:
		return
	var vr := rig as B3VRig
	if vr == null:
		return
	if plane:
		if _fire_guns and cd <= 0.0:
			_plane_gun(vr)
		if _fire_alt and _bomb_cd <= 0.0:
			_drop_bomb(vr)
	else:
		if _fire_guns and cd <= 0.0 and aim_err < (0.6 if player else 0.35):
			_vgun(wpn, vr.muzzle, false)
		if _fire_alt and _rocket_cd <= 0.0:
			_rockets(vr)


## The wing guns fire along the nose (or at what you aim at, if it's close
## to where the nose points), left and right in turn.
func _plane_gun(vr: B3VRig) -> void:
	var nose := _nose()
	var mz: Node3D = null
	if not vr.gun_muzzles.is_empty():
		mz = vr.gun_muzzles[_gun_side % vr.gun_muzzles.size()]
	_gun_side += 1
	var from := mz.global_position if mz and is_instance_valid(mz) else center() + nose * 2.0
	var dir := nose
	if _gun_aim != Vector3.ZERO:
		var to := (_gun_aim - from).normalized()
		if nose.angle_to(to) < 0.38:
			dir = to
	_shoot_ray(wpn, from, dir)
	if rig:      # (the shot may have blown up something right next to us, and us with it)
		rig.recoil = 1.0
	burst += 1
	if burst >= int(wpn.get("burst", 1)):
		burst = 0
		cd = float(wpn.get("reload", wpn.cd))
	else:
		cd = float(wpn.cd)


func _drop_bomb(vr: B3VRig) -> void:
	var bw := B3Defs.weapon("plane_bomb")
	var from := vr.bomb_node.global_position if vr.bomb_node else position + Vector3(0, 0.4, 0)
	var v := linear_velocity * 0.95 + Vector3(0, -1.0, 0)
	battle.spawn_proj("bomb", from, v, self, bw)
	battle.snd("whistle", from, 0.6)
	_bomb_cd = float(bw.cd)


## Two rockets, one from each pod.
func _rockets(vr: B3VRig) -> void:
	var rw := B3Defs.weapon("heli_rocket")
	var sp := float(rw.speed)
	var aimp := _aim_point() + Vector3(0, 0.3, 0)
	if not player and _has_target():
		var tt0 := position.distance_to(aimp) / sp
		aimp += _flat(target.linear_velocity) * tt0 * 0.8
	for mz in vr.rocket_muzzles:
		var from := mz.global_position
		var pt := aimp + Vector3(rng.randf_range(-0.6, 0.6), 0, rng.randf_range(-0.6, 0.6))
		var tt := from.distance_to(pt) / sp
		var vel := B3Proj.lob(from, pt, maxf(tt, 0.05), "rocket")
		battle.spawn_proj("rocket", from, vel, self, rw)
		battle.fx.muzzle(from, vel.normalized(), 1.5)
	battle.snd("rocket", position, 0.8)
	if rig:      # (the shot may have blown up something right next to us, and us with it)
		rig.recoil = 1.0
	_rocket_cd = float(rw.cd)


func _engine_snd() -> void:
	if _snd_t > 0.0:
		return
	_snd_t = rng.randf_range(2.2, 3.0) if plane else rng.randf_range(1.8, 2.4)
	if not player and battle.cam and _flat(position - battle.cam.view_center()).length() > 45.0:
		return
	var v := 0.6 if player else 0.3
	if plane:
		battle.snd("plane", position, v, 0.9 + throttle * 0.25)
	else:
		battle.snd("rumble", position, v, 1.6)


# --------------------------------------------------------------- damage etc
func hurt(dmg: float, dir: Vector3, knock: float, by: B3Unit = null, how := "hit") -> void:
	if falling:
		return
	super.hurt(dmg, dir, knock, by, how)


## Aircraft don't flip over: big blasts shove them and make them wobble.
func _tumble(v: Vector3, kv: float) -> void:
	_push = (_push + v * 0.45).limit_length(25.0)
	_wob = clampf(_wob + kv * 0.06, 0.0, 1.0)
	if kv > 8.0:
		battle.snd("whoosh", position, 0.6)


func _nudge(dir: Vector3, kv: float) -> void:
	_push = (_push + Vector3(dir.x, 0.1, dir.z) * kv * 0.4).limit_length(25.0)
	_wob = clampf(_wob + kv * 0.03, 0.0, 1.0)


func knock_down(vel: Vector3) -> void:
	if dead or wrecked or falling:
		return
	_tumble(vel, vel.length())


## Out of health: on the ground it just blows up; in the air it's shot down
## and falls (see _fall_tick), and only counts as knocked out when it lands.
func _ko(vel: Vector3, by: B3Unit) -> void:
	if falling or wrecked or dead:
		return
	var gh: float = battle.world.height_at(position.x, position.z)
	if parked or held or position.y - gh < 2.5:
		_wreck(vel, by)
		return
	falling = true
	down = true          # nobody shoots at it any more
	hp = 0.0
	_killer = by
	target = null
	_fall_t = 0.0
	_spin_v = 1.0
	contact_monitor = true
	max_contacts_reported = 4
	bar.visible = false
	battle.fx.explosion(center(), 1.3)
	battle.snd("boom", position, 0.9)
	battle.snd("whistle", position, 0.7, 0.75)


## Shot down: trailing smoke and fire it spins and drops, and when it hits
## something it crashes and blows apart.
func _fall_tick(dt: float) -> void:
	_fall_t += dt
	if not _ejected and _fall_t > 0.3:
		_eject()
	_sync_facing()
	if plane:
		pitch = move_toward(pitch, -0.95, dt * 0.55)
		bank += dt * 2.4 * _orbit
		air_spd = clampf(air_spd + dt * 3.0, speed * 0.6, speed * 1.4)
		linear_velocity = _wall(_nose() * air_spd + Vector3(0, -_fall_t * 1.5, 0))      # it comes down inside the map
		angular_velocity = Vector3(0, 0.7 * _orbit, 0)
		rotor = maxf(0.2, rotor - dt * 0.3)
		if rig:
			rig.rotation = Vector3(-pitch, 0.0, bank)
	else:
		_spin_v = minf(_spin_v + dt * 5.0, 7.0)
		var v := linear_velocity
		v.y -= 9.8 * B3Rules.gravity_k() * dt * 0.7
		v.x = move_toward(v.x, 0.0, dt * 2.0)
		v.z = move_toward(v.z, 0.0, dt * 2.0)
		linear_velocity = _wall(v)
		angular_velocity = Vector3(0, _spin_v * _orbit, 0)
		rotor = maxf(0.3, rotor - dt * 0.3)
		if rig:
			rig.rotation = Vector3(0.25 + sin(_fall_t * 3.0) * 0.15, 0.0, sin(_fall_t * 2.3) * 0.25)
	var vr := rig as B3VRig
	if vr:
		vr.rotor_speed = rotor
	_trail_t -= dt
	if _trail_t <= 0.0:
		_trail_t = 0.045
		var c := center()
		battle.fx.trail(c + Vector3(rng.randf_range(-0.4, 0.4), 0.3, rng.randf_range(-0.4, 0.4)), 0.8)
		if rng.randf() < 0.6:
			battle.fx.flame(c + Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(0.0, 0.4), rng.randf_range(-0.5, 0.5)))
	var gh: float = battle.world.height_at(position.x, position.z)
	if (_fall_t > 0.15 and get_contact_count() > 0) or position.y - gh < 0.6 or _fall_t > 12.0:
		_crash()


## 🪂 Shot down: the crew bail out under little parachutes in the team
## colour (B3Fx.chute, just for show: they drift down, land and vanish in a
## puff) and the cockpit is empty after.
func _eject() -> void:
	_ejected = true
	var n := 1 if plane else 2
	var vr := rig as B3VRig
	if vr and not vr.crew.is_empty():
		n = clampi(vr.crew.size(), 1, 2)
	_hide_crew()
	var col := B3Defs.team_col(team) if team != "wild" else Color("8a7a52")
	var f := forward()
	var side := Vector3(-f.z, 0.0, f.x)
	var c := center()
	for i in n:
		var s := 0.0 if n == 1 else (1.0 if i == 0 else -1.0)
		var at := c + Vector3(0, 0.9, 0) + side * s * 0.7
		var v := Vector3(linear_velocity.x, 0.0, linear_velocity.z) * 0.3 + Vector3.UP * 8.5 + side * s * 2.5
		battle.fx.chute(at, v, col)
	battle.snd("eject", c, 0.8)


func _hide_crew() -> void:
	var vr := rig as B3VRig
	if vr:
		for cm in vr.crew:
			if is_instance_valid(cm):
				cm.visible = false


func _crash() -> void:
	if not _ejected:
		_eject()      # (it hit something straight away: they pop out of the wreck)
	var v := linear_velocity
	var k: B3Unit = _killer if _killer != null and is_instance_valid(_killer) else null
	battle.shake(0.5, position)
	_wreck(Vector3(v.x, 0, v.z) * 0.4, k)


# ------------------------------------------------------------- flying it
func player_drive(c: B3Ctl, dt: float) -> void:
	_fp_flash(c)
	target = null
	fleeing = false
	_player_aim(c)
	_gun_aim = _paim
	_fire_guns = c.fire or _fire_now
	_fire_now = false
	_fire_alt = c.fire2
	c.jump = false        # Space is "lift" in aircraft
	var gh: float = battle.world.height_at(position.x, position.z)
	if plane:
		throttle = clampf(throttle + c.steer.y * dt * 0.8, 0.0, 1.0)
		if c.fp:
			# like War Thunder: it steers itself toward where you look
			_want_dir = c.look_dir()
		else:
			if c.lift != 0.0:
				alt = clampf(position.y - gh + c.lift * 8.0, PLANE_MIN + 1.0, CEILING)
				_lifting = true
			elif _lifting:
				_lifting = false
				alt = clampf(position.y - gh, PLANE_MIN + 1.0, CEILING)
			var to := _flat(c.aim - position)
			var h := to.normalized() if to.length() > 2.0 else forward()
			var dy := clampf((gh + alt - position.y) * 0.07, -0.45, 0.45)
			_want_dir = Vector3(h.x, dy, h.z).normalized()
			if c.fire and _paim_unit != null and is_instance_valid(_paim_unit):
				# holding the button on an enemy: dive at it
				var dv := (_paim - position).normalized()
				if dv.y < 0.0:
					_want_dir = Vector3(dv.x, maxf(dv.y, -0.6), dv.z).normalized()
	else:
		if c.lift != 0.0:
			alt = clampf(position.y - gh + c.lift * 2.6, HELI_MIN, CEILING)
			_lifting = true
		elif _lifting:
			_lifting = false
			alt = clampf(position.y - gh + linear_velocity.y * 0.25, HELI_MIN, CEILING)
		if c.fp:
			var fwd := forward()
			var right := Vector3(-fwd.z, 0, fwd.x)
			want = (fwd * c.steer.y + right * c.steer.x).limit_length(1.0) * speed
			_want_yaw = c.look_yaw
		else:
			want = c.move * speed
			var to2 := _flat(c.aim - position)
			if to2.length() > 1.5:
				_want_yaw = atan2(to2.x, to2.z)


func on_player_start(c: B3Ctl) -> void:
	super.on_player_start(c)
	var gh: float = battle.world.height_at(position.x, position.z)
	alt = clampf(position.y - gh, HELI_MIN if not plane else PLANE_MIN + 1.0, CEILING)
	_want_yaw = facing
	_want_dir = _nose() if plane else forward()
	_mode = ""


func on_player_stop() -> void:
	super.on_player_stop()
	_fire_guns = false
	_fire_alt = false
	if not plane:
		want = Vector3.ZERO
		_want_yaw = facing


## The cockpit: looking where the mouse says. In the plane the view leans a
## little with the bank.
func eye_xform(c: B3Ctl) -> Transform3D:
	var xf := super.eye_xform(c)
	if plane and not falling:
		xf.basis = Basis.from_euler(Vector3(c.look_pitch, c.look_yaw + PI, -bank * 0.4))
	return xf


func controls_help(fp: bool) -> String:
	if plane:
		if fp:
			return "mouse steers · W/S throttle · click guns · right-click drop a bomb"
		return "mouse: fly there · Space/Shift up and down · W/S throttle · click guns (hold on an enemy to dive) · right-click drop a bomb"
	if fp:
		return "W/S forward and back · A/D sidestep · mouse turns · Space/Shift up and down · click machine gun · right-click rockets"
	return "WASD fly · mouse aims the nose · Space/Shift up and down · click machine gun · right-click rockets"


# ------------------------------------------------------------------ network
## B3Vehicle's state plus [rotor / propeller speed, extras (1 landing gear
## down, 2 bomb loaded)]. The model's pitch and bank are the tilt values.
func net_state() -> Array:
	var a := super.net_state()
	var vr := rig as B3VRig
	var ex := 0
	if vr and vr.gear and vr.gear.visible:
		ex |= 1
	if vr and vr.bomb_node and vr.bomb_node.visible:
		ex |= 2
	a.append(rotor)
	a.append(ex)
	return a


func _net_falling() -> bool:
	return falling


func apply_net_state(a: Array) -> void:
	super.apply_net_state(a)
	if a.size() < 9 or wrecked or dead:
		return
	falling = int(a[6]) & 8 != 0
	rotor = float(a[7])
	var ex := int(a[8])
	var vr := rig as B3VRig
	if vr:
		vr.rotor_speed = rotor
		if vr.gear:
			vr.gear.visible = ex & 1 != 0
		if vr.bomb_node:
			vr.bomb_node.visible = ex & 2 != 0


func _puppet_fx(dt: float) -> void:
	if falling and not _ejected:
		_fall_t += dt
		if _fall_t > 0.3:
			_ejected = true
			_hide_crew()      # (the host's 🪂 parachutes come over as effects)
	if falling and not _fx_remote():
		_trail_t -= dt
		if _trail_t <= 0.0:
			_trail_t = 0.05
			battle.fx.trail(center(), 0.8)
		return
	super._puppet_fx(dt)
