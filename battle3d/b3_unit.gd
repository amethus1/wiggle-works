class_name B3Unit
extends RigidBody3D
## One fighter: soldier, animal or dinosaur. While standing it is a single
## upright physics body (rotation locked) steered by a small brain; its model
## (B3Rig) is animated by code. A big hit turns it into a B3Ragdoll; if it
## still has health it climbs back up once the ragdoll stops tumbling.

static var _pmat: PhysicsMaterial = null
static var _next_uid := 0

const MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY
const LAUNCH := 6.5       # knock speed (after stability) that turns a unit into a ragdoll

var battle = null
var kind := ""
var def: Dictionary = {}
var wpn: Dictionary = {}
var melee: Dictionary = {}
var act_w: Dictionary = {}
var team := "red"
var pers := "attack"
var pers_choice := "auto"
var hp := 100.0
var max_hp := 100.0
var speed := 4.0
var armor := 0.0
var size := 1.0
var radius := 0.3
var tall := 1.9
var aim_y := 1.2
var stab := 1.0
var flying := false
var heals := false
var rig: B3Rig = null
var disc: MeshInstance3D = null
var bar: MeshInstance3D = null
var laser: MeshInstance3D = null
var home := Vector3.ZERO
var target: B3Unit = null
var ally: B3Unit = null
var down := false
var dead := false
var ragdoll: B3Ragdoll = null
var down_t := 0.0
var facing := 0.0
var want := Vector3.ZERO
var look := Vector3.ZERO
var sep := Vector3.ZERO
var think_t := 0.0
var cd := 0.0
var act := ""
var act_t := 0.0
var act_len := 0.0
var act_fired := false
var burst := 0
var stuck_t := 0.0
var side_t := 0.0
var side_dir := Vector3.ZERO
var wander_t := 0.0
var wander_to := Vector3.ZERO
var fleeing := false
var hurt_t := 99.0
var burn_t := 0.0
var stun_t := 0.0
var charge_t := 0.0
var charge_cd := 1.0
var charge_dir := Vector3.ZERO
var charge_hit := {}
var voice_t := 0.0
var cheer := false
var uid := 0
var kills := 0
var held := false
var player := false              # steered by a person (see B3Player); `ctl` holds their controls
var ctl: B3Ctl = null
var size_mult := 1.0             # Toy Box size (tiny .. huge); set before setup()
var rng := RandomNumberGenerator.new()
var _hz_t := 0.0
var _spd := 0.0
var _grounded := true
var _swoop := false
var _alt := 6.0
var _cheer_t := 0.0
var _heal_fx := 0.0
var _burn_fx := 0.0
var _bar_hp := -1.0
var _turn := 9.0


static func unit_pmat() -> PhysicsMaterial:
	if _pmat == null:
		_pmat = PhysicsMaterial.new()
		_pmat.friction = 0.0
		_pmat.bounce = 0.0
	return _pmat


func setup(b, k: String, t: String, p: String, seed_: int) -> void:
	battle = b
	kind = k
	team = t
	rng.seed = seed_
	_next_uid += 1
	uid = _next_uid
	def = B3Defs.unit_def(k)
	wpn = B3Defs.weapon(String(def.weapon))
	if String(wpn.type) == "melee":
		melee = wpn
	else:
		melee = B3Defs.weapon("bash" if String(def.body) == "human" else "bite")
	if bool(def.get("bayonet", false)):
		melee = B3Defs.weapon("bayonet")
	act_w = wpn
	max_hp = float(def.hp)
	hp = max_hp
	speed = float(def.speed) * rng.randf_range(0.93, 1.07)
	armor = float(def.armor)
	size = float(def.size)
	stab = float(def.stab)
	flying = bool(def.get("flying", false))
	heals = bool(def.get("heals", false))
	set_personality(p)
	mass = float(def.mass)
	if size_mult != 1.0:
		# bigger fighters are tougher, heavier and harder to knock over
		size *= size_mult
		max_hp *= size_mult * size_mult
		hp = max_hp
		mass *= size_mult * size_mult * size_mult
		stab *= size_mult
		speed *= clampf(sqrt(size_mult), 0.75, 1.35)
	lock_rotation = true
	can_sleep = false
	physics_material_override = unit_pmat()
	collision_layer = B3Defs.L_UNIT
	collision_mask = MASK
	gravity_scale = 0.0 if flying else 1.6
	_make_rig()
	_turn = clampf(11.0 / sqrt(maxf(1.0, radius * 2.5)), 2.5, 11.0)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = maxf(tall * (0.55 if flying else 1.0), radius * 2.0 + 0.02)
	cs.shape = cap
	cs.position.y = cap.height * 0.5 + 0.02
	add_child(cs)
	disc = MeshInstance3D.new()
	disc.mesh = B3Mats.cyl(1.0, 1.0, 0.02, 20)
	disc.material_override = B3Mats.flat(Color(B3Defs.team_col(team), 0.42))
	disc.scale = Vector3(radius * 1.35 + 0.1, 1.0, radius * 1.35 + 0.1)
	disc.position.y = 0.05
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(disc)
	bar = MeshInstance3D.new()
	bar.mesh = B3Mats.quad(Vector2(0.9, 0.13))
	bar.material_override = B3Mats.shader_mat("hpbar")
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bar.position.y = tall + 0.35
	bar.scale = Vector3.ONE * clampf(sqrt(size * radius * 3.0), 1.0, 2.2)
	bar.visible = false
	bar.set_instance_shader_parameter("team", B3Defs.team_col(team))
	add_child(bar)
	think_t = rng.randf() * 0.3
	_alt = rng.randf_range(5.5, 7.5)
	voice_t = rng.randf_range(0.0, 2.0)


