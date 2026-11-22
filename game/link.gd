class_name Link
extends RefCounted
## A connection between two bodies: glue (rigid), hinge (spins freely), rope
## (stops them getting farther apart), spring (bouncy) or wire (carries power,
## no pull). Glue and hinge use Godot pin joints; rope and spring are solved
## here every physics step.

var kind := "glue"
var a: PhysicsBody2D
var b: PhysicsBody2D
var la := Vector2.ZERO        # anchor in a's local space
var lb := Vector2.ZERO        # anchor in b's local space
var rest := 0.0
var pins: Array = []
var broken := false
var signal_on := false        # wires: carrying power right now
var uid_a := 0
var uid_b := 0


static func anchor_of(body: PhysicsBody2D, world_pos: Vector2) -> Vector2:
	if body is JellyPoint:
		return Vector2.ZERO
	return body.to_local(world_pos)


func setup(k: String, body_a: PhysicsBody2D, body_b: PhysicsBody2D, pa: Vector2, pb: Vector2) -> void:
	kind = k
	a = body_a
	b = body_b
	la = anchor_of(a, pa)
	lb = anchor_of(b, pb)
	if (k == "glue" or k == "hinge") and is_instance_valid(b):
		# The pins hold both bodies at a's end of the drag, so b's anchor goes
		# there too. Otherwise the gap between where you started and where you
		# let go looks like the joint being ripped apart, and it snaps at once.
		lb = b.to_local(world_a())
	rest = maxf(8.0, world_a().distance_to(world_b()))


func world_a() -> Vector2:
	return a.to_global(la) if is_instance_valid(a) else Vector2.ZERO


func world_b() -> Vector2:
	return b.to_global(lb) if is_instance_valid(b) else Vector2.ZERO


func valid() -> bool:
	return not broken and is_instance_valid(a) and is_instance_valid(b) and a.is_inside_tree() and b.is_inside_tree()


## Creates the pin joints (glue and hinge). Call once both bodies are in the tree.
func build(parent: Node) -> void:
	if kind != "glue" and kind != "hinge":
		return
	var p := world_a()
	var spots := [p]
	if kind == "glue":
		# Two pins a little apart lock rotation too, making a rigid joint.
		var axis := (b.global_position - a.global_position)
		axis = axis.normalized().orthogonal() if axis.length() > 1.0 else Vector2.RIGHT
		spots = [p + axis * 9.0, p - axis * 9.0]
	for s in spots:
		var j := PinJoint2D.new()
		parent.add_child(j)
		j.global_position = s
		j.disable_collision = true
		j.softness = 0.0
		j.node_a = j.get_path_to(a)
		j.node_b = j.get_path_to(b)
		pins.append(j)


func destroy() -> void:
	broken = true
	for j in pins:
		if is_instance_valid(j):
			j.queue_free()
	pins.clear()


## Solves ropes and springs; returns false if the link should break.
func step(dt: float) -> bool:
	if not valid():
		return false
	var pa := world_a()
	var pb := world_b()
	var d := pb - pa
	var dist := d.length()
	match kind:
		"glue", "hinge":
			# If something rips the pins far apart, the connection snaps.
			return dist < 34.0 + (12.0 if kind == "hinge" else 0.0)
		"rope":
			if dist > rest * 2.2 + 120.0:
				return false
			if dist > rest and dist > 0.01:
				_solve_axis(pa, pb, d / dist, dist - rest, dt, true)
		"spring":
			if dist > rest * 3.5 + 200.0:
				return false
			if dist > 0.01:
				_solve_axis(pa, pb, d / dist, dist - rest, dt, false)
	return true


func _solve_axis(pa: Vector2, pb: Vector2, n: Vector2, err: float, dt: float, hard: bool) -> void:
	var sa := _state(a)
	var sb := _state(b)
	var ima := 0.0 if sa == null else sa.inverse_mass
	var imb := 0.0 if sb == null else sb.inverse_mass
	var iia := 0.0 if sa == null else sa.inverse_inertia
	var iib := 0.0 if sb == null else sb.inverse_inertia
	var ra := pa - a.global_position
	var rb := pb - b.global_position
	var rna := ra.cross(n)
	var rnb := rb.cross(n)
	var kk := ima + imb + rna * rna * iia + rnb * rnb * iib
	if kk <= 1e-8:
		return
	var va := Vector2.ZERO if sa == null else sa.linear_velocity + Vector2(-sa.angular_velocity * ra.y, sa.angular_velocity * ra.x)
	var vb := Vector2.ZERO if sb == null else sb.linear_velocity + Vector2(-sb.angular_velocity * rb.y, sb.angular_velocity * rb.x)
	var vrel := (vb - va).dot(n)
	var imp := 0.0
	if hard:
		var desired := -err * 0.35 / dt
		if vrel <= desired:
			return
		imp = (desired - vrel) / kk
	else:
		var omega := TAU * 2.2
		var zeta := 0.3
		imp = -(omega * omega * err * dt + 2.0 * zeta * omega * vrel * dt) / kk
	var J := n * imp
	if sa != null:
		sa.apply_impulse(-J, ra)
	if sb != null:
		sb.apply_impulse(J, rb)


static func _state(body: PhysicsBody2D) -> PhysicsDirectBodyState2D:
	if not (body is RigidBody2D) or (body as RigidBody2D).freeze:
		return null
	return PhysicsServer2D.body_get_direct_state(body.get_rid())
