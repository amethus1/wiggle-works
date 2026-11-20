class_name B3Player
## Playing as a fighter or vehicle in 3D Battle. Each played unit has a
## B3Ctl (its controls): `me` is this computer's, friends' come over the
## network. The unit's _physics_process calls control() instead of its AI.
##  - Overhead view: WASD moves (turned to match the camera), the mouse aims
##    at the ground, click (or hold) to attack, Space to jump.
##  - First person (👀, V key): the mouse looks around, W walks where you're
##    looking, the crosshair is where shots go. Knocked out? You jump into the
##    nearest teammate and keep going (B3Tools.player_lost).
## Vehicles do their own driving/flying from the same controls (player_drive).

static var me := B3Ctl.new()        # this computer's controls
static var unit: B3Unit = null      # the fighter or vehicle this computer is playing
## True from start() until stop(), even after `unit` is knocked out and freed
## (a freed node reads as null, so `unit != null` can't tell "never played"
## from "just got knocked out").
static var playing := false
static var what := ""               # its name, for the "you got knocked out" message
static var was_vehicle := false
static var kind := ""
static var team := ""               # whose side you were on (first person jumps to a teammate)
static var last_pos := Vector3.ZERO # where you were (the nearest teammate takes over)

const MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY


static func active() -> bool:
	return unit != null and is_instance_valid(unit) and not unit.dead


## This computer takes `u`.
static func start(u: B3Unit) -> void:
	stop()
	if u == null or not is_instance_valid(u) or u.dead:
		return
	unit = u
	playing = true
	what = String(u.def.name)
	was_vehicle = u is B3Vehicle
	kind = u.kind
	team = u.team
	last_pos = u.global_position
	me.clear_buttons()
	me.peer = 0
	me.look_yaw = u.facing
	me.look_pitch = 0.0
	attach(u, me)


static func stop() -> void:
	if unit != null and is_instance_valid(unit) and unit.ctl == me:
		detach(unit)
	unit = null
	playing = false
	me.clear_buttons()


## What to say when the fighter or vehicle you were playing is gone.
static func lost_msg() -> String:
	if was_vehicle:
		return "💥 Your %s got wrecked! Pick something else to play." % what
	return "💫 You got knocked out! Pick another fighter to play."


## Hands `u` to the controls `c` (this computer's or a friend's).
static func attach(u: B3Unit, c: B3Ctl) -> void:
	if u.ctl != null and u.ctl != c and u == unit:
		unit = null
	u.ctl = c
	u.player = true
	u.target = null
	u.fleeing = false
	c.aim = u.position + u.forward() * 3.0
	if u.has_method("on_player_start"):
		u.call("on_player_start", c)


## Gives `u` back to the computer.
static func detach(u: B3Unit) -> void:
	if not is_instance_valid(u):
		return
	if u.has_method("on_player_stop"):
		u.call("on_player_stop")
	u.ctl = null
	u.player = false
	u.target = null


## Called from B3Unit._physics_process while it's being played.
static func control(u: B3Unit, dt: float) -> void:
	var c := u.ctl
	if c == null:
		u.player = false
		return
	if u.has_method("player_drive"):
		u.call("player_drive", c, dt)      # vehicles: drive, fly, turn the turret, shoot
		return
	if c.fp:
		u.facing = c.look_yaw              # you turn exactly with the mouse
		u.look = Vector3(sin(c.look_yaw), 0, cos(c.look_yaw))
	else:
		var to := u._flat(c.aim - u.position)
		var dist := to.length()
		u.look = to / dist if dist > 0.4 else Vector3.ZERO
	u.want = c.move * u.speed * 1.1
	if u.charge_t > 0.0:
		u.charge_t = 0.0
	if c.jump:
		c.jump = false
		if u._grounded and not u.flying and u.stun_t <= 0.0:
			u.linear_velocity.y = 7.0
			u.battle.snd("whoosh", u.position, 0.4, 1.3)
	if u.flying and c.lift != 0.0:
		u._alt = clampf(u._alt + c.lift * dt * 6.0, 2.0, 30.0)
	u.target = _pick_target(u, c)
	if c.fire and u.cd <= 0.0 and u.act == "":
		_attack(u, c)