func _make_rig() -> void:
	rig = B3Rig.new()
	rig.size_mult = size_mult
	rig.build(kind, team, rng)
	add_child(rig)
	rig.rotation.y = facing
	radius = rig.radius
	tall = rig.height
	aim_y = rig.reach_y


func set_personality(p: String) -> void:
	pers_choice = p
	pers = String(def.pers) if p == "auto" or p == "" else p
	fleeing = false
	target = null


func set_team(t: String) -> void:
	if t == team or dead:
		return
	team = t
	target = null
	disc.material_override = B3Mats.flat(Color(B3Defs.team_col(team), 0.42))
	bar.set_instance_shader_parameter("team", B3Defs.team_col(team))
	if rig and not down:
		rig.queue_free()
		_make_rig()


func center() -> Vector3:
	if down and ragdoll and is_instance_valid(ragdoll):
		return ragdoll.center()
	return position + Vector3(0, aim_y, 0)


func forward() -> Vector3:
	return Vector3(sin(facing), 0, cos(facing))


## Where the first-person camera sits while someone plays this fighter: at
## its eyes, looking where the mouse points.
func eye_xform(c: B3Ctl) -> Transform3D:
	var p := get_global_transform_interpolated().origin
	if down and ragdoll and is_instance_valid(ragdoll):
		p = ragdoll.center() + Vector3(0, 0.4, 0)
	else:
		p += Vector3(0, tall * 0.9, 0) + forward() * radius * 0.6
	return Transform3D(Basis.from_euler(Vector3(c.look_pitch, c.look_yaw + PI, 0.0)), p)


func is_enemy(u: B3Unit) -> bool:
	if u.team != team:
		return true
	if team == "wild":
		return u.kind != kind
	return false


# ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if dt <= 0.0 or dead:
		return
	if down:
		_down_tick(dt)
		return
	hurt_t += dt
	cd -= dt
	voice_t -= dt
	stun_t -= dt
	charge_cd -= dt
	var p := position
	if p.y < -20.0 or absf(p.x) > B3Defs.BOUNDS + 10.0 or absf(p.z) > B3Defs.BOUNDS + 10.0:
		battle.remove_unit(self, false)
		return
	_hazards(dt)
	if dead or down:
		return
	if burn_t > 0.0:
		burn_t -= dt
		hp -= dt * 7.0
		_burn_fx -= dt
		if _burn_fx <= 0.0:
			_burn_fx = 0.12
			battle.fx.flame(p + Vector3(rng.randf_range(-0.2, 0.2), aim_y + rng.randf_range(-0.3, 0.4), rng.randf_range(-0.2, 0.2)))
		if hp <= 0.0:
			_ko(Vector3.UP * 2.0, null)
			return
	if act != "":
		act_t += dt
		_act_update()
	if held:
		want = Vector3.ZERO
	elif player:
		B3Player.control(self, dt)
	elif battle.fighting:
		think_t -= dt
		if think_t <= 0.0:
			think_t = battle.think_period + rng.randf() * 0.12
			_think()
		_decide(dt)
	else:
		want = Vector3.ZERO
		look = Vector3.ZERO
	_move(dt)


func _move(dt: float) -> void:
	var v := linear_velocity
	_grounded = flying or absf(v.y) < 0.9 or position.y - battle.world.height_at(position.x, position.z) < 0.2
	var ctrl := 1.0 if _grounded else 0.12
	if stun_t > 0.0:
		ctrl *= 0.12
	var accel := 24.0 if not flying else 12.0
	if charge_t > 0.0:
		accel = 30.0
	var hv := Vector3(v.x, 0.0, v.z)
	hv = hv.move_toward(want * battle.r_speed, accel * ctrl * dt)
	var vy := v.y
	if flying:
		var gh: float = battle.world.height_at(position.x, position.z)
		vy = lerpf(vy, clampf((gh + _alt - position.y) * 2.2, -10.0, 7.0), minf(1.0, dt * 4.0))
	linear_velocity = Vector3(hv.x, vy, hv.z)
	_spd = hv.length()
	var f := look
	if f == Vector3.ZERO and want.length_squared() > 0.3:
		f = want
	if f != Vector3.ZERO:
		facing = rotate_toward(facing, atan2(f.x, f.z), dt * _turn)
	if rig:
		rig.rotation.y = facing


func _is_grounded_now() -> bool:
	return _grounded


