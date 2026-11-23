class_name B3Combat
extends RefCounted
## Booms, blasts, hits and breaking things, for B3Battle (its `combat`).
## The 💣 Booms tab (drop, airstrike planes, artillery, C4), explosions and
## the nuke's shock wave, shots hitting things, buildings and crates breaking
## into chunks, and loose bodies sinking in lava and acid. B3Battle passes its
## explode, shot_hit, break_piece... on to this; the lists of what's on the
## field (units, props, chunks, planes...) stay on the battle.

## Booms from the Toy Box that go off by themselves (the 🎆 Boom Boom Boom sticker counts them).
const SELF_BOOMS := ["grenade", "dynamite", "cluster", "napalm", "acidbomb", "airstrike", "artillery", "nuke"]
var battle: B3Battle
var _waves: Array = []
var _sinking: Array = []
var _settling := {}               # buildings (instance ids) with a settle() waiting (settle_soon)
var _hz_t := 0.0
var _shape_q := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()


func _init(b: B3Battle) -> void:
	battle = b
	_sphere.radius = 1.0
	_shape_q.shape = _sphere
	_shape_q.collide_with_bodies = true
	_shape_q.collide_with_areas = false


## Forgets the waves rolling out, the buildings waiting to settle and the
## chunks sinking (the battlefield's been cleared).
func clear() -> void:
	_settling.clear()
	_waves.clear()
	_sinking.clear()


# ------------------------------------------------------------- 💣 the Booms tab
## Things from the Booms tab: `dir` is the screen-right direction (airstrikes).
## `mine` false: not this computer's person's doing (a friend's, sent to the
## host), so no 📒 stickers here. Nor for booms a script sets off by itself
## (🎯 Nuke! and C4 Surprise at Fight!, see B3Battle.later()).
func drop(id: String, pos: Vector3, dir := Vector3.RIGHT, mine := true) -> void:
	var b := battle
	var spent0 := b.spent
	if b.puzzle and not b.puzzle.pay_boom(id, pos):
		return      # 🧩 in a puzzle, booms cost points and go on your side only
	if b.modes and not b.modes.pay_boom(id, pos):
		return      # 🌊 Wave Defense: the same, in your fort
	var paid := b.spent - spent0      # (a mine, barrel or C4 keeps it: erasing it before the fight gives it back)
	if mine and not b._scripted:
		if id == "nuke":
			Settings.award("nuke")
		if id in SELF_BOOMS:
			Settings.count("booms", "boom", 10)
	if b._client_cmd({"c": "drop", "id": id, "pos": pos, "dir": dir}):
		return
	var d: Dictionary = B3Defs.BOOMS.get(id, {})
	match id:
		"grenade":
			var p := b.spawn_proj("dropgrenade", pos + Vector3(0, 3.0, 0), Vector3(b.rng.randf_range(-1, 1), -1.0, b.rng.randf_range(-1, 1)), null, d)
			p.fuse = 2.3
		"dynamite", "c4", "mine", "xbarrel":
			var bp := b.spawn_prop(id, pos, b.rng.randf() * TAU)
			if paid > 0:
				bp.set_meta("cost", paid)
		"cluster", "napalm", "acidbomb":
			b.spawn_proj(id, pos + Vector3(0, 26, 0), Vector3(0, -10, 0), null, d)
			b.snd("whistle", pos, 0.8)
		"airstrike":
			airstrike(pos, dir)
		"artillery":
			artillery(pos)
		"nuke":
			b.spawn_proj("nuke", pos + Vector3(0, 40, 0), Vector3(0, -16, 0), null, d)
			b.snd("alarm", pos, 1.0)
			b.snd("whistle", pos, 1.0)
			if b.ui:
				b.ui.toast("☢️  NUKE INCOMING!")


