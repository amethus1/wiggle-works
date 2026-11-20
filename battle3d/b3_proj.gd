class_name B3Proj
extends Node3D
## Anything that flies and then hits: arrows (arc, stick into things),
## rockets (smoke trail, boom), grenades (bounce, fuse), bombs, artillery
## shells, cluster bombs (split into bomblets), napalm, acid jars and the nuke.
## Moved by hand with a ray each step, so it never tunnels through things.

const MASK := B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_PROP | B3Defs.L_SCENERY

var battle = null
var kind := "arrow"
var vel := Vector3.ZERO
var g := 9.8
var team := ""
var shooter_rid := RID()
var dmg := 20.0
var radius := 3.0
var power := 10.0
var knock := 2.0
var fuse := -1.0
var life := 9.0
var stuck := false
var stuck_t := 0.0
var resting := false
var _trail_t := 0.0
var _q: PhysicsRayQueryParameters3D
var _spin := 0.0


func setup(b, k: String, v: Vector3) -> void:
	battle = b
	kind = k
	vel = v
	_q = PhysicsRayQueryParameters3D.new()
	_q.collision_mask = MASK
	match kind:
		"arrow":
			B3Mats.add(self, B3Mats.cyl(0.018, 0.018, 0.8, 6), B3Mats.mat(Color("a0733f")), Vector3.ZERO, Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.cyl(0.0, 0.045, 0.12, 6), B3Mats.mat(Color("c8ccd2"), 0.3), Vector3(0, 0, 0.44), Vector3(90, 0, 0), Vector3.ONE, false)
			B3Mats.add(self, B3Mats.box(Vector3(0.12, 0.01, 0.14)), B3Mats.mat(Color("ff6b6b")), Vector3(0, 0, -0.36), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.box(Vector3(0.01, 0.12, 0.14)), B3Mats.mat(Color("ff6b6b")), Vector3(0, 0, -0.36), Vector3.ZERO, Vector3.ONE, false)
		"rocket":
			g = 1.2
			B3Mats.add(self, B3Mats.cyl(0.07, 0.07, 0.55, 8), B3Mats.mat(Color("6b7048")), Vector3.ZERO, Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.cyl(0.0, 0.07, 0.2, 8), B3Mats.mat(Color("d94c3a")), Vector3(0, 0, 0.37), Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.sphere(0.09, 8), B3Mats.glow(Color(1.0, 0.6, 0.2), 4.0), Vector3(0, 0, -0.3), Vector3.ZERO, Vector3.ONE, false)
		"grenade", "dropgrenade":
			B3Mats.add(self, B3Mats.sphere(0.13, 10), B3Mats.mat(Color("4f6b35")), Vector3.ZERO, Vector3.ZERO, Vector3(1, 1.15, 1))
			B3Mats.add(self, B3Mats.box(Vector3(0.06, 0.08, 0.06)), B3Mats.mat(Color("a0a6ad"), 0.4), Vector3(0, 0.15, 0), Vector3.ZERO, Vector3.ONE, false)
			_spin = 6.0
		"bomb", "shell", "bomblet", "cluster", "nuke":
			var s: float = {"bomb": 1.0, "shell": 0.6, "bomblet": 0.45, "cluster": 1.2, "nuke": 2.6}[kind]
			var c := Color("3a3f45") if kind != "nuke" else Color("e8c94a")
			if kind == "cluster":
				c = Color("8a5ad6")
			B3Mats.add(self, B3Mats.capsule(0.22 * s, 1.1 * s), B3Mats.mat(c, 0.5), Vector3.ZERO, Vector3(90, 0, 0))
			for a in [0.0, 90.0]:
				B3Mats.add(self, B3Mats.box(Vector3(0.5 * s, 0.04 * s, 0.3 * s)), B3Mats.mat(c.darkened(0.3)), Vector3(0, 0, -0.5 * s), Vector3(0, 0, a))
			if kind == "nuke":
				B3Mats.add(self, B3Mats.cyl(0.58, 0.58, 0.3, 16), B3Mats.mat(Color("2a2a30")), Vector3(0, 0, 0.3), Vector3(90, 0, 0))
				B3Mats.add(self, B3Mats.sphere(0.25, 10), B3Mats.glow(Color(1, 0.3, 0.2), 3.0), Vector3(0, 0.58, 0.3), Vector3.ZERO, Vector3.ONE, false)
		"napalm":
			B3Mats.add(self, B3Mats.cyl(0.25, 0.25, 0.9, 12), B3Mats.mat(Color("d9442b")), Vector3.ZERO, Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.cyl(0.26, 0.26, 0.12, 12), B3Mats.mat(Color("ffcc1a")), Vector3(0, 0, 0.2), Vector3(90, 0, 0))
		"acidbomb":
			B3Mats.add(self, B3Mats.sphere(0.32, 12), B3Mats.glow(Color(0.35, 1.0, 0.25, 0.85), 1.4), Vector3.ZERO)
			B3Mats.add(self, B3Mats.cyl(0.12, 0.12, 0.18, 10), B3Mats.mat(Color("6b4a32")), Vector3(0, 0, 0.35), Vector3(90, 0, 0))
		"fireball":
			g = 0.0
			life = 4.0
			B3Mats.add(self, B3Mats.sphere(0.2, 12), B3Mats.glow(Color(1.0, 0.85, 0.4), 4.0), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.sphere(0.34, 12), B3Mats.glow(Color(1.0, 0.42, 0.08, 0.55), 2.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.cyl(0.0, 0.3, 0.6, 10), B3Mats.glow(Color(1.0, 0.35, 0.05, 0.4), 2.0), Vector3(0, 0, -0.38), Vector3(-90, 0, 0), Vector3.ONE, false)
		"tankshell":
			g = 2.0
			B3Mats.add(self, B3Mats.cyl(0.09, 0.09, 0.4, 10), B3Mats.mat(Color("4a4f38")), Vector3.ZERO, Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.cyl(0.0, 0.09, 0.18, 10), B3Mats.mat(Color("d9a54a"), 0.3), Vector3(0, 0, 0.29), Vector3(90, 0, 0))
			B3Mats.add(self, B3Mats.sphere(0.1, 8), B3Mats.glow(Color(1.0, 0.6, 0.2), 3.0), Vector3(0, 0, -0.22), Vector3.ZERO, Vector3.ONE, false)
		"cannonball":
			B3Mats.add(self, B3Mats.sphere(0.22, 12), B3Mats.mat(Color("26282c"), 0.35, 0.4))
			B3Mats.add(self, B3Mats.cyl(0.02, 0.02, 0.12, 6), B3Mats.mat(Color("8a5a32")), Vector3(0, 0.24, 0), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(self, B3Mats.sphere(0.05, 6), B3Mats.glow(Color(1.0, 0.7, 0.25), 3.0), Vector3(0, 0.31, 0), Vector3.ZERO, Vector3.ONE, false)
		"boulder":
			var rock := B3Mats.mat(Color("8a8580"), 0.95)
			B3Mats.add(self, B3Mats.sphere(0.36, 8), rock, Vector3.ZERO, Vector3(20, 30, 0), Vector3(1.0, 0.8, 0.9))
			B3Mats.add(self, B3Mats.sphere(0.24, 7), B3Mats.mat(Color("77726d"), 0.95), Vector3(0.2, 0.1, 0.05))
			_spin = 7.0
	_orient()


func set_shooter(u) -> void:
	if u == null or not is_instance_valid(u):
		return
	shooter_rid = (u as RigidBody3D).get_rid()
	team = String(u.team)


func _orient() -> void:
	if kind == "grenade" or kind == "dropgrenade" or kind == "boulder" or kind == "cannonball":
		return
	if vel.length_squared() > 0.01:
		var d := vel.normalized()
		var up := Vector3.UP if absf(d.y) < 0.98 else Vector3.RIGHT
		basis = Basis.looking_at(d, up, true)


func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	life -= dt
	if stuck:
		stuck_t -= dt
		if stuck_t <= 0.0:
			queue_free()
		return
	if fuse > 0.0:
		fuse -= dt
		if fuse <= 0.0:
			_boom(global_position)
			return
	if life <= 0.0 or absf(position.x) > B3Defs.BOUNDS + 30.0 or absf(position.z) > B3Defs.BOUNDS + 30.0 or position.y < -30.0:
		queue_free()
		return
	if kind == "cluster" and vel.y < 0.0:
		var gh: float = battle.world.height_at(position.x, position.z)
		if position.y - gh < 9.0:
			_split()
			return
	if resting:
		return
	vel.y -= g * dt
	var from := global_position
	var to := from + vel * dt
	_q.from = from
	_q.to = to
	_q.exclude = [shooter_rid] if shooter_rid.is_valid() else []
	var hit: Dictionary = battle.space().intersect_ray(_q)
	# arrows and grenades fly past friends
	if not hit.is_empty() and team != "" and hit.collider is B3Unit and (hit.collider as B3Unit).team == team and team != "wild":
		_q.exclude = [shooter_rid, (hit.collider as B3Unit).get_rid()] if shooter_rid.is_valid() else [(hit.collider as B3Unit).get_rid()]
		hit = battle.space().intersect_ray(_q)
	if hit.is_empty():
		global_position = to
		_orient()
		if _spin > 0.0:
			rotate_x(dt * _spin)
		if kind == "rocket" or kind == "nuke" or kind == "tankshell" or kind == "cannonball":
			_trail_t -= dt
			if _trail_t <= 0.0:
				_trail_t = 0.025 if kind != "nuke" else 0.05
				if kind == "cannonball":
					_trail_t = 0.05
				battle.fx.trail(global_position - vel.normalized() * 0.4, 0.8 if kind == "nuke" else (0.22 if kind == "cannonball" else 0.3))
		elif kind == "fireball":
			_trail_t -= dt
			if _trail_t <= 0.0:
				_trail_t = 0.03
				battle.fx.flame(global_position - vel.normalized() * 0.3 + Vector3(randf_range(-0.1, 0.1), randf_range(-0.1, 0.1), randf_range(-0.1, 0.1)))
		return
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	match kind:
		"arrow":
			var c = hit.collider
			if c is B3Unit:
				(c as B3Unit).hurt(dmg, (vel.normalized() + Vector3.UP * 0.2).normalized(), knock, battle.unit_by_rid(shooter_rid), "shot")
				battle.snd("arrow_hit", p, 0.6)
				queue_free()
				return
			if c is B3Prop:
				(c as B3Prop).damage(dmg * 0.5)
			global_position = p - vel.normalized() * 0.25
			stuck = true
			stuck_t = 5.0
			battle.snd("arrow_hit", p, 0.4)
		"grenade", "dropgrenade":
			global_position = p + n * 0.14
			var vn := n * vel.dot(n)
			var vt := vel - vn
			vel = (vt * 0.6 - vn * 0.38)
			_spin *= 0.7
			if vel.length() < 1.2:
				vel = Vector3.ZERO
				resting = true
			else:
				battle.snd("clink", p, 0.4)
		_:
			_boom(p + n * 0.1)


func _boom(p: Vector3) -> void:
	match kind:
		"nuke":
			battle.nuke_blast(p)
		"napalm":
			battle.explode(p, radius, power, dmg, {"kind": "fire"})
			battle.spawn_hazard("fire", p, 5.5, 9.0)
			battle.snd("flame", p, 1.0)
		"acidbomb":
			battle.explode(p, radius, power, dmg, {"kind": "acid"})
			battle.spawn_hazard("acid", p, 4.5, 14.0)
			battle.snd("splash", p, 1.0)
		"fireball":
			_fire_burst(p)
		"boulder":
			_crash(p)
		_:
			var by = battle.unit_by_rid(shooter_rid)
			battle.explode(p, radius, power, dmg, {"by": by})
	queue_free()


## Wizard fireball: a small fiery blast that sets fighters burning and leaves
## a little patch of fire on the ground for a few seconds.
func _fire_burst(p: Vector3) -> void:
	var by = battle.unit_by_rid(shooter_rid)
	battle.explode(p, radius, power, dmg, {"by": by})
	var spare := ""
	if team != "" and team != "wild" and not B3Rules.friendly_fire():
		spare = team
	for u: B3Unit in battle.units:
		if u.dead or u.down or B3Defs.is_vehicle(u.kind) or u.kind == "dragon" or u.team == spare:
			continue
		if u.center().distance_to(p) < radius + u.radius:
			u.burn_t = maxf(u.burn_t, 2.5)
	var fires := 0
	for h in battle.hazards:
		if h.kind == "fire":
			fires += 1
	var gy: float = battle.world.height_at(p.x, p.z)
	if fires < 10 and p.y - gy < 1.5:
		battle.spawn_hazard("fire", p, 1.6, 4.0)
	battle.snd("flame", p, 0.8)


## Gorilla boulder: no fire, just a big THUD that bowls fighters over and
## shatters into rubble.
func _crash(p: Vector3) -> void:
	var by = battle.unit_by_rid(shooter_rid)
	for u: B3Unit in battle.units.duplicate():
		if u.dead or not is_instance_valid(u) or (team != "" and team != "wild" and u.team == team):
			continue
		var c := u.center()
		var d := c - p
		var dist := d.length()
		if dist > radius + u.radius:
			continue
		var f := clampf(1.0 - maxf(0.0, dist - u.radius) / radius, 0.25, 1.0)
		var dir := (Vector3(d.x, 0, d.z).normalized() + Vector3.UP * 0.7).normalized()
		u.hurt(dmg * f, dir, knock * f + 2.0, by, "hit")
	battle.blast_props(p, radius + 1.0, 7.0)
	battle.fx.dust(p, radius * 1.2)
	battle.fx.poof(p, 0.9)
	battle.shake(0.25, p)
	battle.snd("crumble", p, 0.9)
	battle.snd("thud", p, 1.0)
	var mat := B3Mats.mat(Color("8a8580"), 0.95)
	for i in 3:
		var sz := Vector3.ONE * randf_range(0.18, 0.28)
		var rb: RigidBody3D = battle._chunk_body(Transform3D(Basis.IDENTITY, p + Vector3(0, 0.3, 0)), sz, 1.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		rb.add_child(cs)
		B3Mats.add(rb, B3Mats.box(sz), mat)
		rb.linear_velocity = vel * 0.15 + Vector3(randf_range(-3, 3), randf_range(2, 5), randf_range(-3, 3))
		rb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	battle._trim_chunks()


func _split() -> void:
	for i in 10:
		var a := TAU * i / 10.0 + randf() * 0.4
		var v := vel * 0.4 + Vector3(cos(a), 0.6, sin(a)) * randf_range(4.0, 9.0)
		var b = battle.spawn_proj("bomblet", global_position, v, null, {})
		b.radius = 2.8
		b.power = 11.0
		b.dmg = 38.0
	battle.fx.explosion(global_position, 1.2)
	battle.snd("pop", global_position, 1.0)
	queue_free()
