class_name Wiggly
extends Node2D
## A soft jelly critter: a ring of small bodies pulled back toward its rest
## shape every physics step ("shape matching"), so it squashes, stretches and
## wobbles but always springs back. Has moods, a face, a little AI, a special
## move, and can be played as.

const N := 12
const BASE_R := 34.0

var uid := 0
var world: Node = null
var kind := "bloop"
var def := {}
var size := 1.0
var points: Array = []                 # JellyPoint bodies (host only)
var rest := PackedVector2Array()       # rest offsets for size 1
var pts := PackedVector2Array()        # current outline points (world space)
var com := Vector2.ZERO
var com_vel := Vector2.ZERO
var angle := 0.0
var puppet := false                    # network client copy

# mood & look
var mood := "happy"                    # happy wow scared dizzy sleep strain frozen party
var look := Vector2(1, 0)
var blink_t := 0.0
var idle_t := 0.0
var dizzy_t := 0.0
var scared_t := 0.0
var party_t := 0.0
var t := 0.0
# play state
var paint := Color(0, 0, 0, 0)
var frozen_t := 0.0
var bubble_t := 0.0
var electric := 0.0
var wet := 0.0
var special_t := 0.0                   # sticky / puff time left
var special_cd := 0.0
var pound := false                     # Boulder slamming down
var puff := 1.0                        # Puffy's size multiplier (smoothly animated)
var grabbed_by := {}                   # player id -> true
var player_id := -1                    # who is playing as this Wiggly
var move_input := 0.0
var want_jump := false
var grounded := false
var ground_t := 0.0
var air_t := 0.0
var ai_t := 0.0
var hop_dir := 0.0
var squash_t := 0.0
var stuck_links := 0
var stretch := 1.0
var face_scale := Vector2.ONE
var jumps := 0
var _contacting := {}


func setup(w: Node, wiggly_kind: String, pos: Vector2, s := 1.0) -> void:
	world = w
	kind = wiggly_kind
	def = Catalog.WIGGLIES.get(kind, Catalog.WIGGLIES.bloop)
	size = clampf(s, 0.45, 2.2)
	rest.resize(N)
	pts.resize(N)
	for i in N:
		var a := TAU * float(i) / N
		rest[i] = Vector2(cos(a), sin(a)) * BASE_R
		pts[i] = pos + rest[i] * size
	com = pos
	blink_t = randf_range(1.0, 4.0)
	ai_t = randf_range(0.5, 2.0)
	t = randf() * 10.0
	z_index = 4


func make_bodies(container: Node) -> void:
	var rad := BASE_R * size
	var pr := rad * sin(PI / N) * 1.15 + 1.0
	var pm := PhysicsMaterial.new()
	pm.friction = float(def.fric)
	pm.bounce = float(def.bounce)
	for i in N:
		var p := JellyPoint.new()
		p.wiggly = self
		p.index = i
		p.position = pts[i]
		p.mass = float(def.mass) * size * size
		p.physics_material_override = pm
		p.collision_layer = Toy.LAYER_WIGGLIES
		p.collision_mask = Toy.LAYER_GROUND | Toy.LAYER_TOYS | Toy.LAYER_WIGGLIES
		p.contact_monitor = true
		p.max_contacts_reported = 3
		p.can_sleep = false
		p.lock_rotation = true
		p.linear_damp = 0.05
		var cs := CollisionShape2D.new()
		var c := CircleShape2D.new()
		c.radius = pr
		cs.shape = c
		p.add_child(cs)
		container.add_child(p)
		points.append(p)
	for i in N:
		for j in range(i + 1, N):
			points[i].add_collision_exception_with(points[j])


func free_bodies() -> void:
	for p in points:
		if is_instance_valid(p):
			p.queue_free()
	points.clear()


func radius() -> float:
	return BASE_R * size * puff


func display_name() -> String:
	return String(def.name)


func shown_color() -> Color:
	return paint if paint.a > 0.0 else def.color


func hit_test(p: Vector2, pad := 0.0) -> bool:
	if pts.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(p, pts):
		return true
	return p.distance_to(com) <= radius() + pad


## Index of the outline point closest to `p`.
func nearest_point(p: Vector2) -> int:
	var best := 0
	var bd := INF
	for i in pts.size():
		var d := pts[i].distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best


func set_velocity(v: Vector2) -> void:
	for p in points:
		p.linear_velocity = v


func add_velocity(v: Vector2) -> void:
	for p in points:
		p.linear_velocity += v


func teleport(to: Vector2) -> void:
	var d := to - com
	for p in points:
		p.global_position += d
		p.linear_velocity = Vector2.ZERO
	com = to


func set_frozen(sec: float) -> void:
	frozen_t = sec
	for p in points:
		p.freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		p.freeze = sec > 0.0
	if sec > 0.0:
		mood = "frozen"


func set_bubble(sec: float) -> void:
	bubble_t = sec
	for p in points:
		p.gravity_scale = -0.12 if sec > 0.0 else (-0.25 if kind == "puffy" and special_t > 0.0 else 1.0)
		p.linear_damp = 1.2 if sec > 0.0 else 0.05


