class_name FighterRagdoll
## A fighter's ragdoll, for Fighter: building its jointed parts from the
## standing pose, popping it back out of the ground, and lying still once
## knocked out: still lying on something?, knocked while lying there, waking
## up. (Keeping the joints together and noticing it has stopped are
## Fighter._solve_limits and _rest_check: they run every physics step.)
## Everything here takes the fighter; all the state stays in Fighter.

static var _touch_q: PhysicsShapeQueryParameters2D = null


## Squeezed deep into the ground: back out on top, standing still (see World._cleanup).
static func unbury(f: Fighter) -> void:
	var bs := f.all_bodies()
	if f.puppet or bs.is_empty() or f.frozen_t > 0.0 or f._resting:
		return
	var c := f.center()
	var hs := f.half_size()
	var to: Vector2 = f.world.lift_out_of_ground(c, 6.0 * f.size)
	if f.state == "stand":
		var feet := Vector2(0.0, hs.y - minf(hs.x, hs.y))
		to = f.world.lift_out_of_ground(to + feet, minf(hs.x, hs.y) * 0.9) - feet
	var up: Vector2 = to - c
	if up.y > -1.0:
		return
	for b in bs:
		b.global_position += up
		b.linear_velocity = Vector2.ZERO
		b.angular_velocity = 0.0


static func _part(f: Fighter, name: String, pos: Vector2, rot: float, half: Vector2, round_p: bool, m: float, vel: Vector2) -> FighterPart:
	var p := FighterPart.new()
	p.fighter = f
	p.part = name
	p.half = half
	p.round_part = round_p
	var cs := CollisionShape2D.new()
	if round_p:
		var c := CircleShape2D.new()
		c.radius = half.x
		cs.shape = c
	else:
		var r := RectangleShape2D.new()
		r.size = half * 2.0
		cs.shape = r
	p.add_child(cs)
	p.mass = m
	p.angular_damp = 1.0       # a little joint friction, so limbs settle instead of spinning on
	p.physics_material_override = f._mat(0.8, 0.05)
	p.collision_layer = Fighter.LAYER
	p.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES | Fighter.LAYER
	p.max_contacts_reported = 3   # (no contact_monitor: see make_standing)
	p.angular_damp = 1.2
	p.linear_damp = 0.1
	p.global_position = pos
	p.rotation = rot
	p.linear_velocity = vel
	f.world.bodies.add_child(p)
	f.parts[name] = p
	return p


static func _seg(f: Fighter, c: Vector2, a: Vector2, b: Vector2) -> Array:
	# world centre and rotation of a limb from local points a->b
	var wa := c + f.flipped(a)
	var wb := c + f.flipped(b)
	return [(wa + wb) * 0.5, (wb - wa).angle() - PI * 0.5, wa.distance_to(wb)]


static func make_person(f: Fighter, c: Vector2, v: Vector2, imp: Vector2) -> void:
	var o := f.pose()
	var s := f.size
	var m := 3.0 * s * s
	var spin := randf_range(-4.0, 4.0)
	var vel := v + imp
	_part(f, "head", c + f.flipped(o.head), 0.0, Vector2(11, 11) * s, true, m * 0.13, vel * 1.1)
	var tor := _seg(f, c, o.shoulder, o.hip)
	_part(f, "torso", tor[0], tor[1], Vector2(7, maxf(8.0, tor[2] * 0.5 + 4.0 * s)) * Vector2(s, 1.0), false, m * 0.4, vel)
	for side in ["f", "b"]:
		var ua := _seg(f, c, o.shoulder, o["elbow_" + side])
		_part(f, "uarm_" + side, ua[0], ua[1], Vector2(3.0 * s, ua[2] * 0.5), false, m * 0.06, vel * 1.15)
		var la := _seg(f, c, o["elbow_" + side], o["hand_" + side])
		_part(f, "larm_" + side, la[0], la[1], Vector2(2.6 * s, la[2] * 0.5), false, m * 0.05, vel * 1.2)
		var th := _seg(f, c, o.hip, o["knee_" + side])
		_part(f, "thigh_" + side, th[0], th[1], Vector2(3.6 * s, th[2] * 0.5), false, m * 0.1, vel * 0.95)
		var sn := _seg(f, c, o["knee_" + side], o["foot_" + side])
		_part(f, "shin_" + side, sn[0], sn[1], Vector2(3.2 * s, sn[2] * 0.5), false, m * 0.08, vel * 0.9)
	for p in f.parts.values():
		p.angular_velocity = spin
	_join(f, "torso", "head", c + f.flipped(o.neck), -0.7, 0.7)
	for side in ["f", "b"]:
		# arms flail almost all the way round, but not quite: with no gap at
		# all, nothing ever slowed a spinning arm and it whirled like a helicopter
		_join(f, "torso", "uarm_" + side, c + f.flipped(o.shoulder), -2.7, 2.7)
		_join(f, "uarm_" + side, "larm_" + side, c + f.flipped(o["elbow_" + side]), -2.4, 0.2)
		_join(f, "torso", "thigh_" + side, c + f.flipped(o.hip), -1.6, 1.6)
		_join(f, "thigh_" + side, "shin_" + side, c + f.flipped(o["knee_" + side]), -0.1, 2.4)
	_no_self_collide(f)


