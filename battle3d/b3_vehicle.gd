class_name B3Vehicle
extends B3Unit
## Tanks, jeeps, cannons, MG turrets and race cars (helicopters and planes
## are B3Aircraft, which builds on this). A vehicle is still a B3Unit, so it
## has a team, is counted, can win, is targeted, selected and erased like a
## fighter, and the same explosions, bullets, lava and Battle Rules hit it.
## The differences:
##  - It's a heavy physics body that drives instead of walking: while driving
##    it can only spin about its vertical axis (tanks turn slowly on the spot,
##    jeeps and cars need speed to turn). Cannons and MG turrets stay put.
##  - Its turret/gun swivels toward its target on its own; the tank also has
##    a small machine gun for enemies too close for its big gun.
##  - The race car has no gun: it zooms into enemies and BONKs them
##    sky-high (cartoon style, not much damage), and it honks.
##  - Bullets mostly bounce off (see the "shot"/"melee"/"fire" damage shares
##    in B3Defs.UNITS); rockets and bombs do the real damage.
##  - A big blast (or the nuke, or Launch!) unlocks it so it tumbles, flips
##    and rolls; once it stops it hops back onto its wheels.
##  - Destroyed, it blows up and breaks into flying, smoking pieces (hull,
##    turret, wheels...) instead of becoming a ragdoll.
## Driving one yourself (B3Player calls player_drive() every physics step):
##  - Overhead: WASD (c.move) is where to go; it turns and drives there.
##  - First person: W/S gas and reverse, A/D steer (tanks turn on the spot).
##  - The turret aims at the mouse / crosshair (c.aim). Click fires the main
##    gun, right-click the tank's machine gun. Cars honk (Space or click).
##  - eye_xform() puts the first-person camera in the driver's seat (car,
##    jeep), the tank's hatch or behind the cannon / machine gun.
## net_state() / apply_net_state(): the few numbers a copy on another
## computer needs to look right (turret, gun, wheels, tilt, wrecked...).

const TUMBLE := 3.0          # knock speed (after stab) that flips it over
const SHOT_MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY

static var _grip: PhysicsMaterial = null

var vdef: Dictionary = {}
var mobile := false
var tumbling := false
var wrecked := false
var puppet := false             # a network copy: no physics or AI, posed by apply_net_state()
var turret_yaw := 0.0
var gun_pitch := 0.0
var aim_err := PI
var mg: Dictionary = {}
var cd2 := 0.0
var burst2 := 0
var fwd_spd := 0.0
var _posed := false
var _still_t := 0.0
var _tumble_t := 0.0
var _righting := 0.0
var _back := false
var _orbit := 1.0
var _swivel := 0.0
var _ram := {}
var _clang_t := 0.0
var _smoke_t := 0.0
var _tilt := Vector3.ZERO
var _fire_now := false
var _skid := 0.0
var _ram_t := 0.0
var _pitch_lo := -0.2           # how far the gun tilts down / up (radians)
var _pitch_hi := 0.85
var _yaw_lim := PI              # how far the turret turns from straight ahead
var _honk_t := 0.0
var _pass_t := 0.0              # race car: keep zooming on after a bump
# while a person drives it (player_drive)
var _paim := Vector3.ZERO       # what the guns point at
var _pground := Vector3.ZERO    # where shells and cannonballs should land
var _paim_unit: B3Unit = null   # the enemy under the mouse (overhead), if any
var _pdirect := false           # first person: W/S gas, A/D steer
var _pgas := 0.0
var _psteer := 0.0
var _look_ref := 0.0
# puppets (network copies)
var _smoking := false
var _pfx_t := 0.0


static func grip_mat() -> PhysicsMaterial:
	if _grip == null:
		_grip = PhysicsMaterial.new()
		_grip.friction = 0.8
		_grip.bounce = 0.12
	return _grip


func setup(b, k: String, t: String, p: String, seed_: int) -> void:
	super.setup(b, k, t, p, seed_)
	vdef = def
	mobile = float(def.speed) > 0.0
	if String(wpn.get("proj", "")) == "tankshell":
		mg = B3Defs.weapon("tank_mg")
	_orbit = 1.0 if rng.randf() < 0.5 else -1.0
	# swap the walking capsule for the vehicle's own collision shapes
	for c in get_children():
		if c is CollisionShape3D:
			remove_child(c)
			c.queue_free()
	var vr := rig as B3VRig
	for s in vr.shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s.shape
		cs.transform = s.xf
		add_child(cs)
	lock_rotation = false
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0, 0.55, 0)
	angular_damp = 0.4
	bar.position.y = tall + 0.45


func _make_rig() -> void:
	var vr := B3VRig.new()
	vr.build(kind, team, rng)
	rig = vr
	add_child(rig)
	radius = rig.radius
	tall = rig.height
	aim_y = rig.reach_y
	if vr.turret:
		vr.turret.rotation.y = turret_yaw
	if vr.gun:
		vr.gun.rotation.x = -gun_pitch