# -------------------------------------------------------------------- brain
func _think() -> void:
	var my := position
	var best: B3Unit = null
	var bd := 1e18
	var hurt_u: B3Unit = null
	var hd := 1e18
	var sx := 0.0
	var sz := 0.0
	var guard := pers == "defend"
	var guard_r := guard_radius()
	var melee_only := String(wpn.type) == "melee" or pers == "berserk"
	for u: B3Unit in battle.units:
		if u == self or u.down:
			continue
		var dx := u.position.x - my.x
		var dz := u.position.z - my.z
		var d2 := dx * dx + dz * dz
		var rr := radius + u.radius + 0.45
		if d2 < rr * rr and d2 > 0.0001:
			var d := sqrt(d2)
			var push := (rr - d) / rr
			sx -= dx / d * push
			sz -= dz / d * push
		if is_enemy(u):
			if guard:
				var hx := u.position.x - home.x
				var hz := u.position.z - home.z
				if hx * hx + hz * hz > guard_r * guard_r:
					continue
			var score := d2
			if u == target:
				score *= 0.55
			if u.flying and melee_only and not flying:
				score = score * 4.0 + 400.0
			if score < bd:
				bd = score
				best = u
		elif heals and u.team == team and u.hp < u.max_hp * 0.92:
			if d2 < hd:
				hd = d2
				hurt_u = u
	sep = Vector3(sx, 0.0, sz)
	if best != target:
		target = best
		if target and voice_t <= 0.0 and pers != "peaceful":
			_voice()
	ally = hurt_u if hd < 22.0 * 22.0 else null


func guard_radius() -> float:
	var r := 9.0
	if String(wpn.type) != "melee":
		r = float(wpn.range) + 2.0
	return r


func _voice() -> void:
	voice_t = rng.randf_range(6.0, 11.0)
	var v := String(def.get("voice", ""))
	if v == "":
		return
	if kind == "trex" and act == "" and _grounded:
		_start_act("roar", 1.3, wpn)
		battle.shake(0.25, position)
		for u: B3Unit in battle.units:
			if u.pers == "coward" and is_enemy(u) and u.position.distance_to(position) < 14.0:
				u.fleeing = true
	battle.snd(v, position, 1.0 if size > 1.5 or kind == "trex" else 0.7)


func _decide(dt: float) -> void:
	want = Vector3.ZERO
	look = Vector3.ZERO
	if cheer:
		_cheer(dt)
		return
	if charge_t > 0.0:
		_charging(dt)
		return
	if act == "heal" and not (heals and ally and is_instance_valid(ally) and not ally.down and not ally.dead):
		act = ""
	if act == "roar" or act == "throw" or act == "aim" or act == "bow":
		if target and is_instance_valid(target):
			look = _flat(target.position - position).normalized()
		return
	if pers == "coward" and hp < max_hp * 0.5:
		fleeing = true
	if burn_t > 0.0 and pers != "berserk":
		if wander_t <= 0.0 or wander_to == Vector3.ZERO:
			wander_to = position + Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8))
			wander_t = 0.6
		wander_t -= dt
		want = _flat(wander_to - position).normalized() * speed * 1.2
		_unstick(dt)
		return
	if pers == "peaceful":
		if hurt_t < 2.5 and target and is_instance_valid(target):
			_flee(dt)
		else:
			_wander(dt, 0.45)
		return
	if heals and ally and is_instance_valid(ally) and not ally.down and not fleeing:
		var threat := target != null and is_instance_valid(target) and position.distance_to(target.position) < 5.0
		if not threat:
			_heal(dt)
			return
	if fleeing:
		_flee(dt)
		return
	if target == null or not is_instance_valid(target) or target.down or target.dead:
		target = null
		if pers == "defend":
			_go_home()
		elif battle.enemies_left(self):
			_wander(dt, 0.25)
		return
	if flying:
		_fly(dt)
		return
	var w := melee if pers == "berserk" else wpn
	var to := _flat(target.position - position)
	var dist := to.length()
	var dir := to / maxf(dist, 0.001)
	if bool(def.get("bayonet", false)) and dist < radius + target.radius + 2.0:
		w = melee         # too close to shoot: stab with the bayonet
	var reach := _reach(w, target)
	var ranged := String(w.type) != "melee"
	look = dir
	var spd := speed * (1.4 if pers == "berserk" else 1.0)
	if not ranged and dist < 7.0 and String(def.body) == "rider" and _bayonet_wall(target):
		# horses shy away from a hedge of bayonets: ride round it instead
		var round_dir := Vector3(-dir.z, 0, dir.x) * (1.0 if uid % 2 == 0 else -1.0)
		want = _safe((round_dir + dir * (0.25 if dist > 5.0 else -0.6)).normalized() * spd * 0.8 + sep * speed * 0.9)
		look = Vector3.ZERO
		_unstick(dt)
		return
	if ranged and pers == "attack":
		# charge in, shooting on the way
		if dist > maxf(3.0, reach * 0.4):
			want = dir * spd
	elif ranged:
		var near := maxf(3.5, reach * 0.35)
		if dist > reach * 0.9:
			want = dir * spd
		elif dist < near and pers != "defend":
			want = -dir * spd * 0.75
		else:
			var side := Vector3(-dir.z, 0, dir.x)
			want = side * sin(battle.time * 0.7 + uid) * 0.6
	else:
		if dist > reach * 0.8:
			want = dir * spd
		if bool(def.get("charge", false)) and charge_cd <= 0.0 and dist > 5.0 and dist < 18.0 and _grounded and act == "" and not (String(def.body) == "rider" and _bayonet_wall(target)):
			_start_charge(dir)
			return
		if bool(def.get("pounce", false)) and cd <= 0.0 and dist > 2.5 and dist < 7.5 and _grounded and act == "":
			_pounce(dir)
			return
	if pers == "defend":
		var off := _flat(position - home)
		if off.length() > guard_radius() + 1.5 and dist > reach:
			_go_home()
			return
	want += sep * speed * 0.9
	want = _safe(want)
	_unstick(dt)
	if dist <= reach and cd <= 0.0 and act == "" and _facing_ok(dir) and _volley_ok(w):
		_attack(w)


