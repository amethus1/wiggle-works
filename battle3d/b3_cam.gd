class_name B3Cam
extends Node3D
## Two views:
##  - Overhead (the usual one): an orthographic isometric camera, 35° pitch,
##    45° yaw, smooth 90° turns, zoom toward the cursor, drag/keys to pan.
##  - First person: while playing a fighter or vehicle with 👀 on, a
##    perspective camera sits at its eyes (B3Unit.eye_xform) and the mouse
##    looks around.
## Shake is gentle and slow (the ⚙️ Screen shake rule scales it). Runs on real
## time so it still moves while the battle is paused.

var cam: Camera3D
var focus := Vector3.ZERO
var yaw := 45.0
var yaw_target := 45.0
var pitch := 35.0
var size := 36.0
var dist := 260.0
var trauma := 0.0
var _last_us := 0
var _t := 0.0
var follow: Node3D = null       # a fighter (or anything with center()) to keep in view
var offset_k := 0.17            # keeps things clear of the Toy Box on the left (0 when it's hidden)
var limit := 60.0               # how far the view can pan from the middle (set from the map size)
var max_size := 160.0
var fp_unit: B3Unit = null      # first person: whose eyes we look through
var fp_ctl: B3Ctl = null
var fov := 72.0
var hands: B3FPView = null      # the weapon in your hands in first person
var battle = null
var _hidden_near: Array = []    # fighters right in front of your face (hidden in first person)
const HIDE_LAYER := 1 << 19     # render layer for the body you're looking out of


func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = size
	cam.near = 1.0
	cam.far = 700.0
	cam.cull_mask = 0xFFFFF & ~HIDE_LAYER
	cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(cam)
	cam.make_current()
	_last_us = Time.get_ticks_usec()
	apply()


func real_dt() -> float:
	var now := Time.get_ticks_usec()
	var dt := clampf((now - _last_us) / 1000000.0, 0.0, 0.1)
	_last_us = now
	return dt


func basis_now() -> Basis:
	return Basis.from_euler(Vector3(deg_to_rad(-pitch), deg_to_rad(yaw), 0.0))


func first_person() -> bool:
	return fp_unit != null and is_instance_valid(fp_unit) and fp_ctl != null


## The ground point in the middle of what you're looking at.
func view_center() -> Vector3:
	if first_person():
		return fp_unit.global_position
	return focus


## In first person, things this close would fill the view (health bars hide).
func too_close(p: Vector3) -> bool:
	return first_person() and fp_unit.global_position.distance_squared_to(p) < 30.0


## Looks out of `u`'s eyes (null goes back to the overhead view).
func set_first_person(u: B3Unit, c: B3Ctl) -> void:
	if fp_unit != null and is_instance_valid(fp_unit):
		_show_body(fp_unit, true)
	fp_unit = u
	fp_ctl = c
	if hands:
		hands.queue_free()
		hands = null
	if u != null:
		hands = B3FPView.new()
		cam.add_child(hands)
		hands.setup(u)
		_show_body(u, false)
		cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		cam.fov = fov
		cam.near = 0.08
		cam.far = 900.0
	else:
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.near = 1.0
		cam.far = 700.0
	apply()


## Puts a fighter's body on a layer the first-person camera doesn't draw, so
## you don't see the inside of your own head.
func _show_body(u: Node, on: bool) -> void:
	if not is_instance_valid(u):
		return
	for c in u.find_children("*", "VisualInstance3D", true, false):
		var vi := c as VisualInstance3D
		if _keep(vi, u):
			continue      # a car's bonnet or a plane's cockpit frame stays in view
		if on:
			if vi.has_meta("fp_layers"):
				vi.layers = int(vi.get_meta("fp_layers"))
				vi.remove_meta("fp_layers")
		else:
			if not vi.has_meta("fp_layers"):
				vi.set_meta("fp_layers", vi.layers)
			vi.layers = HIDE_LAYER


## True if `n` or a parent (up to the unit) has the "fp_keep" meta.
func _keep(n: Node, top: Node) -> bool:
	while n != null and n != top:
		if n.has_meta("fp_keep"):
			return true
		n = n.get_parent()
	return false