func center() -> Vector3:
	return global_transform * Vector3(0, aim_y, 0)


func get_up() -> void:
	pass


## Called once, after B3Battle.spawn_unit has set `facing`.
func _pose() -> void:
	if _posed or not is_inside_tree():
		return
	_posed = true
	if rig:
		rig.rotation = Vector3.ZERO
	global_basis = Basis(Vector3.UP, facing)
	reset_physics_interpolation()


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
	stun_t -= dt
	_clang_t -= dt
	_honk_t -= dt
	_pass_t -= dt
	var p := position
	if p.y < -20.0 or absf(p.x) > B3Defs.BOUNDS + 10.0 or absf(p.z) > B3Defs.BOUNDS + 10.0:
		battle.remove_unit(self, false)
		return
	_hazards(dt)
	if dead or wrecked:
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
			_smoke_t = 0.12
			battle.fx.trail(center() + Vector3(rng.randf_range(-0.3, 0.3), 0.6, rng.randf_range(-0.3, 0.3)), 0.45)
	if act != "":
		act_t += dt
		_act_update()
	if held and not tumbling:
		_tumble(Vector3.UP, 1.0)      # picked up: let it dangle and spin
	if tumbling:
		want = Vector3.ZERO
		_tumble_tick(dt)
	elif held:
		want = Vector3.ZERO
	elif player:
		B3Player.control(self, dt)
	elif battle.fighting:
		think_t -= dt
		if think_t <= 0.0:
			think_t = battle.think_period + rng.randf() * 0.12
			_think()
		_vdecide(dt)
	else:
		want = Vector3.ZERO
		look = Vector3.ZERO
	if not tumbling:
		_drive(dt)
	_aim(dt)
	if (battle.fighting or player) and not tumbling and global_basis.y.dot(Vector3.UP) > 0.7:
		_vfire()
	if mobile and not tumbling and battle.fighting:
		_ram_tick()


func _drive(dt: float) -> void:
	var v := linear_velocity
	var gh: float = battle.world.height_at(position.x, position.z)
	# on the ground or a bridge; not at the top of a jump off a ramp
	_grounded = position.y - gh < 0.4 or (absf(v.y) < 1.5 and _feet_on_something(0.45))
	var fwd := global_basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.01:
		fwd = Vector3(sin(facing), 0, cos(facing))
	fwd = fwd.normalized()
	facing = atan2(fwd.x, fwd.z)
	var side := Vector3(fwd.z, 0, -fwd.x)
	fwd_spd = v.dot(fwd)
	var yaw_rate := 0.0
	var target_spd := 0.0
	var turn := float(vdef.get("turn", 1.5))
	var wheeled := style_is("jeep") or style_is("car")
	var accel := 10.0 if style_is("jeep") else (14.0 if style_is("car") else 5.0)
	if mobile:
		if player and _pdirect:
			# first person: W/S gas and reverse, A/D steer (a tank turns on the spot)
			target_spd = _pgas * speed * battle.r_speed * (1.0 if _pgas >= 0.0 else 0.55)
			if wheeled:
				var dir_s := signf(fwd_spd) if absf(fwd_spd) > 0.4 else (signf(_pgas) if _pgas != 0.0 else 1.0)
				yaw_rate = -_psteer * turn * clampf(absf(fwd_spd) / 4.0, 0.3, 1.0) * dir_s
			else:
				yaw_rate = -_psteer * turn * 1.1
			if _pgas * fwd_spd < 0.0:
				accel *= 1.8      # braking
		else:
			var w: Vector3 = want * battle.r_speed
			if w.length() > 0.4:
				var wd := w.normalized()
				var ang := angle_difference(facing, atan2(wd.x, wd.z))
				var reverse := _back and absf(ang) > 1.6
				if reverse:
					ang = angle_difference(facing, atan2(-wd.x, -wd.z))
				var tr := turn
				if wheeled:
					tr = turn * clampf(absf(fwd_spd) / 3.0, 0.3, 1.0)
				yaw_rate = clampf(ang * 3.0, -tr, tr)
				var align := clampf(cos(ang), 0.0, 1.0)
				if wheeled:
					target_spd = w.length() * lerpf(0.35, 1.0, align)
				else:
					target_spd = w.length() * align * align
				if reverse:
					target_spd = -target_spd * 0.55
					yaw_rate = clampf(ang * 3.0, -tr, tr)
		if wheeled:
			(rig as B3VRig).steer_to(clampf(yaw_rate * 0.25, -0.5, 0.5) * signf(fwd_spd + 0.01))
	elif style_is("cannon"):
		yaw_rate = _swivel
	if not mobile:
		accel = 12.0
	var grip := 14.0
	if _skid > 0.0:
		# just got shoved by a blast: slide for a moment
		_skid -= dt
		accel *= 0.15
		grip = 2.0
	var lat := v.dot(side)
	if _grounded:
		fwd_spd = move_toward(fwd_spd, target_spd, accel * dt)
		lat = move_toward(lat, 0.0, grip * dt)
		var hv := fwd * fwd_spd + side * lat
		linear_velocity = Vector3(hv.x, v.y, hv.z)
		angular_velocity = Vector3(0, yaw_rate, 0)
	else:
		angular_velocity = Vector3(0, lerpf(angular_velocity.y, 0.0, minf(1.0, dt * 2.0)), 0)
	_spd = absf(fwd_spd)
	(rig as B3VRig).drive_speed = fwd_spd
	_tilt_to_ground(dt, gh)