func airstrike(pos: Vector3, dir: Vector3) -> void:
	var b := battle
	if b.puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var d := Vector3(dir.x, 0, dir.z).normalized()
	if d == Vector3.ZERO:
		d = Vector3.RIGHT
	var plane := Node3D.new()
	var body := B3Mats.mat(Color("8a96a8"), 0.5)
	B3Mats.add(plane, B3Mats.capsule(0.6, 6.0), body, Vector3.ZERO, Vector3(90, 0, 0))
	B3Mats.add(plane, B3Mats.box(Vector3(9.0, 0.15, 1.6)), body, Vector3(0, 0, 0.2))
	B3Mats.add(plane, B3Mats.box(Vector3(3.2, 0.12, 0.9)), body, Vector3(0, 0.1, -2.6))
	B3Mats.add(plane, B3Mats.box(Vector3(0.12, 1.4, 1.0)), body, Vector3(0, 0.7, -2.6))
	B3Mats.add(plane, B3Mats.sphere(0.45, 10), B3Mats.mat(Color("6fd3ff"), 0.1), Vector3(0, 0.35, 1.6), Vector3.ZERO, Vector3(0.8, 0.6, 1.4))
	for sx in [-1.0, 1.0]:
		B3Mats.add(plane, B3Mats.box(Vector3(0.6, 0.16, 1.2)), B3Mats.mat(Color("ff4646")), Vector3(4.2 * sx, 0.02, 0.2), Vector3.ZERO, Vector3.ONE, false)
	b.proj_root.add_child(plane)
	var start := pos - d * 75.0 + Vector3(0, 20, 0)
	plane.global_position = start
	plane.global_basis = Basis.looking_at(d, Vector3.UP, true)
	plane.reset_physics_interpolation()
	var drops: Array[Vector3] = []
	for i in 8:
		drops.append(pos + d * (i - 3.5) * 2.8)
	b.planes.append({"node": plane, "dir": d, "speed": 34.0, "drops": drops, "i": 0, "life": 5.0})
	b.snd("plane", pos, 1.0)


func artillery(pos: Vector3) -> void:
	var b := battle
	if b.puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var side := Vector3(b.rng.randf_range(-1, 1), 0, b.rng.randf_range(-1, 1)).normalized()
	for i in 10:
		var t := 0.2 + i * 0.28 + b.rng.randf() * 0.15
		var off := Vector3(b.rng.randf_range(-7, 7), 0, b.rng.randf_range(-7, 7))
		b.later(t, func():
			var target := pos + off
			target.y = b.world.height_at(target.x, target.z)
			var start := target + side * 18.0 + Vector3(0, 38, 0)
			var tt := 1.5
			var v := B3Proj.lob(start, target, tt, "shell")      # lands on target under the Gravity rule
			b.spawn_proj("shell", start, v, null, B3Defs.BOOMS.artillery)
			b.snd("whistle", target, 0.6))


## How far before the target an airstrike plane lets go of a bomb: the bomb
## keeps 5 m/s of the plane's speed while it falls `h` metres (starting at
## 2 m/s down) under the Gravity rule, so it still lands on target in Moon gravity.
static func bomb_lead(h: float) -> float:
	var g := B3Proj.gravity("bomb")
	var t := maxf(h, 0.0) / 2.0 if g < 0.01 else (-2.0 + sqrt(4.0 + 2.0 * g * maxf(h, 0.0))) / g
	return 5.0 * t


## The airstrike planes fly on and drop their bombs.
func planes_tick(dt: float) -> void:
	var b := battle
	var planes := b.planes
	var i := 0
	while i < planes.size():
		var pl: Dictionary = planes[i]
		var node: Node3D = pl.node
		if not is_instance_valid(node):
			planes.remove_at(i)
			continue
		var d: Vector3 = pl.dir
		node.global_position += d * float(pl.speed) * dt
		var drops: Array[Vector3] = pl.drops
		var k: int = pl.i
		while k < drops.size():
			var target: Vector3 = drops[k]
			var rel := (node.global_position - target).dot(d)
			if rel < -bomb_lead(node.global_position.y - 0.8 - target.y):
				break
			var bomb := b.spawn_proj("bomb", node.global_position - Vector3(0, 0.8, 0), d * 5.0 + Vector3(0, -2, 0), null, B3Defs.BOOMS.airstrike)
			bomb.reset_physics_interpolation()
			b.snd("whistle", target, 0.5)
			k += 1
		pl.i = k
		pl.life = float(pl.life) - dt
		if float(pl.life) <= 0.0:
			node.queue_free()
			planes.remove_at(i)
			continue
		i += 1


