class_name B3Special
extends B3Unit
## Fighters with extra moves on top of the normal B3Unit brain:
##   Wizard  - waves its staff and casts fireballs (see B3Proj "fireball").
##   Robot   - charges up and fires a fat laser beam; clanky steps; it
##             clangs when hit and falls apart when KO'd (B3Ragdoll).
##   Gorilla - fast punches, a two-fisted ground-pound shockwave when
##             enemies crowd it, throws boulders at far-away enemies and
##             beats its chest when it spots someone.
##   Dragon  - flies big circles around its target and breathes a cone of
##             fire that sets fighters burning and lights the ground.
## B3Special.make() picks the right script (fighter / special / vehicle).

const HOLD_ACTS := ["pound", "hurl", "beat", "cast"]

var _pound_cd := 2.0
var _rock_cd := 3.0
var _step := 0
var _flap := 0
var _orbit := 1.0
var _tick := 0.0
var _fx_t := 0.0
var _lit := false
var _bdir := Vector3.FORWARD
var _dive := false
var _dive_t := 0.0
var _dive_cd := 3.0


## A new, not yet set up unit of the right script for `kind`.
static func make(kind: String) -> B3Unit:
	if B3Defs.is_vehicle(kind):
		if bool(B3Defs.unit_def(kind).get("air", false)):
			return B3Aircraft.new()      # helicopter, plane
		return B3Vehicle.new()
	var d := B3Defs.unit_def(kind)
	if bool(d.get("special", false)):
		return B3Special.new()
	return B3Unit.new()


func setup(b, k: String, t: String, p: String, seed_: int) -> void:
	super.setup(b, k, t, p, seed_)
	_orbit = 1.0 if rng.randf() < 0.5 else -1.0
	_pound_cd = rng.randf_range(1.0, 3.0)
	_rock_cd = rng.randf_range(2.0, 5.0)


func _physics_process(dt: float) -> void:
	_pound_cd -= dt
	_rock_cd -= dt
	_dive_cd -= dt
	if kind == "dragon":
		burn_t = 0.0          # dragons don't mind fire
	super._physics_process(dt)


# -------------------------------------------------------------------- brain
func _decide(dt: float) -> void:
	if act in HOLD_ACTS and not cheer:
		want = Vector3.ZERO
		look = Vector3.ZERO
		if target and is_instance_valid(target):
			look = _flat(target.position - position).normalized()
		return
	if kind == "gorilla" and _gorilla_moves():
		return
	super._decide(dt)


func _gorilla_moves() -> bool:
	if cheer or act != "" or not _grounded or pers == "peaceful" or fleeing or burn_t > 0.0 or stun_t > 0.0:
		return false
	if target == null or not is_instance_valid(target) or target.down or target.dead:
		return false
	var d := _flat(target.position - position).length()
	if _pound_cd <= 0.0:
		var near := 0
		for u: B3Unit in battle.units:
			if u != self and not u.down and is_enemy(u) and _flat(u.position - position).length() < 3.2 + u.radius:
				near += 1
		if near >= 2 or (near >= 1 and rng.randf() < 0.3):
			_start_act("pound", 0.95, B3Defs.weapon("gorilla_pound"))
			_pound_cd = rng.randf_range(4.5, 7.0)
			want = Vector3.ZERO
			look = _flat(target.position - position).normalized()
			battle.snd("growl", position, 0.7)
			return true
		_pound_cd = 0.4
	if _rock_cd <= 0.0 and d > 6.5 and d < 17.0 and pers != "berserk" and not target.flying:
		_start_act("hurl", 1.15, B3Defs.weapon("boulder"))
		_rock_cd = rng.randf_range(6.0, 9.5)
		want = Vector3.ZERO
		look = _flat(target.position - position).normalized()
		return true
	return false


func _voice() -> void:
	super._voice()
	if act != "" or not battle.fighting:
		return
	if kind == "gorilla" and _grounded and rng.randf() < 0.7:
		_start_act("beat", 1.1, wpn)
	elif kind == "dragon":
		_start_act("roar", 1.0, wpn)
		battle.shake(0.2, position)


# ------------------------------------------------------------------ attacks
func _attack(w: Dictionary) -> void:
	if String(w.type) == "breath":
		_start_breath()
		return
	if String(w.get("proj", "")) == "fireball":
		_start_act("cast", 0.6, w)
		cd = float(w.cd) * rng.randf_range(0.9, 1.15)
		battle.snd("magic", position, 0.45)
		return
	super._attack(w)