## The model leans to match the slope it's on (the body itself stays level).
func _tilt_to_ground(dt: float, gh: float) -> void:
	var t := Vector3.ZERO
	if position.y - gh < 0.5:
		var x := position.x
		var z := position.z
		var hx: float = battle.world.height_at(x + 1.0, z) - battle.world.height_at(x - 1.0, z)
		var hz: float = battle.world.height_at(x, z + 1.0) - battle.world.height_at(x, z - 1.0)
		var n := Vector3(-hx * 0.5, 1.0, -hz * 0.5).normalized()
		var ln := global_basis.inverse() * n
		t = Vector3(atan2(ln.z, ln.y), 0.0, -atan2(ln.x, ln.y))
	_tilt = _tilt.lerp(t, minf(1.0, dt * 6.0))
	rig.rotation = _tilt


func style_is(s: String) -> bool:
	return String(def.style) == s


# -------------------------------------------------------------------- brain
func _think() -> void:
	var old := target
	super._think()
	if style_is("cannon") and target and target.flying:
		# cannonballs can't hit things in the air: pick something on the ground
		var best: B3Unit = null
		var bd := 1e18
		var gr := guard_radius()
		for u: B3Unit in battle.units:
			if u == self or u.down or u.flying or not is_enemy(u):
				continue
			if pers == "defend" and _flat(u.position - home).length() > gr:
				continue
			var d2 := position.distance_squared_to(u.position)
			if d2 < bd:
				bd = d2
				best = u
		target = best
	if style_is("car") and target != null and target != old and pers != "peaceful" and rng.randf() < 0.35:
		_honk()


func _vdecide(dt: float) -> void:
	want = Vector3.ZERO
	look = Vector3.ZERO
	_back = false
	if cheer:
		_cheer(dt)
		return
	if pers == "coward" and hp < max_hp * 0.5:
		fleeing = true
	if pers == "peaceful":
		if mobile:
			_wander(dt, 0.4)
		return
	if target == null or not is_instance_valid(target) or target.down or target.dead:
		target = null
		if not mobile:
			return
		if pers == "defend":
			_go_home()
		elif battle.enemies_left(self):
			_wander(dt, 0.3)
		return
	if not mobile:
		return
	if fleeing:
		_flee(dt)
		return
	var to := _flat(target.position - position)
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	var rng_ := float(wpn.range)
	if pers == "berserk":
		want = dir * speed * 1.15
	elif style_is("car"):
		# zoom straight at it, BONK, keep going for a moment, then come round again
		if _pass_t > 0.0:
			want = forward() * speed
		else:
			var lead := target.position + _flat(target.linear_velocity) * clampf(dist / maxf(speed, 1.0), 0.0, 1.0) * 0.6
			want = _flat(lead - position).normalized() * speed
	elif style_is("jeep"):
		var ring := 14.0 if pers == "ranged" or pers == "defend" else 10.0
		if dist > ring + 6.0:
			want = dir * speed
		else:
			var side := Vector3(-dir.z, 0, dir.x) * _orbit
			want = (side + dir * clampf((dist - ring) / 4.0, -1.0, 1.0)).normalized() * speed * 0.85
			if rng.randf() < dt * 0.05:
				_orbit = -_orbit
	else:
		var stand := rng_ * (0.65 if pers == "ranged" or pers == "defend" else 0.42)
		if dist > stand + 2.0:
			want = dir * speed
		elif dist < 6.0:
			want = -dir * speed * 0.6
			_back = true
	if pers == "defend":
		var off := _flat(position - home)
		if off.length() > guard_radius() + 1.5 and dist > rng_:
			_go_home()
			return
	want += sep * speed * 0.3
	want = _safe(want)
	_unstick(dt)


