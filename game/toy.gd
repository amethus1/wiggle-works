class_name Toy
extends RigidBody2D
## A rigid toy (ball, block, machine, boom, ride part). Knows its shape, paint,
## size and play state, and draws itself with Art.

const LAYER_GROUND := 1
const LAYER_TOYS := 2
const LAYER_WIGGLIES := 4
const LAYER_FIGHTERS := 16
# px/s: nothing in the game moves this fast (a nuke throws things about
# 5,000 px/s). See stop_wild_jump.
const MAX_SPEED := 18000.0

var uid := 0
var world: Node = null
var id := ""                  # catalog id, or a part name: wheel, basket, sail, seat
var def := {}
var shape_kind := "box"       # circle | box | tri
var r := 10.0
var w := 20.0
var h := 20.0
var size_scale := 1.0
var color := Color.WHITE
var paint := Color(0, 0, 0, 0)   # alpha > 0 = painted
var letter := ""
var on := false               # switched on with Use (fan, lamp, kart…)
var powered := false          # getting power from a wire (or a Zappy zap)
var zap_power := 0.0          # seconds of power left from a Zappy zap
var cooldown := 0.0
var fuse := -1.0              # seconds until a lit firework/bomb goes off
var frozen_t := 0.0           # frozen in ice
var bubble_t := 0.0           # floating in a bubble
var electric := 0.0
var wet := 0.0
var nailed := false           # pinned in place with the Nail tool
var facing := 1.0
var parent_uid := 0:          # multi-part rides: the main part
	set(v):
		parent_uid = v
		if world is World:
			world.parent_changes += 1   # (see World.ride_parts)
var puppet := false           # network client copy: no physics, just drawn
var extra := {}
var _prev_contacts := {}
var _art_key := ""
var _last := Vector2.INF   # where the physics (or our own code) last put us


func setup(toy_id: String, d: Dictionary, pos: Vector2, rot := 0.0, scale_f := 1.0) -> void:
	id = toy_id
	def = d
	shape_kind = String(d.get("shape", "box"))
	r = float(d.get("r", 12.0))
	w = float(d.get("w", r * 2.0))
	h = float(d.get("h", r * 2.0))
	color = d.get("color", Color.WHITE)
	size_scale = scale_f
	position = pos
	rotation = rot
	collision_layer = LAYER_TOYS
	collision_mask = LAYER_GROUND | LAYER_TOYS | LAYER_WIGGLIES | LAYER_FIGHTERS
	var pm := PhysicsMaterial.new()
	pm.friction = float(d.get("fric", 0.6))
	pm.bounce = float(d.get("bounce", 0.1))
	physics_material_override = pm
	contact_monitor = true
	max_contacts_reported = 6
	angular_damp = 0.3
	linear_damp = 0.05
	if toy_id == "abc_block" and letter == "":
		letter = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"[randi() % 26]
		color = Catalog.PAINT[randi() % 7]
	if d.has("lift"):
		gravity_scale = 0.0
	_build_shape()


func _build_shape() -> void:
	for c in get_children():
		if c is CollisionShape2D or c is CollisionPolygon2D:
			c.queue_free()
	var s := size_scale
	mass = maxf(0.05, float(def.get("mass", 1.0)) * s * s)
	if shape_kind == "circle":
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = r * s
		cs.shape = c
		add_child(cs)
	elif shape_kind == "tri":
		var cp := CollisionShape2D.new()
		var poly := ConvexPolygonShape2D.new()
		poly.points = tri_points()
		cp.shape = poly
		add_child(cp)
	else:
		var cs := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(w, h) * s
		cs.shape = rect
		add_child(cs)
	if minf(w, h) * s < 14.0 or shape_kind == "circle" and r * s < 10.0:
		continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	queue_redraw()


## Ramp outline (rises toward its facing side).
func tri_points() -> PackedVector2Array:
	var hw := w * 0.5 * size_scale
	var hh := h * 0.5 * size_scale
	var f := facing
	return PackedVector2Array([Vector2(-hw * f, hh), Vector2(hw * f, hh), Vector2(hw * f, -hh)])


func set_size(s: float) -> void:
	size_scale = clampf(s, 0.4, 3.0)
	_build_shape()


func set_facing(f: float) -> void:
	facing = f
	if shape_kind == "tri":
		_build_shape()
	queue_redraw()


func half_extents() -> Vector2:
	if shape_kind == "circle":
		return Vector2(r, r) * size_scale
	return Vector2(w, h) * 0.5 * size_scale


func bound_radius() -> float:
	return half_extents().length() if shape_kind != "circle" else r * size_scale