func _act_update() -> void:
	var k := act_t / maxf(act_len, 0.01)
	match act:
		"pound":
			if not act_fired and k >= 0.55:
				act_fired = true
				_melee_hit(act_w)
				var c := position + forward() * (radius + 0.6)
				battle.fx.ring(c + Vector3(0, 0.3, 0), 0.6, float(act_w.aoe) * 1.25, 0.45, Color(1.0, 0.95, 0.8, 0.8))
		"hurl":
			if not act_fired and k >= 0.62:
				act_fired = true
				_hurl()
		"cast":
			_fx_t -= get_physics_process_delta_time()
			if _fx_t <= 0.0:
				_fx_t = 0.07
				battle.fx.flame(_muzzle_pos() + Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.05, 0.15), rng.randf_range(-0.12, 0.12)))
			if k >= 1.0:
				act = ""
				if target and is_instance_valid(target) and not target.down:
					_shoot_proj(act_w)
					battle.fx.muzzle(_muzzle_pos(), forward(), 1.3)
				return
		"breath":
			_breath(get_physics_process_delta_time(), k)
		"beat":
			pass
		_:
			super._act_update()
			return
	if k >= 1.0:
		act = ""


func _hurl() -> void:
	var aim: Vector3
	if player and ctl:
		# right-click (B3Player): it lands where you're aiming, up to a good throw away
		aim = ctl.aim
		var off := _flat(aim - position)
		if off.length() > 24.0:
			aim = position + off.normalized() * 24.0
			aim.y = battle.world.height_at(aim.x, aim.z)
		aim += Vector3(0, 0.4, 0)
	elif target and is_instance_valid(target):
		aim = target.position + Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * 0.5 + Vector3(0, 0.4, 0)
	else:
		return
	var from := position + Vector3(0, tall + 0.35, 0) + forward() * 0.35
	var flat := _flat(aim - from)
	var tt := clampf(flat.length() / 12.0, 0.55, 1.4)
	var vel := B3Proj.lob(from, aim, tt, "boulder")
	battle.spawn_proj("boulder", from, vel, self, B3Defs.weapon("boulder"))
	battle.snd("swing", from, 0.8)
	battle.snd("growl", position, 0.5)


## Robot laser: a fat glowing beam instead of a thin tracer.
func _fire_gun(w: Dictionary) -> void:
	if not w.has("beam"):
		super._fire_gun(w)
		return
	if target == null or not is_instance_valid(target):
		return
	var from := _muzzle_pos()
	var dir := (target.center() - from).normalized()
	var s := float(w.get("spread", 0.01))
	dir = (dir + Vector3(rng.randf_range(-s, s), rng.randf_range(-s, s) * 0.6, rng.randf_range(-s, s))).normalized()
	var to := from + dir * (float(w.range) * 1.4)
	var hit := shot_ray(from, to)
	var end := to
	if not hit.is_empty():
		end = hit.position
		battle.shot_hit(hit, w, dir, self)
	var tc: Color = w.get("tracer", Color(5, 1, 1))
	battle.fx.beam(from, end, tc, float(w.beam), 0.22)
	battle.fx.beam(from, end, Color(2.6, 1.6, 1.6), float(w.beam) * 0.3, 0.16)
	battle.fx.muzzle(from, dir, 1.4)
	battle.snd(String(w.snd), from, 0.85)
	if rig:
		rig.recoil = 1.0
	act = "shoot"
	act_t = 0.0
	act_len = 0.15
	cd = float(w.cd) * rng.randf_range(0.9, 1.15)


# ------------------------------------------------------------------- dragon
func _fly(dt: float) -> void:
	if kind != "dragon":
		super._fly(dt)
		return
	var to := _flat(target.position - position)
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	look = dir
	if act == "breath":
		_dive = false
		_alt = move_toward(_alt, 4.6, dt * 3.0)
		want = dir * clampf((d - 6.0) * 0.8, -speed * 0.4, speed * 0.4)
		return
	if _dive:
		# swoop down low for a bite (melee fighters can hit back now)
		_dive_t += dt
		var gh: float = battle.world.height_at(position.x, position.z)
		_alt = move_toward(_alt, maxf(0.7, target.position.y - gh + target.aim_y - 0.6), dt * 7.0)
		want = dir * speed * 1.15
		if d < radius + target.radius + 0.9 and absf(center().y - target.center().y) < 2.5:
			_dive = false
			_dive_cd = rng.randf_range(4.0, 7.0)
			_start_act("attack", 0.45, melee)
			act_fired = true
			target.hurt(30.0, (dir + Vector3.UP * 0.6).normalized(), 9.0, self)
			battle.snd("snap", position, 0.9)
			battle.snd("roar", position, 0.5)
		elif _dive_t > 3.5 or d > 18.0:
			_dive = false
			_dive_cd = rng.randf_range(2.0, 4.0)
		return
	_alt = move_toward(_alt, 6.4 + sin(battle.time * 0.7 + uid) * 0.6, dt * 2.0)
	if d > 14.0:
		want = dir * speed
	else:
		var side := Vector3(-dir.z, 0, dir.x) * _orbit
		want = side * speed * 0.75 + dir * clampf((d - 7.5) * 0.9, -speed, speed)
		look = (dir * 1.5 + side).normalized()
		if rng.randf() < dt * 0.08:
			_orbit = -_orbit
	if cd <= 0.0 and act == "" and d < 13.0 and d > 3.0:
		_start_breath()
	elif act == "" and cd > 1.0 and _dive_cd <= 0.0 and d < 14.0:
		_dive = true
		_dive_t = 0.0
		battle.snd("screech", position, 0.5, 0.6)
	want += sep * speed * 0.5