func _aim(dt: float) -> void:
	var vr := rig as B3VRig
	if vr == null or (vr.turret == null and vr.gun == null):
		return
	var has := false
	var pt := Vector3.ZERO
	if player and ctl:
		has = true
		pt = _paim
	elif target and is_instance_valid(target) and not target.dead:
		has = true
		pt = target.center()
	var turn := float(vdef.get("turn", 1.5))
	var want_yaw := 0.0
	var want_pitch := 0.0
	_swivel = 0.0
	if has:
		var piv := vr.gun.global_position if vr.gun else center()
		var rel := pt - piv
		var flat := Vector2(rel.x, rel.z).length()
		var world_yaw := atan2(rel.x, rel.z)
		want_pitch = atan2(rel.y, flat)
		if style_is("cannon"):
			var lob := _lob(piv, _pground if player and ctl else pt)
			want_pitch = atan2(lob.y, Vector2(lob.x, lob.z).length())
			var e := angle_difference(facing, world_yaw)
			var st := turn * (1.8 if player else 1.0)
			_swivel = clampf(e * 2.5, -st, st)
			aim_err = absf(e)
		else:
			want_yaw = clampf(angle_difference(facing, world_yaw), -_yaw_lim, _yaw_lim)
	if cheer:
		want_yaw = turret_yaw + 1.0
		want_pitch = 0.4
	var tspd := 1.4 if style_is("tank") else turn * 1.4
	if player:
		tspd *= 1.7      # snappier when it's you aiming
	turret_yaw = rotate_toward(turret_yaw, want_yaw, tspd * dt)
	gun_pitch = move_toward(gun_pitch, clampf(want_pitch, _pitch_lo, _pitch_hi), dt * (2.5 if player else 1.5))
	if has and not style_is("cannon"):
		aim_err = absf(angle_difference(turret_yaw, want_yaw))
	if vr.turret:
		vr.turret.rotation.y = turret_yaw
	if vr.gun:
		vr.gun.rotation.x = -gun_pitch


## Launch velocity for a cannonball from `from` to land on `to`.
func _lob(from: Vector3, to: Vector3) -> Vector3:
	var flat := _flat(to - from)
	var tt := clampf(flat.length() / 15.0, 0.9, 2.8)
	return B3Proj.lob(from, to, tt, "cannonball")


# ------------------------------------------------------------- driving it
## A person drives (B3Player.control calls this instead of the AI, every
## physics step). It only sets what to do; _drive, _aim and _vfire do it.
func player_drive(c: B3Ctl, _dt: float) -> void:
	_fp_flash(c)
	look = Vector3.ZERO
	target = null
	fleeing = false
	_pdirect = c.fp and mobile
	_back = false
	if mobile and c.fp:
		_pgas = c.steer.y
		_psteer = c.steer.x
		want = Vector3.ZERO
	elif mobile:
		want = c.move * speed
	else:
		want = Vector3.ZERO
	_player_aim(c)
	if c.fp and (style_is("car") or style_is("jeep")):
		# the view turns with the car (the mouse still looks around)
		c.look_yaw = wrapf(c.look_yaw + angle_difference(_look_ref, facing), -PI, PI)
	_look_ref = facing
	if c.jump:
		c.jump = false
		if style_is("car"):
			_honk()
	# (a tank's turret stays on the crosshair while the hull turns under it)


## No white hit-flash over the view while you look out of it.
func _fp_flash(c: B3Ctl) -> void:
	var vr := rig as B3VRig
	if vr:
		vr.no_flash = c.fp


## Works out _paim (what the guns point at) and _pground (where shells land).
## First person: exactly the crosshair point. Overhead: an enemy under the
## mouse gets aimed at its middle, otherwise the ground under the mouse.
func _player_aim(c: B3Ctl) -> void:
	_paim_unit = null
	if c.fp:
		_paim = c.aim
		_pground = c.aim
		return
	var best: B3Unit = null
	var bd := 1e9
	for o: B3Unit in battle.units_near(c.aim, 2.2, 1.0):
		if o == self or o.down or o.dead or not is_enemy(o):
			continue
		var d := _flat(o.position - c.aim).length()
		if d < maxf(2.2, o.radius + 1.6) and (d < bd or (d == bd and o.grid_i < best.grid_i)):
			bd = d
			best = o
	_paim_unit = best
	if best:
		_paim = best.center()
		_pground = best.position + Vector3(0, 0.3, 0)
	else:
		_paim = c.aim + Vector3(0, 0.9, 0)
		_pground = c.aim


func on_player_start(_c: B3Ctl) -> void:
	_look_ref = facing
	_pgas = 0.0
	_psteer = 0.0
	_fire_now = false
	_paim = center() + forward() * 10.0
	_pground = position + forward() * 10.0


func on_player_stop() -> void:
	if rig:
		(rig as B3VRig).no_flash = false
	_pdirect = false
	_pgas = 0.0
	_psteer = 0.0
	want = Vector3.ZERO


## The first-person camera: driver's seat, tank hatch, behind the gun.
## It looks wherever the mouse says (c.look_yaw / c.look_pitch).
func eye_xform(c: B3Ctl) -> Transform3D:
	var vr := rig as B3VRig
	var p: Vector3
	if vr and vr.eye and is_instance_valid(vr.eye):
		p = vr.eye.get_global_transform_interpolated().origin
	else:
		p = get_global_transform_interpolated() * Vector3(0, tall * 0.85, 0)
	return Transform3D(Basis.from_euler(Vector3(c.look_pitch, c.look_yaw + PI, 0.0)), p)