## Horses won't charge into a steady line of bayonets (why squares worked):
## `u` has a bayonet and at least two friends with bayonets right beside it.
func _bayonet_wall(u: B3Unit) -> bool:
	if not bool(u.def.get("bayonet", false)):
		return false
	var n := 0
	for o: B3Unit in battle.units:
		if o != u and o.team == u.team and not o.down and bool(o.def.get("bayonet", false)) and o.position.distance_squared_to(u.position) < 6.25:
			n += 1
			if n >= 2:
				return true
	return false


## Muskets fire in volleys: everyone on a team who's loaded shoots in the same
## short window, every `volley` seconds.
func _volley_ok(w: Dictionary) -> bool:
	if not w.has("volley"):
		return true
	var period := float(w.volley)
	return fposmod(battle.time + float(absi(team.hash()) % 97) * 0.31, period) < 0.8


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


func _reach(w: Dictionary, u: B3Unit) -> float:
	var r := float(w.range)
	if String(w.type) == "melee":
		return radius + u.radius + r * size * 0.6
	return r


func _facing_ok(dir: Vector3) -> bool:
	return forward().dot(dir) > 0.75


func _go_home() -> void:
	var to := _flat(home - position)
	if to.length() > 1.2:
		want = to.normalized() * speed * 0.8
		want = _safe(want)
	else:
		look = Vector3.ZERO


func _wander(dt: float, f: float) -> void:
	wander_t -= dt
	if wander_t <= 0.0:
		wander_t = rng.randf_range(1.5, 4.0)
		if rng.randf() < 0.3:
			wander_to = position
		else:
			wander_to = home + Vector3(rng.randf_range(-6, 6), 0, rng.randf_range(-6, 6))
		if kind == "chicken" and rng.randf() < 0.35:
			wander_t = 0.8
			f = 1.3
			battle.snd("cluck", position, 0.5)
	var to := _flat(wander_to - position)
	if to.length() > 0.6:
		want = to.normalized() * speed * (f if kind != "chicken" else 0.8)
	want = _safe(want + sep * speed * 0.5)
	_unstick(dt)


func _flee(dt: float) -> void:
	var threat: B3Unit = target
	if threat == null or not is_instance_valid(threat):
		return
	var away := _flat(position - threat.position)
	var d := away.length()
	if d > 17.0:
		want = Vector3.ZERO
		look = -away.normalized()
		return
	want = away.normalized() * speed * 1.15
	want = _safe(want + sep * speed * 0.5)
	_unstick(dt)


func _heal(dt: float) -> void:
	var to := _flat(ally.position - position)
	var d := to.length()
	look = to.normalized()
	if d > 2.2:
		want = _safe(look * speed)
		_unstick(dt)
		if act == "heal":
			act = ""
		return
	if act == "":
		_start_act("heal", 0.5, wpn)
	ally.hp = minf(ally.max_hp, ally.hp + 24.0 * dt)
	ally.hurt_t = 0.0
	_heal_fx -= dt
	if _heal_fx <= 0.0:
		_heal_fx = 0.22
		battle.fx.heal(ally.position + Vector3(rng.randf_range(-0.3, 0.3), ally.aim_y + rng.randf_range(0.0, 0.6), rng.randf_range(-0.3, 0.3)))
		if rng.randf() < 0.15:
			battle.snd("heal", position, 0.5)


func _cheer(dt: float) -> void:
	_cheer_t -= dt
	if _cheer_t <= 0.0 and _grounded and not flying:
		linear_velocity.y = 4.0 + rng.randf() * 1.5
		_cheer_t = rng.randf_range(0.7, 1.6)


## Steer around lava/acid and (if not reckless) don't walk off high edges.
func _safe(w: Vector3) -> Vector3:
	if w == Vector3.ZERO or pers == "berserk" or flying:
		return w
	var n := w.normalized()
	for hz in battle.hazards:
		var h: B3Hazard = hz
		var ahead := position + n * (1.6 + radius)
		var dx := ahead.x - h.position.x
		var dz := ahead.z - h.position.z
		var r := h.radius + radius + 0.7
		if dx * dx + dz * dz < r * r:
			var out := _flat(position - h.position).normalized()
			if out == Vector3.ZERO:
				out = Vector3.RIGHT
			var tan := Vector3(-out.z, 0, out.x)
			if tan.dot(n) < 0.0:
				tan = -tan
			return (tan + out * 0.6).normalized() * w.length()
	# walk along the shore rather than into deep water (B3World)
	if not battle.world.waters.is_empty():
		var dry: Vector3 = battle.world.steer_dry(position, w, radius)
		if dry != w:
			return dry
	if pers != "attack" and _grounded:
		var gh: float = battle.world.height_at(position.x, position.z)
		if position.y - gh > 1.2:
			var ahead2 := position + n * (radius + 0.8)
			var sy: float = battle.surface_y(ahead2 + Vector3(0, 0.5, 0))
			if position.y - sy > 1.3:
				return Vector3.ZERO
	return w