func c4_count() -> int:
	var n := 0
	for p in battle.props:
		if p.kind == "c4" and not p.lit:
			n += 1
	return n


## 💥 Sets off every C4. `mine`: as for drop() (a script's or a friend's
## press earns no 📒 stickers on this computer).
func detonate_c4(mine := true) -> void:
	var b := battle
	var n := c4_count()
	if n > 0 and mine and not b._scripted:
		Settings.count("booms", "boom", 10, n)
	if b._client_cmd({"c": "c4"}):
		return
	var t := 0.0
	var any := false
	for p in b.props:
		if p.kind == "c4" and not p.lit:
			p.trigger(t)
			t += 0.12
			any = true
	if any:
		b.snd("pin", null, 1.0)
	elif b.ui:
		b.ui.toast("No C4 placed yet! Pick 📟 C4 from the 💣 Booms tab.", false)


# --------------------------------------------------------------- explosions
## The big one: knocks, damages, launches, breaks and chains. `power` is the
## launch speed (m/s) at the centre; it fades to nothing at `r`.
## opts: "by" (who threw or fired it), "team" (theirs, in case they've been
## knocked out since), "up", "kind", "quiet", and "hit" / "skip" (dictionaries
## that get the fighters' uids (with the damage each took) / the bodies it
## hit, so a blast that follows can leave them alone).
func explode(pos: Vector3, r: float, power: float, dmg: float, opts := {}) -> void:
	var b := battle
	if b.puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	var up: float = opts.get("up", 0.8)
	var kind := String(opts.get("kind", "fire"))
	var by = opts.get("by", null)
	if by != null and not is_instance_valid(by):
		by = null
	r *= B3Rules.boom_r()
	power *= B3Rules.boom_power()
	var spare_team := ""
	if not B3Rules.friendly_fire():
		var own := String(by.team) if by != null and by is B3Unit else String(opts.get("team", ""))
		if own != "wild":
			spare_team = own
	var hit: Dictionary = opts.get("hit", {})
	if b.modes and b.modes.keep_up:
		b.modes.keep_blast(pos, r, dmg, String(by.team) if by is B3Unit else String(opts.get("team", "")))     # 🌊 the attackers' booms hurt the 🚩 keep
	_blast_bodies(pos, r, power * b.r_knock, dmg, up, opts.get("skip", {}), 0.0, 0.0, spare_team, {}, by as B3Unit)
	for u: B3Unit in b.units.duplicate():
		if u.dead or not is_instance_valid(u) or hit.has(u.uid):
			continue
		if spare_team != "" and u.team == spare_team:
			continue
		var c := u.center()
		var d := c - pos
		var dist := d.length()
		if dist > r + u.radius:
			continue
		var f := clampf(1.0 - maxf(0.0, dist - u.radius) / r, 0.0, 1.0)
		var dir := (Vector3(d.x, 0, d.z).normalized() + Vector3.UP * up).normalized()
		hit[u.uid] = dmg * f
		u.hurt(dmg * f, dir, power * f * 1.15 + 1.5, by, "blast")      # (its hit marker for you, too)
	if bool(opts.get("quiet", false)):
		return
	b.fx.explosion(pos, r, 1 if kind == "acid" else 0)
	b.shake(clampf(r / 7.0, 0.15, 0.9), pos)
	if r >= 5.0:
		b.snd("mega_boom", pos, 1.0)
	else:
		b.snd("boom", pos, 0.9)