## The enemy under the cursor or crosshair, or (for melee) whoever is right in front.
static func _pick_target(u: B3Unit, c: B3Ctl) -> B3Unit:
	var best: B3Unit = null
	var bd := 1e9
	for o: B3Unit in u.battle.units:
		if o == u or o.down or not u.is_enemy(o):
			continue
		var d := u._flat(o.position - c.aim).length()
		if d < maxf(2.2 if not c.fp else 1.2, o.radius + (1.6 if not c.fp else 0.6)) and d < bd:
			bd = d
			best = o
	if best != null or String(u.wpn.type) != "melee":
		return best
	var fwd := u.forward()
	for o: B3Unit in u.battle.units:
		if o == u or o.down or not u.is_enemy(o):
			continue
		var off := u._flat(o.position - u.position)
		var d2 := off.length()
		if d2 < u._reach(u.wpn, o) * 1.3 and fwd.dot(off / maxf(d2, 0.01)) > 0.2 and d2 < bd:
			bd = d2
			best = o
	return best


static func _attack(u: B3Unit, c: B3Ctl) -> void:
	var w: Dictionary = u.wpn
	var ty := String(w.type)
	var aim_at := c.aim
	if not (ty in ["gun", "proj", "throw"]) or (u.target != null and not c.fp):
		u._attack(w)      # melee, or overhead with an enemy under the mouse: the fighter aims itself
		return
	# shoot exactly at the spot (first person: the crosshair; overhead: the ground under the mouse)
	match ty:
		"gun":
			_fire_at(u, w, aim_at if c.fp else aim_at + Vector3(0, 0.9, 0))
		"proj":
			_proj_at(u, w, aim_at)
		"throw":
			_throw_at(u, w, aim_at)


static func _fire_at(u: B3Unit, w: Dictionary, point: Vector3) -> void:
	var from := u._muzzle_pos()
	var dir := (point - from).normalized()
	var s := float(w.get("spread", 0.03))
	if u.ctl and u.ctl.fp:
		s *= 0.5        # aiming down the sights
	dir = (dir + Vector3(u.rng.randf_range(-s, s), u.rng.randf_range(-s, s) * 0.6, u.rng.randf_range(-s, s))).normalized()
	var to := from + dir * (float(w.range) * 1.6)
	var hit: Dictionary = u.battle.raycast(from, to, MASK, [u.get_rid()])
	var end := to
	if not hit.is_empty():
		end = hit.position
		u.battle.shot_hit(hit, w, dir, u)
	var tc: Color = w.get("tracer", Color(4, 3, 1))
	u.battle.fx.tracer(from, end, tc, 0.08)
	if w.has("smoke") and u.has_method("musket_smoke"):
		u.musket_smoke(from, dir)      # muskets: a big puff of smoke
	else:
		u.battle.fx.muzzle(from, dir)
	u.battle.snd(String(w.get("snd", "gun_rifle")), from, 0.7)
	if u.rig:
		u.rig.recoil = 1.0
	u.act = "shoot"
	u.act_t = 0.0
	u.act_len = 0.12
	if w.has("burst"):
		u.burst += 1
		if u.burst >= int(w.burst):
			u.burst = 0
			u.cd = float(w.reload)
		else:
			u.cd = float(w.cd)
	else:
		u.cd = float(w.cd)


static func _proj_at(u: B3Unit, w: Dictionary, point: Vector3) -> void:
	var from := u._muzzle_pos()
	var sp := float(w.get("speed", 20.0))
	var kind_s := String(w.get("proj", "rocket"))
	var vel: Vector3
	if kind_s == "arrow":
		var flat := u._flat(point - from)
		var tt := maxf(flat.length() / sp, 0.15)
		vel = flat / tt + Vector3(0, (point.y - from.y + 0.5 * 9.8 * tt * tt) / tt, 0)
	else:
		var p := point + (Vector3(0, 0.3, 0) if not (u.ctl and u.ctl.fp) else Vector3.ZERO)
		vel = (p - from).normalized() * sp
	u.battle.spawn_proj(kind_s, from, vel, u, w)
	u.battle.snd(String(w.get("snd", "bazooka")), from, 0.8)
	if kind_s == "rocket":
		u.battle.fx.muzzle(from, vel.normalized(), 1.8)
	if u.rig:
		u.rig.recoil = 1.0
	u.cd = float(w.cd)


static func _throw_at(u: B3Unit, w: Dictionary, point: Vector3) -> void:
	var from := u.position + Vector3(0, u.aim_y + 0.5, 0) + u.forward() * 0.3
	var flat := u._flat(point - from)
	var tt := clampf(flat.length() / 9.0, 0.6, 1.5)
	var vel := flat / tt + Vector3(0, (point.y - from.y + 0.5 * 9.8 * tt * tt) / tt, 0)
	var p = u.battle.spawn_proj(String(w.get("proj", "grenade")), from, vel, u, w)
	if p and "fuse" in p:
		p.fuse = tt + 0.5
	u.battle.snd("swing", from, 0.5)
	u._start_act("throw", 0.4, w)
	u.act_fired = true
	u.cd = float(w.cd) * 0.6