func _start_breath() -> void:
	_start_act("breath", float(wpn.get("len", 1.8)), wpn)
	cd = float(wpn.cd) * rng.randf_range(0.9, 1.2)
	_lit = false
	_tick = 0.0
	_fx_t = 0.0
	_bdir = (forward() + Vector3.DOWN * 0.6).normalized()
	if target and is_instance_valid(target):
		_bdir = (target.center() - _muzzle_pos()).normalized()
	battle.snd("roar", position, 0.8)
	battle.snd("flame", position, 1.0)


func _breath(dt: float, k: float) -> void:
	var mouth := _muzzle_pos()
	var aim := mouth + _bdir * 8.0
	if target and is_instance_valid(target) and not target.down and not target.dead:
		aim = target.center()
	elif player and ctl:
		aim = ctl.aim + Vector3(0, 0.5, 0)
	var to := aim - mouth
	if to.length() > 0.1:
		_bdir = _bdir.slerp(to.normalized(), minf(1.0, dt * 4.0)).normalized()
	if k < 0.08 or k > 0.92:
		return
	var sz := size * 0.32
	_fx_t -= dt
	while _fx_t <= 0.0:
		_fx_t += 0.022
		var spread := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * 0.1
		battle.fx.breath(mouth + _bdir * 0.3, (_bdir + spread).normalized() * rng.randf_range(16.0, 20.0), rng.randf_range(1.1, 1.6) * sz, 0.6)
	_tick -= dt
	if _tick > 0.0:
		return
	_tick = 0.15
	var reach := float(wpn.range)
	if rng.randf() < 0.5:
		battle.fx.light(mouth + _bdir * 4.0, 9.0, 3.0, 0.2)
	for u: B3Unit in battle.units.duplicate():
		if u == self or u.dead or not is_instance_valid(u) or not is_enemy(u):
			continue
		var rel := u.center() - mouth
		var dist := rel.length()
		if dist > reach + u.radius or dist < 0.01:
			continue
		var cone := 0.9 - clampf(u.radius / dist, 0.0, 0.3)
		if rel.dot(_bdir) / dist < cone:
			continue
		u.hurt(float(wpn.dmg), (_flat(rel).normalized() + Vector3.UP * 0.3).normalized(), 0.6, self, "fire")
		if is_instance_valid(u) and not u.dead and not B3Defs.is_vehicle(u.kind) and u.kind != "dragon":
			u.burn_t = maxf(u.burn_t, 2.0)
	for p: B3Prop in battle.props.duplicate():
		if not is_instance_valid(p):
			continue
		var rel2 := p.global_position - mouth
		var d2 := rel2.length()
		if d2 < reach and rel2.dot(_bdir) / maxf(d2, 0.01) > 0.9:
			p.damage(float(wpn.dmg) * 0.6)
	if not _lit and k > 0.35:
		var hit: Dictionary = battle.raycast(mouth, mouth + _bdir * reach * 1.25, B3Defs.L_TERRAIN | B3Defs.L_STRUCT)
		if not hit.is_empty():
			_lit = true
			var fires := 0
			for h in battle.hazards:
				if h.kind == "fire":
					fires += 1
			if fires < 10:
				var hp_: Vector3 = hit.position
				battle.spawn_hazard("fire", hp_, 2.2, 6.0)


# --------------------------------------------------------------- feedback
func hurt(dmg: float, dir: Vector3, knock: float, by: B3Unit = null, how := "hit") -> void:
	if kind == "robot" and not dead and not down and (how == "shot" or how == "hit") and rng.randf() < 0.35:
		battle.snd("metal_hit", position, 0.45)
		battle.fx.sparks(center(), 4)
	super.hurt(dmg, dir, knock, by, how)


func _process(dt: float) -> void:
	super._process(dt)
	if rig == null or dead:
		return
	match kind:
		"robot":
			if _spd > 0.5 and _grounded:
				var st := int(floor(rig.phase / PI))
				if st != _step:
					_step = st
					battle.snd("clink", position, 0.22, 0.55)
		"dragon":
			var fl := int(floor(rig.wing_flap / TAU))
			if fl != _flap:
				_flap = fl
				battle.snd("whoosh", position, 0.25, 0.6)