## Blasts the loose things: ragdolls, props, building pieces and trees.
## `spare`: a team whose fighters lying on the ground are left alone
## (Battle Rules: blasts don't hurt teammates). `units_hit`: uids of fighters
## already hurt by this blast, whose ragdolls are only pushed, not hurt again.
## `by`: whose blast it is (knocking out someone lying on the ground counts for them).
func _blast_bodies(pos: Vector3, r: float, power: float, dmg: float, up: float, skip: Dictionary, r_min := 0.0, fall_r := 0.0, spare := "", units_hit: Dictionary = {}, by: B3Unit = null) -> void:
	var b := battle
	var rng := b.rng
	var fr := fall_r if fall_r > 0.0 else r
	_sphere.radius = r
	_shape_q.transform = Transform3D(Basis.IDENTITY, pos)
	_shape_q.collision_mask = B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_STRUCT | B3Defs.L_SCENERY
	var res := b.space().intersect_shape(_shape_q, 1024)
	var hit_rd := {}
	var touched := {}
	for hit in res:
		var c = hit.collider
		if c == null or not is_instance_valid(c):
			continue
		var id: int = (c as Object).get_instance_id()
		if skip.has(id):
			continue
		var cp: Vector3 = (c as Node3D).global_position
		var d := cp - pos
		var dist := d.length()
		if dist < r_min:
			continue
		skip[id] = true
		if c is B3Piece:
			var pc := c as B3Piece
			var ed := maxf(0.0, dist - pc.size.length() * 0.35)
			var f2 := clampf(1.0 - ed / fr, 0.0, 1.0)
			if f2 <= 0.0:
				continue
			pc.hp -= dmg * f2 * 1.4
			if pc.hp <= 0.0 or power * f2 > 14.0:
				var dir2 := (d.normalized() + Vector3.UP * 0.6).normalized()
				touched[pc.structure] = true
				break_piece(pc, dir2 * power * f2 * 0.8)
			continue
		var f := clampf(1.0 - dist / fr, 0.0, 1.0)
		if f <= 0.0:
			continue
		var dir := (d.normalized() if dist > 0.05 else Vector3.UP)
		dir = (dir + Vector3.UP * up * 0.6).normalized()
		if c is RigidBody3D:
			var rb := c as RigidBody3D
			if rb.has_meta("ragdoll"):
				var rd = rb.get_meta("ragdoll")
				if is_instance_valid(rd):
					var mate: bool = spare != "" and is_instance_valid(rd.unit) and not rd.unit.dead and String(rd.unit.team) == spare
					if mate:
						continue      # a teammate who's been knocked down isn't hurt or thrown about either
					if rd.frozen and rd.sinking <= 0.0:
						rd.unfreeze()
					if rd.unit and is_instance_valid(rd.unit) and not hit_rd.has(rd.get_instance_id()) and not units_hit.has(rd.unit.uid):
						hit_rd[rd.get_instance_id()] = true
						rd.unit.hurt(dmg * f * 0.6, dir, 0.0, by, "blast")
				if not rb.freeze:
					rb.linear_velocity += dir * power * f * 1.1
					rb.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.6
			elif rb is B3Prop:
				var p := rb as B3Prop
				if not p.freeze:
					var k := clampf(40.0 / p.mass, 0.4, 1.4)
					p.linear_velocity += dir * power * f * k
					p.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.4
				p.damage(dmg * f)
			elif not rb.freeze:
				rb.linear_velocity += dir * power * f
				rb.angular_velocity += Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * power * f * 0.3
		elif c is StaticBody3D and (c as Node).has_meta("scenery"):
			if power * f > 15.0:
				if b.net:
					b.net.rec_event(["uproot", b.world.scenery_index(c), dir * power * f * 0.7])
				b.world.uproot(c, dir * power * f * 0.7, b)
	for s in touched:
		if is_instance_valid(s):
			settle_soon(s as B3Struct)


## Pushes props and ragdolls around without damage (stomps, charges).
func blast_props(pos: Vector3, r: float, power: float) -> void:
	if battle.puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	_sphere.radius = r
	_shape_q.transform = Transform3D(Basis.IDENTITY, pos)
	_shape_q.collision_mask = B3Defs.L_RAGDOLL | B3Defs.L_PROP
	for hit in battle.space().intersect_shape(_shape_q, 128):
		var c = hit.collider
		if c is RigidBody3D and not (c as RigidBody3D).freeze:
			var rb := c as RigidBody3D
			var d := rb.global_position - pos
			var f := clampf(1.0 - d.length() / r, 0.0, 1.0)
			rb.linear_velocity += (Vector3(d.x, 0, d.z).normalized() + Vector3.UP * 0.8).normalized() * power * f
		elif c is RigidBody3D and (c as Node).has_meta("ragdoll"):
			var rd = (c as Node).get_meta("ragdoll")
			if is_instance_valid(rd) and rd.frozen and rd.sinking <= 0.0:
				rd.unfreeze()