func _unstick(dt: float) -> void:
	if want.length_squared() < 1.0:
		stuck_t = 0.0
		return
	if side_t > 0.0:
		side_t -= dt
		want = (want.normalized() * 0.35 + side_dir).normalized() * want.length()
		return
	if _spd < 0.45:
		stuck_t += dt
	else:
		stuck_t = maxf(0.0, stuck_t - dt)
	if stuck_t > 0.55:
		stuck_t = 0.0
		side_t = rng.randf_range(0.6, 1.1)
		var n := want.normalized()
		side_dir = Vector3(-n.z, 0, n.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		if _grounded and size < 1.6 and radius < 0.8:
			linear_velocity.y = 5.2


# ------------------------------------------------------------------ attacks
func _start_act(a: String, length: float, w: Dictionary) -> void:
	act = a
	act_t = 0.0
	act_len = length
	act_fired = false
	act_w = w


func _attack(w: Dictionary) -> void:
	var ty := String(w.type)
	var bers := pers == "berserk"
	match ty:
		"melee":
			_start_act("attack", clampf(float(w.cd) * 0.6, 0.25, 0.75), w)
			cd = float(w.cd) * (0.75 if bers else 1.0)
			if rig and rig.hold == "fists":
				rig.punch_side = 1 - rig.punch_side
			if float(w.dmg) >= 30.0:
				battle.snd("swing", position, 0.6)
		"gun":
			if w.has("aim"):
				_start_act("aim", float(w.aim), w)
				cd = float(w.cd)
				battle.snd("reload", position, 0.3)
				return
			_fire_gun(w)
		"proj":
			if String(w.proj) == "arrow":
				_start_act("bow", 0.5, w)
			else:
				_start_act("aim", 0.3, w)
			cd = float(w.cd)
		"throw":
			_start_act("throw", 0.75, w)
			cd = float(w.cd)


func _act_update() -> void:
	var k := act_t / maxf(act_len, 0.01)
	match act:
		"attack":
			if not act_fired and k >= 0.5:
				act_fired = true
				_melee_hit(act_w)
		"aim":
			if String(act_w.type) == "gun":
				_update_laser()
			if k >= 1.0:
				_hide_laser()
				act = ""
				if target and is_instance_valid(target) and not target.down:
					if String(act_w.type) == "gun":
						_fire_gun(act_w)
					else:
						_shoot_proj(act_w)
				return
		"bow":
			if k >= 1.0:
				act = ""
				if target and is_instance_valid(target) and not target.down:
					_shoot_proj(act_w)
				return
		"throw":
			if not act_fired and k >= 0.62:
				act_fired = true
				_throw(act_w)
		"pounce":
			if not act_fired and target and is_instance_valid(target) and not target.down:
				if center().distance_to(target.center()) < radius + target.radius + 1.0:
					act_fired = true
					target.hurt(float(wpn.dmg) * 1.5, (_flat(target.position - position).normalized() + Vector3.UP * 0.5).normalized(), 7.0, self)
					battle.snd("slash", position, 0.8)
		"heal":
			if k >= 1.0:
				act_t = 0.0
			return
	if k >= 1.0:
		act = ""


func _melee_hit(w: Dictionary) -> void:
	var dmg := float(w.dmg)
	var knock := float(w.knock)
	battle.snd(String(w.snd), position, 0.8 if size < 1.5 else 1.0)
	if w.has("aoe"):
		var fwd := forward()
		var reach := float(w.range) * (size if String(def.body) == "human" else 1.0)
		var c := position + fwd * (reach * 0.6 + radius)
		var r := float(w.aoe) * (size if String(def.body) == "human" else 1.0)
		if String(w.anim) == "tail":
			c = position
			r = float(w.aoe) + radius
		for u: B3Unit in battle.units.duplicate():
			if u == self or u.down or not is_enemy(u):
				continue
			var d := _flat(u.position - c).length()
			if d < r + u.radius:
				var dir := (_flat(u.position - position).normalized() + Vector3.UP * 0.7).normalized()
				u.hurt(dmg * (1.0 - 0.35 * d / r), dir, knock * (1.0 - 0.3 * d / r), self)
		battle.blast_props(c, r, knock * 0.5)
		battle.fx.dust(c, r)
		battle.shake(float(w.get("shake", 0.1)), c)
		if String(w.anim) == "stomp" or String(w.anim) == "slam":
			battle.snd("stomp", c, 1.0)
		return
	if target == null or not is_instance_valid(target) or target.down:
		return
	var d2 := _flat(target.position - position).length()
	if d2 > _reach(w, target) * 1.35:
		return
	var up := 0.95 if w.has("toss") else 0.35
	var dir2 := (_flat(target.position - position).normalized() + Vector3.UP * up).normalized()
	target.hurt(dmg, dir2, knock * (1.5 if w.has("toss") else 1.0), self)
	if w.has("shake"):
		battle.shake(float(w.shake), position)


func _muzzle_pos() -> Vector3:
	if rig and rig.muzzle and is_instance_valid(rig.muzzle):
		return rig.muzzle.global_position
	return position + Vector3(0, aim_y + 0.15, 0) + forward() * (radius + 0.3)


func _fire_gun(w: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := _muzzle_pos()
	var aim := target.center()
	var dir := (aim - from).normalized()
	var s := float(w.get("spread", 0.03))
	dir = (dir + Vector3(rng.randf_range(-s, s), rng.randf_range(-s, s) * 0.6, rng.randf_range(-s, s))).normalized()
	var to := from + dir * (float(w.range) * 1.4)
	var hit: Dictionary = battle.raycast(from, to, B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY, [get_rid()])
	if w.has("volley"):
		# musket lines fire past their own front rank (it kneels)
		var skip: Array = [get_rid()]
		while skip.size() < 6 and not hit.is_empty() and hit.collider is B3Unit and not is_enemy(hit.collider):
			skip.append((hit.collider as B3Unit).get_rid())
			hit = battle.raycast(from, to, B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY, skip)
	var end := to
	if not hit.is_empty():
		end = hit.position
		battle.shot_hit(hit, w, dir, self)
	var tc: Color = w.get("tracer", Color(4, 3, 1))
	battle.fx.tracer(from, end, tc, 0.06 if String(def.weapon) != "sniper" else 0.12)
	battle.fx.muzzle(from, dir)
	if w.has("smoke"):
		musket_smoke(from, dir)
	battle.snd(String(w.snd), from, 0.55 if String(w.snd) == "gun_mg" else 0.75)
	if rig:
		rig.recoil = 1.0
	act = "shoot"
	act_t = 0.0
	act_len = 0.12
	if w.has("burst"):
		burst += 1
		if burst >= int(w.burst):
			burst = 0
			cd = float(w.reload)
		else:
			cd = float(w.cd)
	else:
		cd = float(w.cd) * rng.randf_range(0.9, 1.15)


## A musket's big flash and puff of white smoke.
func musket_smoke(from: Vector3, dir: Vector3) -> void:
	battle.fx.muzzle(from, dir, 2.2)
	var at := from + dir * 0.5
	if rng.randf() < 0.5:
		battle.fx.steam(at, 1.1)
	else:
		battle.fx.poof(at, 0.9)


func _lead(from: Vector3, speed_: float) -> Vector3:
	var aim := target.center()
	var t := from.distance_to(aim) / maxf(speed_, 1.0)
	return aim + Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * t * 0.7


func _shoot_proj(w: Dictionary) -> void:
	var from := _muzzle_pos()
	var sp := float(w.speed)
	var aim := _lead(from, sp)
	var kind_s := String(w.proj)
	var vel: Vector3
	if kind_s == "arrow":
		var flat := _flat(aim - from)
		var tt := maxf(flat.length() / sp, 0.15)
		vel = flat / tt + Vector3(0, (aim.y - from.y + 0.5 * 9.8 * tt * tt) / tt, 0)
		vel += Vector3(rng.randf_range(-0.5, 0.5), rng.randf_range(-0.3, 0.3), rng.randf_range(-0.5, 0.5))
	else:
		aim.y = target.position.y + 0.3
		vel = (aim - from).normalized() * sp
	battle.spawn_proj(kind_s, from, vel, self, w)
	battle.snd(String(w.snd), from, 0.8)
	if kind_s == "rocket":
		battle.fx.muzzle(from, vel.normalized(), 1.8)
		if rig:
			rig.recoil = 1.0


func _throw(w: Dictionary) -> void:
	if target == null or not is_instance_valid(target):
		return
	var from := position + Vector3(0, aim_y + 0.5, 0) + forward() * 0.3
	var aim := target.position + Vector3(target.linear_velocity.x, 0, target.linear_velocity.z) * 0.6
	var flat := _flat(aim - from)
	var tt := clampf(flat.length() / 9.0, 0.6, 1.5)
	var vel := flat / tt + Vector3(0, (aim.y - from.y + 0.5 * 9.8 * tt * tt) / tt, 0)
	var p = battle.spawn_proj("grenade", from, vel, self, w)
	p.fuse = tt + 0.5
	battle.snd("swing", from, 0.5)


func _update_laser() -> void:
	if target == null or not is_instance_valid(target):
		return
	if laser == null:
		laser = MeshInstance3D.new()
		laser.mesh = B3Mats.box(Vector3(0.025, 0.025, 1.0))
		laser.material_override = B3Mats.glow(Color(1.0, 0.15, 0.1, 0.8), 3.0)
		laser.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		battle.fx.add_child(laser)
	var a := _muzzle_pos()
	var b := target.center()
	var l := a.distance_to(b)
	if l < 0.1:
		return
	laser.visible = true
	laser.global_transform = Transform3D(Basis.looking_at((b - a) / l, Vector3.UP).scaled(Vector3(1, 1, l)), (a + b) * 0.5)


func _hide_laser() -> void:
	if laser:
		laser.visible = false


func _start_charge(dir: Vector3) -> void:
	charge_t = 2.2
	charge_dir = dir
	charge_hit.clear()
	_start_act("charge", 2.2, wpn)
	battle.snd(String(def.get("voice", "charge")), position, 0.9)
	battle.snd("charge", position, 0.8)


func _charging(dt: float) -> void:
	charge_t -= dt
	want = charge_dir * speed * 2.6
	look = charge_dir
	var w := wpn
	for u: B3Unit in battle.units.duplicate():
		if u == self or u.down or not is_enemy(u) or charge_hit.has(u.uid):
			continue
		var d := _flat(u.position - position).length()
		if d < radius + u.radius + 0.5:
			charge_hit[u.uid] = true
			var dir := (charge_dir + Vector3.UP * 0.8).normalized()
			u.hurt(float(w.get("charge_dmg", 30.0)), dir, float(w.get("charge_knock", 15.0)), self)
			battle.shake(0.15, position)
			battle.snd("thud", position, 0.9)
	battle.blast_props(position + charge_dir * radius, radius + 0.5, 6.0)
	if charge_t <= 0.0 or (charge_t < 1.8 and _spd < 1.0):
		charge_t = 0.0
		act = ""
		charge_cd = rng.randf_range(3.5, 5.5)
		stun_t = 0.25


func _pounce(dir: Vector3) -> void:
	linear_velocity = dir * 10.5 + Vector3.UP * 4.5
	_start_act("pounce", 0.7, wpn)
	cd = 1.2
	stun_t = 0.5
	battle.snd("screech", position, 0.6)


func _fly(dt: float) -> void:
	var to := _flat(target.position - position)
	var d := to.length()
	var dir := to / maxf(d, 0.001)
	look = dir
	var gh: float = battle.world.height_at(position.x, position.z)
	if cd <= 0.0 and d < 14.0 and act == "":
		_swoop = true
	if _swoop:
		_alt = maxf(0.6, target.position.y - gh + target.aim_y - 0.2)
		want = dir * speed * 1.25
		if center().distance_to(target.center()) < radius + target.radius + 0.8:
			_swoop = false
			_start_act("attack", 0.4, wpn)
			act_fired = true
			var hdir := (dir + Vector3.UP * 0.6).normalized()
			target.hurt(float(wpn.dmg), hdir, float(wpn.knock), self)
			battle.snd("screech", position, 0.7)
			cd = float(wpn.cd)
			_alt = rng.randf_range(5.5, 7.5)
		elif d > 16.0:
			_swoop = false
			_alt = rng.randf_range(5.5, 7.5)
	else:
		_alt = rng.randf_range(5.5, 7.5) if _alt < 3.0 else _alt
		if d < 9.0:
			want = Vector3(-dir.z, 0, dir.x) * speed * 0.9 + dir * 1.0
		else:
			want = dir * speed
	want += sep * speed * 0.5


# --------------------------------------------------------------- damage etc
## dir: push direction (unit vector). knock: push speed for a normal unit.
func hurt(dmg: float, dir: Vector3, knock: float, by: B3Unit = null, how := "hit") -> void:
	if dead:
		return
	dmg /= battle.r_tough      # Battle Rules: toughness and knockback
	knock *= battle.r_knock
	if down:
		hp -= dmg * (1.0 - armor)
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.push(dir * knock / stab * 0.6)
		if hp <= 0.0:
			_die(by)
		return
	if def.has("dodge") and how != "blast" and how != "fire" and rng.randf() < float(def.dodge):
		battle.fx.poof(position + Vector3(0, 0.8, 0), 0.6)
		battle.snd("whoosh", position, 0.6)
		var side := Vector3(-dir.z, 0, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		linear_velocity += side * 6.0 + Vector3.UP * 2.0
		return
	var d := dmg * (1.0 - armor)
	if rig and rig.shield and how != "blast" and how != "fire":
		var from := _flat(-dir).normalized()
		if forward().dot(from) > 0.25:
			d *= 0.35
			knock *= 0.5
			battle.snd("clang", position, 0.7)
			battle.fx.sparks(position + Vector3(0, 1.0, 0) + forward() * 0.4, 6)
	hp -= d
	hurt_t = 0.0
	if rig:
		rig.flash()
	if d >= 1.0:
		battle.fx.number(position + Vector3(0, tall + 0.5, 0), d)
	if by and is_instance_valid(by) and by != self and is_enemy(by) and pers != "peaceful" and not by.down:
		if target == null or not is_instance_valid(target) or position.distance_squared_to(by.position) < position.distance_squared_to(target.position) * 0.5:
			target = by
	if pers == "coward" and hp < max_hp * 0.5 and not fleeing:
		fleeing = true
		battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.6)
	var kv := knock / stab
	if hp <= 0.0:
		if by and is_instance_valid(by):
			by.kills += 1
		_ko(dir * maxf(kv, 3.0) + Vector3.UP * 2.0, by)
		return
	if kv > LAUNCH:
		knock_down(dir * kv)
		if String(def.body) == "human" and rng.randf() < 0.6:
			battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.7)
	else:
		linear_velocity += dir * kv
		stun_t = maxf(stun_t, 0.1 + kv * 0.04)
		if String(def.body) == "human" and d > 8.0 and rng.randf() < 0.25:
			battle.snd("oof%d" % (rng.randi() % 3 + 1), position, 0.5)


func _ko(vel: Vector3, by: B3Unit) -> void:
	knock_down(vel)
	_die(by)


## Turns into a ragdoll flying off with `vel`.
func knock_down(vel: Vector3) -> void:
	if dead:
		return
	if down:
		if ragdoll and is_instance_valid(ragdoll):
			ragdoll.push(vel * 0.7)
		return
	if rig == null:
		return
	down = true
	down_t = 0.0
	act = ""
	charge_t = 0.0
	_swoop = false
	_hide_laser()
	var rd := B3Ragdoll.new()
	rd.battle = battle
	rd.unit = self
	battle.ragdoll_root.add_child(rd)
	var inherit := linear_velocity * 0.6
	rd.build(rig, vel + inherit, 3.0 + vel.length() * 0.4, rng)
	rig.queue_free()
	rig = null
	ragdoll = rd
	battle.ragdolls.append(rd)
	freeze = true
	collision_layer = 0
	collision_mask = 0
	disc.visible = false
	bar.visible = false
	rd.show_stars(99.0)
	if vel.length() > 12.0:
		battle.snd("whoosh", position, 0.7)


func _die(by: B3Unit = null) -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	_hide_laser()
	if ragdoll and is_instance_valid(ragdoll):
		ragdoll.set_dead()
	battle.on_unit_ko(self, by)
	if laser:
		laser.queue_free()
	queue_free()


func _down_tick(dt: float) -> void:
	if ragdoll == null or not is_instance_valid(ragdoll):
		battle.remove_unit(self, false)
		return
	down_t += dt
	var c := ragdoll.center()
	global_position = c
	if c.y < -20.0 or absf(c.x) > B3Defs.BOUNDS + 10.0 or absf(c.z) > B3Defs.BOUNDS + 10.0:
		_die(null)
		return
	if ragdoll.sinking > 0.0:
		if ragdoll.sinking > 0.6:
			_die(null)
		return
	if held:
		down_t = 0.0
		return
	if down_t > 2.0 and ragdoll.is_settled():
		get_up()


func get_up() -> void:
	if not down or dead or ragdoll == null:
		return
	var c := ragdoll.center()
	var gy: float = battle.surface_y(c + Vector3(0, 1.0, 0))
	freeze = false
	collision_layer = B3Defs.L_UNIT
	collision_mask = MASK
	global_position = Vector3(c.x, gy + 0.08, c.z)
	linear_velocity = Vector3(0, 3.0, 0)
	_make_rig()
	battle.ragdolls.erase(ragdoll)
	ragdoll.queue_free()
	ragdoll = null
	down = false
	stun_t = 0.35
	disc.visible = true
	reset_physics_interpolation()
	battle.snd("boing", position, 0.5, 1.2)
	battle.fx.dust(position, 0.8)


func _hazards(dt: float) -> void:
	_hz_t -= dt
	if _hz_t > 0.0:
		return
	_hz_t = 0.1
	var h: B3Hazard = battle.hazard_at(position, 0.0)
	if h == null:
		return
	if flying and position.y > h.surface + 1.0:
		return
	hp -= h.dps * 0.1
	hurt_t = 0.0
	if rig:
		rig.flash()
	if h.kind == "lava" or h.kind == "fire":
		burn_t = 2.5
	if h.kind != "fire" and _grounded and rng.randf() < 0.5:
		linear_velocity.y = 3.5
	if rng.randf() < 0.3:
		battle.snd("sizzle" if h.kind != "acid" else "fizz", position, 0.6)
	if hp <= 0.0:
		_ko(Vector3.UP * 2.5, null)
		if h.kind != "fire" and ragdoll:
			pass


func _process(dt: float) -> void:
	if rig == null:
		return
	var mood := ""
	if cheer:
		mood = "cheer"
	elif burn_t > 0.0:
		mood = "flail"
	elif fleeing and _spd < 0.6 and battle.fighting:
		mood = "cower"
	var aiming: bool = battle.fighting and target != null and String(wpn.type) != "melee" and pers != "berserk" and not fleeing and not cheer
	var a := act
	if _swoop:
		a = "swoop"
	rig.animate(dt, _spd, a, act_t / maxf(act_len, 0.01), aiming, mood)
	if hurt_t < 3.0 and hp < max_hp and not battle.cam.too_close(position):
		bar.visible = true
		var f := clampf(hp / max_hp, 0.0, 1.0)
		if absf(f - _bar_hp) > 0.004:
			_bar_hp = f
			bar.set_instance_shader_parameter("hp", f)
	elif bar.visible:
		bar.visible = false