# ----------------------------------------------------------------- physics
func physics_step(dt: float) -> void:
	t += dt
	_read_points()
	if frozen_t > 0.0:
		frozen_t -= dt
		if frozen_t <= 0.0:
			set_frozen(0.0)
			mood = "happy"
		return

	# Shape matching: pull every point toward the rest shape, rotated to fit.
	var sc := size * puff
	var sx := 0.0
	var sy := 0.0
	for i in N:
		var q := rest[i] * sc
		var p := pts[i] - com
		sx += q.x * p.y - q.y * p.x
		sy += q.dot(p)
	angle = atan2(sx, sy)
	var stiff := float(def.stiff)
	if pound:
		stiff = 1.0
	var freq := 2.2 + 5.0 * stiff
	var k := pow(TAU * freq, 2.0) * dt
	var c := 2.0 * 0.32 * TAU * freq * dt
	var far := 0.0
	for i in N:
		var target := com + rest[i].rotated(angle) * sc
		var body: JellyPoint = points[i]
		var lv := body.linear_velocity
		var off := target - pts[i]
		body.linear_velocity = lv + off * k - (lv - com_vel) * c
		far = maxf(far, (pts[i] - com).length() / (BASE_R * sc))
	stretch = far

	# what we're touching
	grounded = false
	_contacting.clear()
	for p in points:
		for b in p.get_colliding_bodies():
			if b is JellyPoint and b.wiggly == self:
				continue
			_contacting[b.get_instance_id()] = b
			if (p.global_position - com).dot(world.gravity_dir()) > BASE_R * sc * 0.25:
				grounded = true
	if grounded:
		ground_t += dt
		air_t = 0.0
		if pound:
			_finish_pound()
	else:
		air_t += dt
		ground_t = 0.0

	_timers(dt)
	if bubble_t > 0.0:
		return
	if player_id >= 0:
		_player_control(dt)
	elif grabbed_by.is_empty():
		_ai(dt)
	_mood()


func _read_points() -> void:
	if points.is_empty():
		return
	var s := Vector2.ZERO
	var v := Vector2.ZERO
	for i in N:
		var p: JellyPoint = points[i]
		pts[i] = p.global_position
		s += pts[i]
		v += p.linear_velocity
	com = s / N
	com_vel = v / N


func _timers(dt: float) -> void:
	blink_t -= dt
	if blink_t < -0.12:
		blink_t = randf_range(1.8, 4.5)
	dizzy_t = maxf(0.0, dizzy_t - dt)
	scared_t = maxf(0.0, scared_t - dt)
	party_t = maxf(0.0, party_t - dt)
	special_cd = maxf(0.0, special_cd - dt)
	electric = maxf(0.0, electric - dt)
	wet = maxf(0.0, wet - dt * 0.15)
	if electric > 0.0:
		for p in points:
			p.linear_velocity += Vector2(randf_range(-1, 1), randf_range(-1, 1)) * 900.0 * dt
	if bubble_t > 0.0:
		bubble_t -= dt
		if bubble_t <= 0.0:
			set_bubble(0.0)
			world.fx_event("pop_bubble", {"p": com, "r": radius() * 1.4})
	if special_t > 0.0:
		special_t -= dt
		if special_t <= 0.0:
			_end_special()
	var want_puff := 1.7 if kind == "puffy" and special_t > 0.0 else 1.0
	puff = move_toward(puff, want_puff, dt * 1.6)
	if squash_t > 0.0:
		squash_t -= dt
		for p in points:
			p.linear_velocity += world.gravity_dir() * 520.0 * dt
		if squash_t <= 0.0:
			_launch_hop()
	if absf(com_vel.length()) < 30.0 and grabbed_by.is_empty() and player_id < 0:
		idle_t += dt
	else:
		idle_t = 0.0


var _voice_t := 0.0
var _last_mood := "happy"


func _mood() -> void:
	_set_mood()
	_voice_t = maxf(0.0, _voice_t - 0.016)
	if mood != _last_mood:
		_last_mood = mood
		var voice: String = {"wow": "wee", "scared": "eek", "party": "yay", "dizzy": "dizzy"}.get(mood, "")
		if voice != "" and _voice_t <= 0.0:
			_voice_t = 1.5
			world.fx_event("voice", {"p": com, "v": voice, "s": size})


func _set_mood() -> void:
	if frozen_t > 0.0:
		mood = "frozen"
	elif not grabbed_by.is_empty() and stretch > 1.45:
		mood = "strain"
	elif dizzy_t > 0.0:
		mood = "dizzy"
	elif scared_t > 0.0:
		mood = "scared"
	elif party_t > 0.0:
		mood = "party"
	elif com_vel.length() > 650.0 or (air_t > 0.45 and com_vel.length() > 300.0):
		mood = "wow"
	elif idle_t > 22.0 and player_id < 0:
		mood = "sleep"
	else:
		mood = "happy"


# ---------------------------------------------------------------- movement
func hop(dir: float, power := 1.0) -> void:
	if squash_t > 0.0:
		return
	hop_dir = dir
	squash_t = 0.09
	set_meta("hop_power", power)