func shown_color() -> Color:
	return paint if paint.a > 0.0 else color


func display_name() -> String:
	if def.has("name"):
		return String(def.name)
	return {"wheel": "Wheel", "basket": "Basket", "envelope": "Balloon", "sail": "Sail", "seat": "Seat", "arm": "Arm"}.get(id, id.capitalize())


func hit_test(p: Vector2, pad := 0.0) -> bool:
	var l := to_local(p)
	var he := half_extents()
	if shape_kind == "circle":
		return l.length() <= he.x + pad
	return absf(l.x) <= he.x + pad and absf(l.y) <= he.y + pad


func is_on() -> bool:
	return on or powered or zap_power > 0.0


## Part of a go-kart or monster truck that's switched on (it bowls fighters over).
func driving() -> bool:
	var ride = self if parent_uid == 0 else (world.things.get(parent_uid) if world else null)
	return ride is Toy and String(ride.def.get("build", "")) == "car" and ride.is_on()


func update_freeze() -> void:
	if extra.has("held_by"):
		return   # a fighter is holding it
	var want := nailed or frozen_t > 0.0 or puppet
	if freeze != want:
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC if not puppet else RigidBody2D.FREEZE_MODE_KINEMATIC
		freeze = want
		if want and not puppet:
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0


func make_puppet() -> void:
	puppet = true
	collision_layer = 0
	collision_mask = 0
	contact_monitor = false
	update_freeze()


## Squeezed in a jumble (dropped weapons and limbs in a heap), the physics
## engine now and then "pushes a body out" thousands of pixels in one step,
## and the body, hurtling along, flings everything it hits: a whole heap went
## flying out of the world at once. A body the physics just moved further than
## anything really goes in one step (or to "not a number") is put straight
## back where it was, standing still. `last`: where it was after the last step
## (or where our own code put it since). Returns where it is now, for next time.
static func stop_wild_jump(body: RigidBody2D, s: PhysicsDirectBodyState2D, last: Vector2) -> Vector2:
	var at := s.transform.origin
	if last == Vector2.INF:
		return at
	var most := MAX_SPEED * s.step
	if at.distance_squared_to(last) > most * most or not at.is_finite():
		var rot := s.transform.get_rotation()
		var back := Transform2D(rot if is_finite(rot) else 0.0, last)
		s.transform = back
		# (the body's own copy too: if that's NaN, Godot copies it back over
		# the physics state after this, as NaN never equals itself)
		body.global_transform = back
		s.linear_velocity = Vector2.ZERO
		s.angular_velocity = 0.0
		return last
	if not s.linear_velocity.is_finite() or not is_finite(s.angular_velocity):
		s.linear_velocity = Vector2.ZERO
		s.angular_velocity = 0.0
	return at


func _notification(what: int) -> void:
	# our own code moved it, not the physics (that doesn't send this)
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_last = global_position


func _integrate_forces(s: PhysicsDirectBodyState2D) -> void:
	if not puppet:
		_last = stop_wild_jump(self, s, _last)
	# On the first frame of a contact Godot still reports the velocities from
	# before the bounce, so the closing speed along the normal is exact.
	var n := s.get_contact_count()
	if n == 0:
		_prev_contacts.clear()
		return
	var seen := {}
	for i in n:
		var other_id := s.get_contact_collider_id(i)
		seen[other_id] = true
		if _prev_contacts.has(other_id):
			continue
		var nrm := s.get_contact_local_normal(i)
		var rel := s.get_contact_local_velocity_at_position(i) - s.get_contact_collider_velocity_at_position(i)
		var closing := -rel.dot(nrm)
		if closing > 60.0 and world:
			world.queue_impact("toy", self, s.get_contact_collider_object(i), closing, s.get_contact_local_position(i), nrm)
	_prev_contacts = seen


func _process(_d: float) -> void:
	var key := "%d%d%d|%d|%d|%d|%s|%.2f|%d" % [int(on), int(powered), int(zap_power > 0.0), int(frozen_t > 0.0), int(bubble_t > 0.0),
		int(electric > 0.05), paint.to_html(), size_scale, int(nailed)]
	if fuse >= 0.0:
		key += "f%d" % int(fuse * 8.0)
	if extra.has("art"):
		key += String(extra.art)
	var blink := Art.blink_key(self)
	if blink != 0:
		key += "b%d" % blink
	if key != _art_key:
		_art_key = key
		queue_redraw()
	elif Art.animates(self):
		queue_redraw()   # spinning fans and propellers, flames, blinking lights, sparks


func _draw() -> void:
	Art.draw_toy(self, self)