func nuke_blast(pos: Vector3) -> void:
	var b := battle
	if b.puppet:
		return     # a friend's copy: the host does the real thing and sends the effects
	b.fx.nuke(pos)
	if b.ui:
		b.ui.flash(1.0)
	b.cam.shake(1.6)
	b.snd("nuke", pos, 1.4)
	b.snd("mega_boom", pos, 1.4)
	b.snd("rumble", pos, 1.2)
	# the fireball in the middle, then the shock wave rolling out. The fireball
	# reaches past the wave's start with bigger explosions, so the wave only
	# adds whatever damage the fireball didn't already do (never both in full).
	var fire_hits := {}
	var hit_bodies := {}
	explode(pos, 10.0, 42.0, 900.0, {"quiet": true, "up": 1.0, "hit": fire_hits, "skip": hit_bodies})
	_waves.append({"pos": pos, "r": 10.0, "max": 46.0, "speed": 32.0, "power": 36.0, "dmg": 520.0, "skip": hit_bodies, "units": {}, "fire": fire_hits})


## The nukes' shock waves roll on (each physics step).
func waves_tick(dt: float) -> void:
	var i := 0
	while i < _waves.size():
		if not _wave_tick(_waves[i], dt):
			_waves.remove_at(i)
		else:
			i += 1


func _wave_tick(w: Dictionary, dt: float) -> bool:
	var pos: Vector3 = w.pos
	var r0: float = w.r
	var r1 := r0 + float(w.speed) * dt
	var mx: float = w.max
	w.r = r1
	var power: float = w.power
	var dmg: float = w.dmg
	var waved: Dictionary = w.units       # fighters this wave has reached
	var fire: Dictionary = w.get("fire", {})     # uid -> damage the fireball already did
	for u: B3Unit in battle.units.duplicate():
		if u.dead or waved.has(u.uid):
			continue
		var c := u.center()
		var dist := Vector2(c.x - pos.x, c.z - pos.z).length()
		if dist > r1:
			continue
		waved[u.uid] = true
		var f := clampf(1.0 - dist / mx, 0.0, 1.0)
		var d := dmg * f - float(fire.get(u.uid, 0.0))
		if fire.has(u.uid) and d <= 0.0:
			continue      # the fireball already hit it harder than the wave would
		var dir := (Vector3(c.x - pos.x, 0, c.z - pos.z).normalized() + Vector3.UP * 0.9).normalized()
		u.hurt(d, dir, power * f + 5.0, null, "blast")
	_blast_bodies(pos, r1, power, dmg, 0.9, w.skip, r0 - 1.0, mx, "", fire.merged(waved))
	return r1 < mx


# ----------------------------------------------------------- hits & breaks
func shot_hit(hit: Dictionary, w: Dictionary, dir: Vector3, shooter) -> void:
	var c = hit.collider
	var p: Vector3 = hit.position
	if c is B3Unit:
		(c as B3Unit).hurt(float(w.dmg), dir, float(w.get("knock", 1.0)), shooter, "shot")      # (hurt shows your hit marker, not a dodge)
	elif c is B3Prop:
		var pr := c as B3Prop
		pr.damage(float(w.dmg))
		if not pr.freeze and is_instance_valid(pr):
			pr.apply_impulse(dir * float(w.dmg) * 0.5, p - pr.global_position)
		battle.snd("metal_hit" if pr.kind == "xbarrel" else "thud", p, 0.4)
	elif c is B3Piece:
		var pc := c as B3Piece
		pc.hp -= float(w.dmg) * 0.15
		if pc.hp <= 0.0:
			break_piece(pc, dir * 3.0)
		battle.fx.dust(p, 0.25)