## The help line shown while you drive it (B3UI).
func controls_help(fp: bool) -> String:
	match String(def.style):
		"tank":
			return ("W/S drive · A/D turn · mouse aims the turret" if fp else "WASD drive · mouse aims the turret") + " · click cannon · right-click machine gun"
		"jeep":
			return ("W/S gas and reverse · A/D steer · mouse aim" if fp else "WASD drive · mouse aim") + " · click machine gun"
		"car":
			return ("W/S gas and reverse · A/D steer" if fp else "WASD drive") + " · bump into enemies! · Space honk"
		"cannon":
			return "mouse aim · click fire (it lobs to where you point)"
	return "mouse aim · click fire"


# ------------------------------------------------------------------ weapons
## The player pressed fire through the fighter code: shoot what we point at.
func _attack(_w: Dictionary) -> void:
	_fire_now = true


func _vfire() -> void:
	var vr := rig as B3VRig
	if vr == null:
		return
	if player:
		if ctl:
			_player_fire(ctl, vr)
		return
	if pers == "peaceful":
		return
	_fire_now = false
	var has_t := target != null and is_instance_valid(target) and not target.down and not target.dead
	if not has_t:
		return
	var dist := _flat(target.position - position).length()
	var rng_ := float(wpn.range)
	var ok := aim_err < (0.09 if style_is("tank") or style_is("cannon") else 0.18) and dist <= rng_ and dist >= float(wpn.get("min", 0.0))
	match String(def.style):
		"tank":
			if cd <= 0.0 and ok:
				_fire_shell()
			if not mg.is_empty() and cd2 <= 0.0 and dist <= float(mg.range) and aim_err < 0.3:
				_vgun(mg, vr.mg_muzzle, true)
		"cannon":
			if cd <= 0.0 and ok and not target.flying:
				_fire_ball()
		"car":
			pass      # no gun: it rams (see _ram_tick)
		_:
			if cd <= 0.0 and ok:
				_vgun(wpn, vr.muzzle, false)


## Fire buttons while a person drives: click = main gun, right-click = the
## tank's machine gun (other guns fire with either). Cars honk.
func _player_fire(c: B3Ctl, vr: B3VRig) -> void:
	var main := c.fire or _fire_now
	_fire_now = false
	match String(def.style):
		"tank":
			if main and cd <= 0.0 and aim_err < 0.3:
				_fire_shell()
			if c.fire2 and cd2 <= 0.0 and not mg.is_empty():
				_vgun(mg, vr.mg_muzzle, true)
		"cannon":
			if main and cd <= 0.0 and aim_err < 0.35:
				_fire_ball()
		"car":
			if main:
				_honk()
		_:
			if (main or c.fire2) and cd <= 0.0 and aim_err < 0.6:
				_vgun(wpn, vr.muzzle, false)


## Where shells and cannonballs go.
func _aim_point() -> Vector3:
	if player and ctl:
		return _pground
	if target and is_instance_valid(target) and not target.dead:
		return target.position
	return center() + forward() * 10.0


## Where bullets go.
func _gun_point() -> Vector3:
	if player and ctl:
		return _paim
	if target and is_instance_valid(target) and not target.dead:
		return target.center()
	return center() + forward() * 10.0 + Vector3(0, 0.5, 0)


func _fire_shell() -> void:
	var from := _muzzle_pos()
	var exact := player and ctl != null and ctl.fp
	var aim := _aim_point() + (Vector3.ZERO if exact else Vector3(0, 0.35, 0))
	var sp := float(wpn.speed)
	var tt := from.distance_to(aim) / sp
	if target and is_instance_valid(target):
		aim += Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * tt * 0.6
	var vel := B3Proj.lob(from, aim, maxf(tt, 0.05), "tankshell")
	battle.spawn_proj("tankshell", from, vel, self, wpn)
	var d := vel.normalized()
	battle.fx.muzzle(from, d, 2.6)
	battle.fx.poof(from + d * 0.5, 0.7)
	battle.snd("cannon", from, 1.0)
	battle.shake(0.12, from)
	if rig:      # (the shot may have blown up something right next to us, and us with it)
		rig.recoil = 1.0
	linear_velocity -= _flat(d) * 0.8
	cd = float(wpn.cd) * rng.randf_range(0.9, 1.15)


func _fire_ball() -> void:
	var from := _muzzle_pos()
	var to := _aim_point()
	if target and is_instance_valid(target):
		to += Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * 1.2
	var vel := _lob(from, to)
	battle.spawn_proj("cannonball", from, vel, self, wpn)
	var d := vel.normalized()
	battle.fx.muzzle(from, d, 3.0)
	battle.fx.poof(from + d * 0.6, 1.0)
	battle.fx.poof(from, 0.7)
	battle.snd("cannon", from, 1.0)
	battle.shake(0.15, from)
	if rig:      # (the shot may have blown up something right next to us, and us with it)
		rig.recoil = 1.0
	linear_velocity -= forward() * 1.6
	cd = float(wpn.cd) * rng.randf_range(0.9, 1.15)


