class_name B3Ragdoll
extends Node3D
## A floppy physics version of a unit: one RigidBody3D per body part, held
## together with cone-twist joints. Made from the unit's current pose (the
## rig's meshes move into the bodies), so it flies off exactly where the unit
## was. Knocked-out ragdolls go grey with X eyes; knocked-down ones get
## spinning stars and climb back up (B3Unit rebuilds itself).

static var _pmat: PhysicsMaterial = null

var battle = null
var unit = null            # the B3Unit while it's only knocked down
var kind := ""
var team := ""
var bodies: Array[RigidBody3D] = []
var root_body: RigidBody3D = null
var head_body: RigidBody3D = null
var dead := false
var age := 0.0
var still_t := 0.0
var frozen := false
var sinking := 0.0
var sink_kind := ""
var stars: Node3D = null
var star_t := 0.0
var eyes: Array[Node3D] = []
var _check_t := 0.0
var _land_t := 0.0


static func phys_mat() -> PhysicsMaterial:
	if _pmat == null:
		_pmat = PhysicsMaterial.new()
		_pmat.friction = 0.8
		_pmat.bounce = 0.15
	return _pmat


## Call after adding to the tree.
func build(rig: B3Rig, vel: Vector3, spin: float, rng: RandomNumberGenerator) -> void:
	kind = rig.kind
	team = rig.team
	if rig.parts.is_empty():
		return       # nothing floppy to build (vehicles break apart instead)
	var xf: Array[Transform3D] = []
	for p in rig.parts:
		var n: Node3D = p.node
		xf.append(n.global_transform)
	var total_mass := 0.0
	for i in rig.parts.size():
		var spec: Dictionary = rig.parts[i]
		var pivot: Node3D = spec.node
		var b := RigidBody3D.new()
		b.collision_layer = B3Defs.L_RAGDOLL
		b.collision_mask = B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_RAGDOLL | B3Defs.L_PROP | B3Defs.L_SCENERY
		b.mass = float(spec.mass) * rig.size * rig.size
		b.physics_material_override = phys_mat()
		b.angular_damp = 1.5
		b.linear_damp = 0.05
		b.gravity_scale = 1.25
		var cs := CollisionShape3D.new()
		cs.shape = spec.shape
		cs.transform = spec.offset
		b.add_child(cs)
		add_child(b)
		var t: Transform3D = xf[i]
		b.global_transform = Transform3D(t.basis.orthonormalized(), t.origin)
		for c in pivot.get_children():
			if c.has_meta("pivot"):
				continue
			if c is Node3D:
				(c as Node3D).reparent(b, true)
		b.set_meta("ragdoll", self)
		b.linear_velocity = vel + Vector3(rng.randf_range(-1, 1), rng.randf_range(0, 1), rng.randf_range(-1, 1)) * (0.6 + vel.length() * 0.12)
		b.angular_velocity = Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)) * spin
		var kick: Vector3 = spec.get("kick", Vector3.ZERO)    # a rider hops off its horse
		b.linear_velocity += kick
		bodies.append(b)
		total_mass += b.mass
	root_body = bodies[0]
	head_body = bodies[1] if bodies.size() > 1 else bodies[0]
	# parts that start inside each other (a rider's legs round its horse) don't bump
	for pr in rig.no_collide:
		var pa: Array = pr
		bodies[int(pa[0])].add_collision_exception_with(bodies[int(pa[1])])
	# joints: anchored at each child part's pivot, twist axis along the limb
	for i in rig.parts.size():
		var spec: Dictionary = rig.parts[i]
		var parent := int(spec.parent)
		if parent < 0:
			continue
		var anchor: Vector3 = xf[i].origin
		var off: Transform3D = spec.offset
		var center: Vector3 = xf[i].basis.orthonormalized() * (off.origin) + anchor
		var dir := center - anchor
		if dir.length() < 0.01:
			dir = center - xf[parent].origin
		var x := dir.normalized() if dir.length() > 0.001 else Vector3.DOWN
		var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.9 else Vector3.FORWARD
		var z := x.cross(up).normalized()
		var y := z.cross(x).normalized()
		var j := ConeTwistJoint3D.new()
		add_child(j)
		j.global_transform = Transform3D(Basis(x, y, z), anchor)
		j.set_param(ConeTwistJoint3D.PARAM_SWING_SPAN, deg_to_rad(float(spec.swing)))
		j.set_param(ConeTwistJoint3D.PARAM_TWIST_SPAN, deg_to_rad(float(spec.twist)))
		j.node_a = j.get_path_to(bodies[parent])
		j.node_b = j.get_path_to(bodies[i])
	for e in rig.eyes:
		eyes.append(e)