func apply() -> void:
	if first_person():
		var xf: Transform3D = fp_unit.eye_xform(fp_ctl)
		if trauma > 0.0:
			var a := trauma * trauma * 0.035 * B3Rules.shake_k()
			xf.basis = xf.basis * Basis.from_euler(Vector3(sin(_t * 13.0) * a, sin(_t * 9.0 + 1.0) * a, 0.0))
		cam.global_transform = xf
		return
	var b := basis_now()
	var off := b * Vector3(0, 0, dist)
	var sh := Vector3.ZERO
	if trauma > 0.0:
		var s := trauma * trauma * (0.25 + size * 0.012) * B3Rules.shake_k()
		# slow, smooth wobble (not a fast jitter)
		sh = (b.x * (sin(_t * 17.0) + sin(_t * 7.3) * 0.5) + b.y * (cos(_t * 13.0) + cos(_t * 5.9) * 0.5)) * s
	cam.global_transform = Transform3D(b, focus + off + sh)
	cam.size = size


func _process(_d: float) -> void:
	var dt := real_dt()
	_t += dt
	if absf(yaw_target - yaw) > 0.01:
		yaw += (yaw_target - yaw) * minf(1.0, dt * 9.0)
	trauma = maxf(0.0, trauma - dt * 2.2)
	if fp_ctl != null and not first_person():
		set_first_person(null, null)      # the fighter we were looking out of is gone
	if first_person():
		var p := fp_unit.global_position
		focus = Vector3(p.x, 0, p.z)
		_hide_near(p)
	elif not _hidden_near.is_empty():
		_hide_near(Vector3(INF, 0, INF))
	elif follow != null:
		if not is_instance_valid(follow) or follow.is_queued_for_deletion():
			follow = null
		else:
			var p: Vector3 = follow.center() if follow.has_method("center") else follow.global_position
			var b := basis_now()
			var right := Vector3(b.x.x, 0, b.x.z).normalized()
			# slide along the view ray down to the ground, so planes and dragons up high stay mid-screen
			var d := -b.z
			if absf(d.y) > 0.05:
				p -= d * (p.y / d.y)
			var goal := Vector3(p.x, 0, p.z) - right * size * offset_k
			focus = focus.lerp(goal, minf(1.0, dt * 4.0))
			_clamp()
	apply()


## In first person, a teammate standing in your face would fill the whole
## view, so fighters within an arm's length are hidden until they move away.
func _hide_near(at: Vector3) -> void:
	var keep: Array = []
	if battle != null and at.x != INF:
		for u: B3Unit in battle.units:
			if u == fp_unit or u.rig == null or u is B3Vehicle:
				continue
			var d := Vector2(u.position.x - at.x, u.position.z - at.z).length()
			if d < 1.1 + u.radius and absf(u.position.y - at.y) < 2.5:
				keep.append(u.rig)
	for r in _hidden_near:
		if is_instance_valid(r) and not keep.has(r):
			(r as Node3D).visible = true
	for r in keep:
		(r as Node3D).visible = false
	_hidden_near = keep


func shake(a: float) -> void:
	trauma = clampf(trauma + a * 0.7, 0.0, 1.0)


func rotate_view(dir: float) -> void:
	yaw_target += 90.0 * dir


func screen_to_ground(sp: Vector2, y := 0.0) -> Vector3:
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return Vector3(o.x, y, o.z)
	var t := (y - o.y) / d.y
	return o + d * t


func ray(sp: Vector2) -> Array:
	return [cam.project_ray_origin(sp), cam.project_ray_normal(sp)]


func zoom_at(sp: Vector2, factor: float) -> void:
	if first_person():
		return
	var before := screen_to_ground(sp, focus.y)
	size = clampf(size / factor, 9.0, max_size)
	apply()
	var after := screen_to_ground(sp, focus.y)
	focus += Vector3(before.x - after.x, 0, before.z - after.z)
	_clamp()
	apply()


func pan_screen(from: Vector2, to: Vector2) -> void:
	if first_person():
		return
	follow = null
	var a := screen_to_ground(from, focus.y)
	var b := screen_to_ground(to, focus.y)
	focus += Vector3(a.x - b.x, 0, a.z - b.z)
	_clamp()
	apply()


## Keyboard pan: v.x right, v.y down (screen directions), in screens per second.
func pan_keys(v: Vector2, dt: float) -> void:
	follow = null
	var b := basis_now()
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	var fwd := Vector3(-b.z.x, 0, -b.z.z).normalized()
	focus += (right * v.x - fwd * v.y) * size * 1.1 * dt
	_clamp()


## Frames `center` in the free area right of the palette.
func fit(center: Vector3, extent: float) -> void:
	size = clampf(extent, 9.0, max_size)
	var b := basis_now()
	var right := Vector3(b.x.x, 0, b.x.z).normalized()
	focus = Vector3(center.x, 0, center.z) - right * size * offset_k
	_clamp()
	apply()


func screen_pos(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func _clamp() -> void:
	focus.x = clampf(focus.x, -limit, limit)
	focus.z = clampf(focus.z, -limit, limit)