func _vgun(w: Dictionary, mz: Node3D, second: bool) -> void:
	var from := mz.global_position if mz and is_instance_valid(mz) else _muzzle_pos()
	_shoot_ray(w, from, (_gun_point() - from).normalized())
	if not second:
		if rig:      # (the shot may have blown up something right next to us, and us with it)
			rig.recoil = 1.0
		burst += 1
		if burst >= int(w.get("burst", 1)):
			burst = 0
			cd = float(w.get("reload", w.cd))
		else:
			cd = float(w.cd)
	else:
		burst2 += 1
		if burst2 >= int(w.get("burst", 1)):
			burst2 = 0
			cd2 = float(w.get("reload", w.cd))
		else:
			cd2 = float(w.cd)


## One bullet: a ray from `from` along `dir` (with the gun's spread), a
## tracer, a muzzle flash and a bang.
func _shoot_ray(w: Dictionary, from: Vector3, dir: Vector3) -> void:
	var s := float(w.get("spread", 0.05))
	if player and ctl and ctl.fp:
		s *= 0.6
	var d := (dir + Vector3(rng.randf_range(-s, s), rng.randf_range(-s, s) * 0.6, rng.randf_range(-s, s))).normalized()
	var to := from + d * (float(w.range) * 1.4)
	var hit := shot_ray(from, to)
	var end := to
	if not hit.is_empty():
		end = hit.position
		battle.shot_hit(hit, w, d, self)
	var tc: Color = w.get("tracer", Color(4, 3, 1))
	battle.fx.tracer(from, end, tc, 0.06)
	battle.fx.muzzle(from, d)
	battle.snd(String(w.snd), from, 0.5)


## Beep beep! (race car)
func _honk() -> void:
	if _honk_t > 0.0:
		return
	_honk_t = 0.55
	battle.snd("honk", position, 0.9, rng.randf_range(0.95, 1.08))
	battle.fx.word(position + Vector3(0, tall + 0.6, 0), "HONK!", Color("ffe066"))


## Driving into enemies bowls them over.
func _ram_tick() -> void:
	_ram_t -= get_physics_process_delta_time()
	if _spd < 2.5 or _ram_t > 0.0:
		return
	_ram_t = 0.05
	var fwd := forward() * signf(fwd_spd)
	var now: float = battle.time
	var car := style_is("car")
	var hits: Array[B3Unit] = []
	for u: B3Unit in battle.units_near(position, radius + (0.95 if car else 0.35), 1.0):
		if _rams(u, fwd, car, now):
			hits.append(u)
	for u: B3Unit in _in_order(hits):
		if not _rams(u, fwd, car, now):
			continue
		_ram[u.uid] = now
		if car:
			_bump(u, fwd)
			continue
		var heavy := clampf(mass / 1000.0, 1.0, 4.0)
		u.hurt(_spd * 1.6 * heavy, (fwd + Vector3.UP * 0.6).normalized(), _spd * 1.7, self, "hit")
		battle.snd("thud", position, 0.8)
		battle.shake(0.1, position)


## Driving along `fwd` runs into `u` (not bumped in the last second).
func _rams(u: B3Unit, fwd: Vector3, car: bool, now: float) -> bool:
	if u == self or u.down or u.dead or not is_enemy(u) or u.flying:
		return false
	var off := _flat(u.position - position)
	var d := off.length()
	if d > radius + u.radius + (0.95 if car else 0.35) or off.dot(fwd) < 0.3 * d:
		return false
	return float(_ram.get(u.uid, -9.0)) <= now - 1.0


## The race car's cartoon BONK: whoever it hits goes flying up in the air
## (it doesn't hurt much). Big heavy things don't budge: the car bounces off.
func _bump(u: B3Unit, fwd: Vector3) -> void:
	var big := u.mass > mass * 1.5 or u is B3Vehicle
	var dir := (fwd * 0.55 + Vector3.UP).normalized()
	u.hurt(8.0 + _spd * 0.9, dir, 6.0 + _spd * 0.8, self, "hit")
	var at := (position + u.position) * 0.5 + Vector3(0, 1.3, 0)
	battle.fx.word(at, "BOING!" if big else "BONK!", Color("ffffff") if big else Color("8fe3ff"))
	battle.fx.poof(at, 0.5)
	battle.snd("boing", at, 0.9, rng.randf_range(0.95, 1.25))
	if big:
		linear_velocity = -fwd * maxf(3.0, _spd * 0.6) + Vector3.UP * 3.5
		_skid = 0.6
	else:
		linear_velocity.y += 1.2
	_pass_t = 1.1
	if rng.randf() < 0.3:
		_honk()