## Someone hurt `victim`. If it was the fighter or vehicle you're playing
## and `victim` is an enemy, the first-person crosshair shows a hit marker.
func player_hit(by, victim) -> void:
	if battle.ui == null or by == null or not is_instance_valid(by) or not (by is B3Unit) or by != B3Player.unit:
		return
	if (by as B3Unit).ctl != B3Player.me or not (victim is B3Unit) or not (by as B3Unit).is_enemy(victim as B3Unit):
		return
	battle.ui.hit_marker()


func break_piece(p: B3Piece, vel: Vector3, whole := false) -> void:
	if not is_instance_valid(p) or p.is_queued_for_deletion():
		return
	var b := battle
	var rng := b.rng
	var s: B3Struct = p.structure
	if b.net and is_instance_valid(s):
		b.net.rec_event(["brk", s.get_instance_id(), int(p.get_meta("pi", -1)), vel, whole])
	if s:
		s.pieces.erase(p)
	var xf := p.global_transform
	var mat: Material = null
	for c in p.get_children():
		if c is MeshInstance3D:
			mat = (c as MeshInstance3D).material_override
			break
	if p.whole or p.wedge or whole:
		var rb := chunk_body(xf, p.size, 1.0)
		for c in p.get_children():
			(c as Node).reparent(rb, true)
		rb.linear_velocity = vel
		rb.angular_velocity = Vector3(rng.randf_range(-2, 2), rng.randf_range(-2, 2), rng.randf_range(-2, 2)) * (0.3 + vel.length() * 0.1)
	else:
		var n := Vector3i(clampi(ceili(p.size.x / 1.3), 1, 3), clampi(ceili(p.size.y / 1.3), 1, 2), clampi(ceili(p.size.z / 1.3), 1, 3))
		var sub := p.size / Vector3(n)
		for ix in n.x:
			for iy in n.y:
				for iz in n.z:
					var lp := -p.size * 0.5 + sub * Vector3(ix + 0.5, iy + 0.5, iz + 0.5)
					var rb := chunk_body(Transform3D(xf.basis, xf * lp), sub, 1.0)
					var cs := CollisionShape3D.new()
					var bs := BoxShape3D.new()
					bs.size = sub * 0.96
					cs.shape = bs
					rb.add_child(cs)
					B3Mats.add(rb, B3Mats.box(sub * 0.97), mat)
					var spread := Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)) * (1.5 + vel.length() * 0.25)
					rb.linear_velocity = vel + spread
					rb.angular_velocity = Vector3(rng.randf_range(-3, 3), rng.randf_range(-3, 3), rng.randf_range(-3, 3)) * (0.3 + vel.length() * 0.08)
	p.queue_free()
	b.fx.dust(xf.origin, maxf(1.0, p.size.length() * 0.4))
	b.snd("crumble", xf.origin, 0.8)
	if s and s.pieces.is_empty():
		b.structs.erase(s)
		s.queue_free()
	elif s and not whole:
		settle_soon(s)
	trim_chunks()


## Anything left floating after pieces of `s` break falls, at the next go of
## the `later` list. One blast can break a dozen pieces of one building: it
## only needs checking once for all of them (settle() looks at every pair of
## pieces), so while one check is waiting no more are added.
func settle_soon(s: B3Struct) -> void:
	var id := s.get_instance_id()
	if _settling.has(id):
		return
	_settling[id] = true
	# (looked up by id when it fires: a lambda that captured the building
	# itself makes Godot print an error if the building is gone by then)
	battle.later(0.0, func():
		_settling.erase(id)
		var st := instance_from_id(id) as B3Struct
		if st != null and is_instance_valid(st):
			st.settle())