static func make_beast(f: Fighter, c: Vector2, v: Vector2, imp: Vector2) -> void:
	var b: Vector2 = f.def.body * f.size
	var bc := c + Vector2(0, -float(f.def.legs) * f.size * 0.5)
	var m := maxf(1.0, f.def.body.x * f.def.body.y / 900.0) * f.size * f.size
	var vel := v + imp
	_part(f, "torso", bc, 0.0, Vector2(b.x * 0.45, b.y * 0.42 + float(f.def.legs) * f.size * 0.25), false, m * 0.75, vel)
	var hr := float(f.def.head) * f.size
	var neck_len := float(f.def.neck) * f.size
	var hp_pos := bc + Vector2(f.facing * (b.x * 0.48 + neck_len * 0.6 + hr * 0.6), -b.y * 0.35 - neck_len * (0.9 if f.def.get("long_neck", false) else 0.5))
	_part(f, "head", hp_pos, 0.0, Vector2(hr * 0.8, hr * 0.8), true, m * 0.12, vel * 1.1)
	_join(f, "torso", "head", bc + Vector2(f.facing * b.x * 0.45, -b.y * 0.2), -0.8, 0.8)
	var tl := float(f.def.tail) * f.size
	if tl > 14.0:
		var tp := bc + Vector2(-f.facing * (b.x * 0.45 + tl * 0.45), -b.y * 0.05)
		_part(f, "tail", tp, 0.0, Vector2(tl * 0.45, maxf(3.0, b.y * 0.12)), false, m * 0.1, vel)
		_join(f, "torso", "tail", bc + Vector2(-f.facing * b.x * 0.42, -b.y * 0.05), -0.9, 0.9)
	for p in f.parts.values():
		p.angular_velocity = randf_range(-3.0, 3.0)
	_no_self_collide(f)


static func _join(f: Fighter, a: String, b: String, at: Vector2, lo: float, hi: float) -> void:
	var pa: FighterPart = f.parts.get(a)
	var pb: FighterPart = f.parts.get(b)
	if pa == null or pb == null:
		return
	var j := PinJoint2D.new()
	f.world.pin_parent.add_child(j)
	j.global_position = at
	j.disable_collision = true
	j.softness = 0.0
	j.node_a = j.get_path_to(pa)
	j.node_b = j.get_path_to(pb)
	f.pins.append(j)
	var ref := pb.rotation - pa.rotation
	if f.facing < 0.0:
		var t2 := lo
		lo = -hi
		hi = -t2
	f.limits.append([pa, pb, ref + lo, ref + hi, pa.to_local(at), pb.to_local(at)])


static func _no_self_collide(f: Fighter) -> void:
	var ps := f.parts.values()
	for i in ps.size():
		for j in range(i + 1, ps.size()):
			ps[i].add_collision_exception_with(ps[j])


## Lying still: is any of our parts still touching the ground, a platform, a
## toy or someone else (a couple of pixels in the direction of gravity)?
## If what we lay on went (a toy knocked away, a Wiggly hopping off), we fall.
static func supported(f: Fighter) -> bool:
	if _touch_q == null:
		_touch_q = PhysicsShapeQueryParameters2D.new()
		_touch_q.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES | Fighter.LAYER
	var down: Vector2 = f.world.gravity_vec().normalized() * 3.0
	var mine: Array[RID] = []
	for p in f.parts.values():
		if is_instance_valid(p):
			mine.append(p.get_rid())
	_touch_q.exclude = mine
	var space: PhysicsDirectSpaceState2D = f.world.get_world_2d().direct_space_state
	for p in f.parts.values():
		if not is_instance_valid(p) or p.get_child_count() == 0:
			continue
		var cs := p.get_child(0) as CollisionShape2D
		if cs == null or cs.shape == null:
			continue
		_touch_q.shape = cs.shape
		_touch_q.transform = p.global_transform.translated(down)
		if not space.intersect_shape(_touch_q, 1).is_empty():
			return true
	return false


## Something hit us while we lay still (World._handle_impacts): wake up and
## take some of the blow, as if we'd been loose all along. `from` is where it
## came from, `m` how heavy it is.
static func knocked_while_resting(f: Fighter, from: Vector2, closing: float, m: float) -> void:
	wake(f)
	var dir := (f.center() - from).normalized()
	var dv := dir * closing * m / (m + f.weight())
	for p in f.all_bodies():
		p.linear_velocity += dv


## A knocked-out ragdoll lying still moves again: a blast or a bump, a fan,
## a beam, a grab, the gravity changing, the ground (or whatever it lay on)
## going. Frozen bodies don't feel any of that by themselves, so everything
## that can move them calls this first (see also World.wake_resting and
## World._handle_impacts).
static func wake(f: Fighter, and_neighbours := true) -> void:
	if not f._resting:
		return
	f._resting = false
	f._rest_t = 0.0
	f._still_t = 0.0
	f._rest_at.clear()
	f._roam_at = Vector2.INF
	for p in f.parts.values():
		if is_instance_valid(p):
			p.freeze = false
	# anyone lying on (or right next to) us moves too; further into a heap,
	# supported() notices soon enough if we were holding someone up
	if and_neighbours:
		f.world.wake_resting(f.center(), f.radius() * 1.5, false)