# --------------------------------------------------------------- damage etc
func hurt(dmg: float, dir: Vector3, knock: float, by: B3Unit = null, how := "hit") -> void:
	if dead or wrecked:
		return
	dmg = maxf(dmg, 0.0) / battle.r_tough      # Battle Rules: toughness and knockback (a hit never heals)
	knock *= battle.r_knock
	var share := 1.0
	match how:
		"shot":
			share = float(vdef.get("shot", 0.5))
		"hit":
			share = float(vdef.get("melee", 0.6))
		"fire":
			share = float(vdef.get("fire", 0.6))
		"blast":
			share = float(vdef.get("blast", 1.0))
	var d := dmg * share * (1.0 - armor)
	hp -= d
	battle.player_hit(by, self)      # first-person hit marker, if it was you
	hurt_t = 0.0
	if rig:
		rig.flash()
	if d >= 1.0:
		battle.fx.number(position + Vector3(0, tall + 0.5, 0), d)
	if (how == "shot" or how == "hit") and _clang_t <= 0.0:
		_clang_t = 0.12
		battle.snd("metal_hit" if how == "shot" else "clang", position, 0.4)
		battle.fx.sparks(center() + Vector3(rng.randf_range(-0.4, 0.4), 0.2, rng.randf_range(-0.4, 0.4)), 4)
	if by and is_instance_valid(by) and by != self and is_enemy(by) and pers != "peaceful" and not by.down and not player:
		if target == null or not is_instance_valid(target) or position.distance_squared_to(by.position) < position.distance_squared_to(target.position) * 0.5:
			target = by
	if pers == "coward" and hp < max_hp * 0.5 and not fleeing and not player:
		fleeing = true
	var kv := knock / stab
	if hp <= 0.0:
		if by and is_instance_valid(by):
			by.kills += 1
		_ko(dir * kv, by)
		return
	if kv > TUMBLE:
		_tumble(dir * kv, kv)
	elif kv > 0.5:
		_nudge(dir, kv)


## Lava, flames and burning only get through its fire share (a tank's thick
## armour keeps most of the heat out); acid eats through anything. Toughness
## and armour count too.
func _env_share(fire: bool) -> float:
	var share := float(vdef.get("fire", 0.6)) if fire else 1.0
	return share * (1.0 - armor) / battle.r_tough


## A smaller knock: slides it a little.
func _nudge(dir: Vector3, kv: float) -> void:
	linear_velocity += Vector3(dir.x, 0.25, dir.z) * kv * 0.6
	_skid = clampf(kv * 0.15, 0.1, 0.6)


## Flips and flings it (big blasts, Launch!). Small pokes just nudge it.
func knock_down(vel: Vector3) -> void:
	if dead or wrecked:
		return
	if vel.length() < 4.0:
		linear_velocity += vel * 0.3
		return
	_tumble(vel, vel.length())


func _tumble(v: Vector3, kv: float) -> void:
	if not tumbling:
		tumbling = true
		axis_lock_angular_x = false
		axis_lock_angular_z = false
		physics_material_override = grip_mat()
		_tumble_t = 0.0
		_still_t = 0.0
		_righting = 0.0
		act = ""
	linear_velocity += v * 0.85
	var hd := Vector3(v.x, 0, v.z)
	var axis := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)).normalized()
	if hd.length() > 0.05:
		axis = Vector3.UP.cross(hd.normalized())
	angular_velocity += axis * clampf(kv * 0.45, 1.0, 9.0) + Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.6
	if kv > 8.0:
		battle.snd("whoosh", position, 0.7)


func _tumble_tick(dt: float) -> void:
	_tumble_t += dt
	_spd = linear_velocity.length()
	(rig as B3VRig).drive_speed = 4.0 if _tumble_t < 2.0 else 0.0
	_tilt = _tilt.lerp(Vector3.ZERO, minf(1.0, dt * 4.0))
	rig.rotation = _tilt
	if _righting > 0.0:
		_righting += dt
		var cur := global_basis.y
		var ang := acos(clampf(cur.dot(Vector3.UP), -1.0, 1.0))
		var axis := cur.cross(Vector3.UP)
		if axis.length() < 0.01:
			axis = global_basis.z
		angular_velocity = axis.normalized() * minf(ang * 5.0, 6.0)
		if (ang < 0.12 and _righting > 0.2) or _righting > 2.5:
			_settle()
		return
	if held:
		_still_t = 0.0
		_tumble_t = 0.0
		return
	if linear_velocity.length() < 0.8 and angular_velocity.length() < 0.8:
		_still_t += dt
	else:
		_still_t = 0.0
	if (_still_t > 0.5 and _tumble_t > 0.6) or _tumble_t > 9.0:
		if global_basis.y.dot(Vector3.UP) > 0.93:
			_settle()
		else:
			_righting = 0.01
			linear_velocity.y = 5.5
			battle.snd("boing", position, 0.7, 0.8)
			battle.fx.dust(position, 1.5)


func _settle() -> void:
	tumbling = false
	_righting = 0.0
	var f := global_basis.z
	f.y = 0.0
	if f.length() > 0.1:
		facing = atan2(f.x, f.z)
	angular_velocity = Vector3.ZERO
	global_basis = Basis(Vector3.UP, facing)
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	physics_material_override = unit_pmat()
	stun_t = 0.3


func _ko(vel: Vector3, by: B3Unit) -> void:
	_wreck(vel, by)