func _launch_hop() -> void:
	var power: float = get_meta("hop_power", 1.0)
	var up: Vector2 = -world.gravity_dir()
	if up == Vector2.ZERO:
		up = Vector2.UP
	var v: Vector2 = up * 470.0 * power * (1.25 if kind == "bloop" else 1.0) + Vector2(hop_dir * 190.0 * power, 0)
	if kind == "boulder":
		v *= 0.75
	add_velocity(v)
	world.fx_event("hop", {"p": com + world.gravity_dir() * radius(), "k": kind, "s": size})
	jumps += 1


func _player_control(dt: float) -> void:
	if move_input != 0.0:
		_roll(move_input, dt, 1.0)
	if want_jump:
		want_jump = false
		if grounded or air_t < 0.12:
			hop(move_input * 0.8, 1.15)
			Settings.count("jumps", "player", 10)


func _roll(dir: float, dt: float, strength: float) -> void:
	# Spin the jelly like a wheel (clockwise rolls right), up to a top speed.
	for i in N:
		var d := pts[i] - com
		var tan := Vector2(-d.y, d.x).normalized()
		var body: JellyPoint = points[i]
		if (body.linear_velocity - com_vel).dot(tan) * dir < 520.0:
			body.linear_velocity += tan * dir * 2400.0 * strength * dt
	if not grounded:
		add_velocity(Vector2(dir * 420.0 * dt * strength, 0))


func _ai(dt: float) -> void:
	if mood == "sleep" or electric > 0.0:
		return
	# run away from lit bombs
	var danger = world.nearest_danger(com, 260.0)
	if danger != null:
		scared_t = 0.6
		if grounded and squash_t <= 0.0 and ai_t <= 0.0:
			hop(signf(com.x - danger.x) if com.x != danger.x else 1.0, 1.1)
			ai_t = 0.45
	ai_t -= dt
	if ai_t > 0.0 or not grounded:
		return
	var roll := randf()
	if party_t > 0.0:
		hop(randf_range(-0.4, 0.4), 0.9)
		ai_t = randf_range(0.35, 0.6)
	elif roll < 0.42:
		hop(randf_range(-1.0, 1.0), randf_range(0.5, 0.9))
		ai_t = randf_range(1.2, 3.0)
	elif roll < 0.62:
		var toy = world.nearest_toy(com, 500.0)
		if toy:
			hop(signf(toy.global_position.x - com.x), 0.75)
		ai_t = randf_range(1.5, 3.0)
	else:
		look = Vector2.from_angle(randf_range(-PI, 0.0))
		ai_t = randf_range(0.8, 2.5)


# ----------------------------------------------------------------- specials
func use_special() -> void:
	if special_cd > 0.0 or frozen_t > 0.0:
		return
	special_cd = 1.2
	idle_t = 0.0
	Settings.mark("specials", kind, "special", Catalog.WIGGLY_ORDER.size())
	match kind:
		"bloop":
			var up: Vector2 = -world.gravity_dir() if world.gravity_dir() != Vector2.ZERO else Vector2.UP
			add_velocity(up * 950.0)
			world.fx_event("special", {"p": com, "k": kind, "r": radius()})
		"gummy":
			special_t = 8.0
			world.fx_event("special", {"p": com, "k": kind, "r": radius()})
		"zappy":
			world.zap_area(com, 190.0, self)
		"blaze":
			world.heat_area(com, 170.0, self)
		"frosty":
			world.freeze_area(com, 170.0, 5.0, self)
		"puffy":
			special_t = 5.0
			set_bubble(bubble_t)
			for p in points:
				p.gravity_scale = -0.25
			world.fx_event("special", {"p": com, "k": kind, "r": radius()})
		"boulder":
			pound = true
			add_velocity(world.gravity_dir() * 1500.0 if world.gravity_dir() != Vector2.ZERO else Vector2.DOWN * 1500.0)
			world.fx_event("special", {"p": com, "k": kind, "r": radius()})
		"twinkle":
			var to: Vector2 = world.random_open_spot(com)
			world.fx_event("warp", {"a": com, "b": to, "r": radius()})
			teleport(to)


func _end_special() -> void:
	if kind == "puffy":
		for p in points:
			p.gravity_scale = 1.0


func _finish_pound() -> void:
	pound = false
	world.ground_pound(com, 230.0 * size, self)


func on_point_impact(_p: JellyPoint, other, closing: float, at: Vector2) -> void:
	idle_t = 0.0
	if world:
		world.on_wiggly_impact(self, other, closing, at)
	if closing > 950.0 and kind != "boulder":
		dizzy_t = 2.5
	if kind == "gummy" and special_t > 0.0 and other != null and not (other is JellyPoint and other.wiggly == self):
		world.sticky_touch(self, _p, other, at)


# ------------------------------------------------------------------ drawing
func _process(_d: float) -> void:
	if not puppet:
		_read_points()
	queue_redraw()


func _draw() -> void:
	Art.draw_wiggly(self, self)