func set_dead() -> void:
	if dead:
		return
	dead = true
	unit = null
	# grey it out + X eyes
	for b in bodies:
		for c in b.get_children():
			if c is MeshInstance3D:
				var mi := c as MeshInstance3D
				mi.material_overlay = null
				mi.material_override = B3Mats.ko(mi.material_override)
	for e in eyes:
		if not is_instance_valid(e):
			continue
		for c in e.get_children():
			(c as Node3D).visible = false
		var s := 0.07
		for a in [45.0, -45.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = B3Mats.box(Vector3(s * 1.6, s * 0.35, s * 0.35))
			mi.material_override = B3Mats.mat(Color("1d1b2a"))
			mi.rotation_degrees = Vector3(0, 0, a)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			e.add_child(mi)
	if B3Defs.unit_def(kind).get("body", "") == "robot" and not bodies.is_empty():
		_fall_apart()
	show_stars(3.5)


## Robots come apart into a pile of tin pieces when knocked out.
func _fall_apart() -> void:
	for c in get_children():
		if c is Joint3D:
			c.queue_free()
	for b in bodies:
		b.linear_velocity += Vector3(randf_range(-2.5, 2.5), randf_range(2.0, 4.5), randf_range(-2.5, 2.5))
		b.angular_velocity += Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	if battle:
		battle.fx.sparks(center() + Vector3(0, 0.4, 0), 12)
		battle.fx.poof(center(), 0.8)
		battle.snd("metal_hit", center(), 0.8)
		battle.snd("clang", center(), 0.6, 0.8)


func show_stars(t: float) -> void:
	star_t = t
	if stars != null or head_body == null:
		return
	stars = Node3D.new()
	add_child(stars)
	var m := B3Mats.glow(Color("ffd84a"), 1.6)
	for i in 3:
		var mi := MeshInstance3D.new()
		mi.mesh = B3Mats.prism(Vector3(0.16, 0.16, 0.05))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var a := TAU * i / 3.0
		mi.position = Vector3(cos(a), 0, sin(a)) * 0.32
		stars.add_child(mi)


func is_settled() -> bool:
	return still_t > 0.5


func blast(dv: Vector3, from: Vector3, spin: float) -> void:
	if frozen:
		unfreeze()
	for b in bodies:
		var d := b.global_position - from
		var v := dv
		if d.length() > 0.01:
			v = d.normalized() * dv.length() * 0.35 + dv * 0.65
		b.linear_velocity += v
		b.angular_velocity += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * spin
	still_t = 0.0


func push(dv: Vector3) -> void:
	if frozen:
		unfreeze()
	for b in bodies:
		b.linear_velocity += dv
	still_t = 0.0


func unfreeze() -> void:
	frozen = false
	for b in bodies:
		b.freeze = false
		b.sleeping = false


func center() -> Vector3:
	return root_body.global_position if is_instance_valid(root_body) else global_position


func sink(kind_s: String) -> void:
	if sinking > 0.0:
		return
	sinking = 0.01
	sink_kind = kind_s
	for b in bodies:
		b.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		b.freeze = true
	frozen = true


func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	age += dt
	if sinking > 0.0:
		sinking += dt
		for b in bodies:
			b.global_position.y -= dt * 0.55
			b.rotate_x(dt * 0.3)
		if sinking > 2.6:
			_gone()
		return
	if age > 1.0 and int(age * 4.0) % 4 == 0:
		var c := center()
		if c.y < -25.0 or absf(c.x) > B3Defs.BOUNDS + 12.0 or absf(c.z) > B3Defs.BOUNDS + 12.0:
			if unit == null or not is_instance_valid(unit):
				_gone()
				return
	_check_t -= dt
	if _check_t <= 0.0 and not frozen:
		_check_t = 0.12
		var moving := false
		for b in bodies:
			if b.linear_velocity.length_squared() > 0.6:
				moving = true
				break
		if moving:
			still_t = 0.0
		else:
			still_t += 0.12
		if dead and still_t > 4.0:
			frozen = true
			for b in bodies:
				b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				b.freeze = true


func _gone() -> void:
	if battle:
		battle.ragdolls.erase(self)
	queue_free()


func _process(dt: float) -> void:
	if stars:
		if star_t > 0.0 and is_instance_valid(head_body):
			star_t -= dt
			stars.visible = true
			stars.global_position = head_body.global_position + Vector3(0, 0.45 * maxf(1.0, _size_hint()), 0)
			stars.rotation.y += dt * 5.0
			stars.scale = Vector3.ONE * clampf(star_t * 2.0, 0.0, 1.0) * maxf(1.0, _size_hint() * 0.6)
		else:
			stars.queue_free()
			stars = null


func _size_hint() -> float:
	var d := B3Defs.unit_def(kind)
	return float(d.size) * (1.0 if String(d.body) == "human" else 1.6)