## BOOM: a big blast and the vehicle flies apart into smoking pieces.
func _wreck(vel: Vector3, by: B3Unit) -> void:
	if wrecked or dead:
		return
	var c := center()
	var r := float(vdef.get("boom", 4.0))
	_wreck_visual(vel)
	battle.explode(c, r, 8.0 + r * 0.8, 25.0 + r * 4.0, {"up": 1.0})
	_die(by)


## The look of blowing up (no damage): smoking pieces, fireball, bang.
## Works with physics processing off (network puppets get _wreck() called).
func _wreck_visual(vel: Vector3) -> void:
	if wrecked:
		return
	wrecked = true
	hp = 0.0
	var c := center()
	var local_fx := not _fx_remote()
	var vr := rig as B3VRig
	if vr:
		var hull: RigidBody3D = vr.break_apart(battle, linear_velocity * 0.5 + Vector3(vel.x, 0, vel.z) * 0.3, rng)
		rig = null
		if hull and local_fx:
			var b := Burner.new()
			b.battle = battle
			b.body = hull
			battle.fx.add_child(b)
	disc.visible = false
	bar.visible = false
	collision_layer = 0
	collision_mask = 0
	freeze = true
	var r := float(vdef.get("boom", 4.0))
	if local_fx:
		battle.fx.explosion(c + Vector3(0, 0.8, 0), r * 0.7)
	battle.shake(0.35 + r * 0.05, c)
	battle.snd("mega_boom", c, 1.0)


## True on a friend's computer, where the host's effects are replayed (so a
## puppet mustn't make its own smoke and fireballs as well).
func _fx_remote() -> bool:
	return battle != null and battle.get("puppet") == true


func _process(dt: float) -> void:
	if not _posed and is_inside_tree():
		_pose()
	if puppet and not wrecked:
		_puppet_fx(dt)
	super._process(dt)


## Smoke on a badly hurt puppet (the real one makes its own in physics).
## Skipped when the host's effects are replayed here anyway.
func _puppet_fx(dt: float) -> void:
	if not _smoking or _fx_remote():
		return
	_pfx_t -= dt
	if _pfx_t <= 0.0:
		_pfx_t = 0.12
		battle.fx.trail(center() + Vector3(rng.randf_range(-0.3, 0.3), 0.6, rng.randf_range(-0.3, 0.3)), 0.45)


# ------------------------------------------------------------------ network
## What a copy on another computer needs beyond the body's transform:
## [turret yaw, gun pitch, wheel steer, drive speed, model tilt x, tilt z,
##  flags (1 wrecked, 2 tumbling, 4 smoking, 8 falling)]. B3Aircraft adds
## the rotor / propeller speed.
func net_state() -> Array:
	var vr := rig as B3VRig
	var rr := rig.rotation if rig else Vector3.ZERO
	var flags := 0
	if wrecked:
		flags |= 1
	if tumbling:
		flags |= 2
	if hp < max_hp * 0.35 or _smoking:
		flags |= 4
	if _net_falling():
		flags |= 8
	return [turret_yaw, gun_pitch, vr.steer_angle if vr else 0.0, fwd_spd, rr.x, rr.z, flags]


func _net_falling() -> bool:
	return false


## Poses this copy from another computer's net_state(). It then runs no
## physics or AI of its own (`puppet`); _process keeps the wheels rolling
## and rotors spinning. The wrecked flag is ignored here: blowing up a
## puppet is done by calling _wreck(vel, null) on it.
func apply_net_state(a: Array) -> void:
	if a.size() < 7 or wrecked or dead:
		return
	if not puppet:
		puppet = true
		freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		freeze = true
	turret_yaw = float(a[0])
	gun_pitch = float(a[1])
	fwd_spd = float(a[3])
	_spd = absf(fwd_spd)
	var flags := int(a[6])
	tumbling = flags & 2 != 0
	_smoking = flags & 4 != 0
	var vr := rig as B3VRig
	if vr == null:
		return
	if vr.turret:
		vr.turret.rotation.y = turret_yaw
	if vr.gun:
		vr.gun.rotation.x = -gun_pitch
	vr.steer_to(float(a[2]))
	vr.drive_speed = fwd_spd
	_tilt = Vector3(float(a[4]), 0.0, float(a[5]))
	vr.rotation = _tilt


## Keeps a wreck burning and smoking for a few seconds.
class Burner extends Node3D:
	var battle = null
	var body: Node3D = null
	var life := 7.0
	var _e := 0.0

	func _physics_process(dt: float) -> void:
		life -= dt
		if life <= 0.0 or body == null or not is_instance_valid(body):
			queue_free()
			return
		_e -= dt
		if _e > 0.0:
			return
		_e = 0.09
		var p := body.global_position + Vector3(randf_range(-0.5, 0.5), 0.5, randf_range(-0.5, 0.5))
		if life > 2.5:
			battle.fx.flame(p)
		if randf() < 0.5:
			battle.fx.trail(p + Vector3(0, 0.4, 0), 0.7)