func chunk_body(xf: Transform3D, size: Vector3, _k: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.collision_layer = B3Defs.L_PROP
	rb.collision_mask = B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_UNIT | B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_SCENERY
	rb.mass = clampf(size.x * size.y * size.z * 120.0, 6.0, 160.0)
	rb.physics_material_override = B3Prop.pmat()
	rb.angular_damp = 0.5
	rb.set_meta("debris", true)
	battle.prop_root.add_child(rb)
	rb.global_transform = xf
	rb.reset_physics_interpolation()
	battle.chunks.append(rb)
	return rb


func break_crate(c: B3Prop) -> void:
	var b := battle
	var rng := b.rng
	var xf := c.global_transform
	var v := c.linear_velocity
	b.remove_prop(c, false)
	var mat := B3Mats.mat(Color("c08a4e"))
	for i in 4:
		var lp := Vector3(0, -0.375 + i * 0.25, 0)
		var rb := chunk_body(Transform3D(xf.basis, xf * lp), Vector3(1.0, 0.22, 0.3), 1.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.0, 0.2, 0.3)
		cs.shape = bs
		rb.add_child(cs)
		B3Mats.add(rb, B3Mats.box(Vector3(1.0, 0.2, 0.3)), mat)
		rb.linear_velocity = v + Vector3(rng.randf_range(-3, 3), rng.randf_range(1, 5), rng.randf_range(-3, 3))
		rb.angular_velocity = Vector3(rng.randf_range(-5, 5), rng.randf_range(-5, 5), rng.randf_range(-5, 5))
	b.fx.poof(xf.origin, 1.0)
	b.snd("crumble", xf.origin, 0.7)
	trim_chunks()


func trim_chunks() -> void:
	var chunks := battle.chunks
	while chunks.size() > B3Defs.MAX_CHUNKS:
		var c: RigidBody3D = chunks.pop_front()
		if is_instance_valid(c):
			battle.fx.poof(c.global_position, 0.5)
			c.queue_free()


# ------------------------------------------------------------ 🌋 pools
## Every 0.15 s, ragdolls, props and chunks that fell into lava or acid start
## to sink; sinking chunks go down and vanish.
func pools_tick(dt: float) -> void:
	_hz_t -= dt
	if _hz_t <= 0.0:
		_hz_t = 0.15
		_hazard_bodies()
	var i := 0
	while i < _sinking.size():
		var sk: Array = _sinking[i]
		var rb: RigidBody3D = sk[0]
		sk[1] = float(sk[1]) + dt
		if not is_instance_valid(rb) or float(sk[1]) > 2.2:
			if is_instance_valid(rb):
				rb.queue_free()
			_sinking.remove_at(i)
			continue
		rb.global_position.y -= dt * 0.6
		i += 1


## Ragdolls, props and chunks that fall into lava/acid sink and vanish.
func _hazard_bodies() -> void:
	var b := battle
	var hazards := b.hazards
	if hazards.is_empty():
		return
	for rd: B3Ragdoll in b.ragdolls.duplicate():
		if not is_instance_valid(rd) or rd.sinking > 0.0:
			continue
		var c := rd.center()
		for h in hazards:
			if h.kind != "fire" and h.contains(c, -0.3):
				rd.sink(h.kind)
				b.fx.splash(c, h.kind == "acid")
				b.snd("sizzle" if h.kind == "lava" else "fizz", c, 0.8)
				break
	for p: B3Prop in b.props.duplicate():
		if not is_instance_valid(p) or p.sinking > 0.0 or p.freeze:
			continue
		for h in hazards:
			if h.kind != "fire" and h.contains(p.global_position, -0.2):
				if p.kind == "xbarrel" or p.kind == "dynamite":
					p.trigger(0.2)
				else:
					p.sinking = 0.01
					p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
					p.freeze = true
					b.fx.splash(p.global_position, h.kind == "acid")
					b.snd("sizzle", p.global_position, 0.6)
				break
	var chunks := b.chunks
	for c: RigidBody3D in chunks.duplicate():
		if not is_instance_valid(c):
			chunks.erase(c)
			continue
		for h in hazards:
			if h.kind != "fire" and h.contains(c.global_position, -0.2):
				chunks.erase(c)
				c.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				c.freeze = true
				_sinking.append([c, 0.0])
				b.fx.splash(c.global_position, h.kind == "acid")
				break
