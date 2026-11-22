class_name B3Fx
extends Node3D
## Pooled visual effects: fireballs, smoke, sparks, debris, dust, tracers,
## muzzle flashes, lights, scorch marks, heal pluses, damage numbers, shock
## rings and the nuke's mushroom cloud. Nothing here touches physics.

class Item:
	var node: Node3D
	var kind := ""
	var age := 0.0
	var life := 1.0
	var delay := 0.0
	var size := 1.0
	var vel := Vector3.ZERO
	var f := 0.0

var battle = null
var _items: Array[Item] = []
var _owner := {}          # pooled node -> the Item moving it now (see _add)
var _pools := {}          # name -> Array of nodes
var _next := {}           # name -> int
var _balls: Array[MeshInstance3D] = []
var _ball_i := 0
var _lights: Array[OmniLight3D] = []
var _light_i := 0
var _decals: Array[Decal] = []
var _decal_i := 0
var _labels: Array[Label3D] = []
var _label_i := 0
var _tracers: Array[MeshInstance3D] = []
var _tracer_i := 0
var _muzzles: Array[MeshInstance3D] = []
var _muzzle_i := 0
var _pluses: Array[Node3D] = []
var _plus_i := 0
var _rings: Array[MeshInstance3D] = []
var _ring_i := 0
var _dust: Array[CPUParticles3D] = []
var _num_budget := 0.0
var _beams: Array[MeshInstance3D] = []
var _beam_i := 0


var _fx_depth := 0          # >0 while one effect is making others (only the outer one is sent to friends)

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	for i in 8:
		var bm := MeshInstance3D.new()
		bm.mesh = B3Mats.cyl(0.5, 0.5, 1.0, 10)
		bm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bm.visible = false
		add_child(bm)
		_beams.append(bm)
	for i in 130:
		var b := MeshInstance3D.new()
		b.mesh = B3Mats.sphere(1.0, 12)
		b.material_override = B3Mats.shader_mat("fireball")
		b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		b.visible = false
		add_child(b)
		_balls.append(b)
	for i in 8:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.65, 0.3)
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
	var scorch := GradientTexture2D.new()
	scorch.fill = GradientTexture2D.FILL_RADIAL
	scorch.fill_from = Vector2(0.5, 0.5)
	scorch.fill_to = Vector2(1.0, 0.5)
	scorch.width = 128
	scorch.height = 128
	var g := Gradient.new()
	g.set_color(0, Color(0.05, 0.04, 0.03, 0.85))
	g.set_color(1, Color(0.1, 0.08, 0.06, 0.0))
	g.add_point(0.55, Color(0.08, 0.06, 0.05, 0.6))
	scorch.gradient = g
	for i in 40:
		var d := Decal.new()
		d.texture_albedo = scorch
		d.cull_mask = 2
		d.visible = false
		d.upper_fade = 0.2
		d.lower_fade = 0.3
		add_child(d)
		_decals.append(d)
	for i in 28:
		var l := Label3D.new()
		l.font = B3Mats.get_font()
		l.font_size = 64
		l.outline_size = 14
		l.pixel_size = 0.006
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color("ffe066")
		l.outline_modulate = Color(0.15, 0.05, 0.1)
		l.visible = false
		l.render_priority = 5
		l.outline_render_priority = 4
		add_child(l)
		_labels.append(l)
	for i in 72:
		var t := MeshInstance3D.new()
		t.mesh = B3Mats.box(Vector3(1, 1, 1))
		t.material_override = B3Mats.glow(Color(1.0, 0.85, 0.4), 4.0)
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		t.visible = false
		add_child(t)
		_tracers.append(t)
	for i in 24:
		var m := MeshInstance3D.new()
		m.mesh = B3Mats.sphere(0.5, 8)
		m.material_override = B3Mats.glow(Color(1.0, 0.75, 0.3), 5.0)
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.visible = false
		add_child(m)
		_muzzles.append(m)
	for i in 24:
		var p := Node3D.new()
		var gm := B3Mats.glow(Color(0.35, 1.0, 0.45), 2.2)
		B3Mats.add(p, B3Mats.box(Vector3(0.24, 0.07, 0.07)), gm, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		B3Mats.add(p, B3Mats.box(Vector3(0.07, 0.24, 0.07)), gm, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		p.visible = false
		add_child(p)
		_pluses.append(p)
	for i in 8:
		var r := MeshInstance3D.new()
		r.mesh = B3Mats.torus(0.92, 1.0)
		r.material_override = B3Mats.shader_mat("ring")
		r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		r.visible = false
		add_child(r)
		_rings.append(r)
	_make_pool("smoke", 12)
	_make_pool("sparks", 12)
	_make_pool("debris", 10)
	_make_pool("poof", 10)
	_make_pool("dust", 10)
	_make_pool("steam", 8)
	_make_pool("hit", 14)


# --------------------------------------------------------------- particles
func _curve(a: float, b: float, c: float) -> Curve:
	var cv := Curve.new()
	cv.max_value = maxf(1.0, maxf(a, maxf(b, c)))
	cv.add_point(Vector2(0, a))
	cv.add_point(Vector2(0.3, b))
	cv.add_point(Vector2(1, c))
	return cv


func _ramp(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0]) if cols.size() == 3 else PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray(cols)
	return g


## CPU particles: few per burst, and they clean up nicely.
func make_particles(kind: String) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.explosiveness = 0.95
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.direction = Vector3.UP
	match kind:
		"smoke":
			p.amount = 12
			p.lifetime = 2.2
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 1.2
			p.spread = 75.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 4.5
			p.gravity = Vector3(0, 1.4, 0)
			p.damping_min = 1.0
			p.damping_max = 2.5
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.3
			p.scale_amount_curve = _curve(0.5, 1.0, 1.3)
			p.color_ramp = _ramp([Color(0.3, 0.27, 0.26, 0.8), Color(0.55, 0.53, 0.5, 0.5), Color(0.75, 0.75, 0.75, 0.0)])
			p.mesh = B3Mats.sphere(0.6, 8)
			p.material_override = B3Mats.vcol(false, true)
		"steam":
			p.amount = 10
			p.lifetime = 1.6
			p.explosiveness = 0.6
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.6
			p.spread = 30.0
			p.initial_velocity_min = 1.0
			p.initial_velocity_max = 2.5
			p.gravity = Vector3(0, 1.0, 0)
			p.scale_amount_min = 0.4
			p.scale_amount_max = 0.9
			p.scale_amount_curve = _curve(0.4, 1.0, 1.5)
			p.color_ramp = _ramp([Color(0.9, 0.9, 0.9, 0.7), Color(0.8, 0.8, 0.8, 0.0)])
			p.mesh = B3Mats.sphere(0.5, 8)
			p.material_override = B3Mats.vcol(false, true)
		"poof":
			p.amount = 12
			p.lifetime = 0.9
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.5
			p.spread = 180.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 3.5
			p.damping_min = 3.0
			p.damping_max = 5.0
			p.gravity = Vector3(0, 0.5, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.0
			p.scale_amount_curve = _curve(0.6, 1.0, 0.2)
			p.color_ramp = _ramp([Color(1, 1, 1, 0.95), Color(0.95, 0.95, 0.95, 0.0)])
			p.mesh = B3Mats.sphere(0.4, 8)
			p.material_override = B3Mats.vcol(false, true)
		"dust":
			p.amount = 16
			p.lifetime = 1.1
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
			p.emission_ring_axis = Vector3.UP
			p.emission_ring_radius = 1.0
			p.emission_ring_inner_radius = 0.7
			p.emission_ring_height = 0.1
			p.spread = 30.0
			p.initial_velocity_min = 0.5
			p.initial_velocity_max = 1.5
			p.radial_accel_min = 5.0
			p.radial_accel_max = 9.0
			p.damping_min = 3.0
			p.damping_max = 4.0
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.1
			p.scale_amount_curve = _curve(0.5, 1.0, 1.3)
			p.color_ramp = _ramp([Color(0.75, 0.68, 0.55, 0.8), Color(0.75, 0.7, 0.6, 0.0)])
			p.mesh = B3Mats.sphere(0.45, 8)
			p.material_override = B3Mats.vcol(false, true)
		"sparks", "hit":
			p.amount = 26 if kind == "sparks" else 7
			p.lifetime = 0.9 if kind == "sparks" else 0.35
			p.spread = 80.0 if kind == "sparks" else 60.0
			p.initial_velocity_min = 7.0 if kind == "sparks" else 3.0
			p.initial_velocity_max = 18.0 if kind == "sparks" else 7.0
			p.gravity = Vector3(0, -14, 0)
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.2
			p.color_ramp = _ramp([Color(6.0, 4.5, 1.6, 1.0), Color(3.0, 0.9, 0.15, 1.0), Color(0.3, 0.1, 0.05, 0.0)])
			p.particle_flag_align_y = true
			p.mesh = B3Mats.box(Vector3(0.05, 0.35, 0.05))
			p.material_override = B3Mats.vcol(true, true)
		"debris":
			p.amount = 14
			p.lifetime = 1.4
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 0.8
			p.spread = 55.0
			p.initial_velocity_min = 5.0
			p.initial_velocity_max = 12.0
			p.gravity = Vector3(0, -18, 0)
			p.angular_velocity_min = -540.0
			p.angular_velocity_max = 540.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
			p.scale_amount_curve = _curve(1.0, 1.0, 0.0)
			p.color_ramp = _ramp([Color(0.45, 0.36, 0.28), Color(0.4, 0.38, 0.36)])
			p.mesh = B3Mats.box(Vector3(0.22, 0.22, 0.22))
			p.material_override = B3Mats.vcol()
		"fire":
			p.one_shot = false
			p.explosiveness = 0.0
			p.amount = 40
			p.lifetime = 0.9
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 1.0
			p.spread = 15.0
			p.initial_velocity_min = 1.5
			p.initial_velocity_max = 3.5
			p.gravity = Vector3(0, 2.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.1
			p.scale_amount_curve = _curve(0.6, 1.0, 0.1)
			p.color_ramp = _ramp([Color(5.0, 3.2, 0.8, 1.0), Color(3.0, 0.8, 0.1, 0.9), Color(0.3, 0.25, 0.2, 0.0)])
			p.mesh = B3Mats.sphere(0.35, 8)
			p.material_override = B3Mats.vcol(true, true)
		"bubbles":
			p.one_shot = false
			p.explosiveness = 0.0
			p.amount = 14
			p.lifetime = 1.4
			p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 1.0
			p.spread = 10.0
			p.initial_velocity_min = 0.2
			p.initial_velocity_max = 0.6
			p.gravity = Vector3.ZERO
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.2
			p.scale_amount_curve = _curve(0.2, 1.0, 0.0)
			p.mesh = B3Mats.sphere(0.18, 8)
	return p


func _make_pool(n: String, count: int) -> void:
	var arr: Array[CPUParticles3D] = []
	for i in count:
		var p := make_particles(n)
		add_child(p)
		arr.append(p)
	_pools[n] = arr
	_next[n] = 0


func _emit(n: String, pos: Vector3, s := 1.0) -> void:
	var arr: Array[CPUParticles3D] = _pools[n]
	var i: int = _next[n]
	_next[n] = (i + 1) % arr.size()
	var p := arr[i]
	p.global_position = pos
	p.scale = Vector3.ONE * s
	p.restart()
	p.emitting = true


func set_dust_color(c: Color) -> void:
	var g := _ramp([Color(c, 0.8), Color(c, 0.0)])
	for p: CPUParticles3D in _pools.get("dust", []):
		p.color_ramp = g


## Starts animating `it`. Pools hand out their nodes in turn, so a busy
## battle can reuse a node while an older effect is still moving it: that
## older effect just stops (it would otherwise fight over the node and hide
## the new effect when it ends).
func _add(it: Item) -> void:
	var old: Item = _owner.get(it.node)
	if old != null:
		old.node = null
	_owner[it.node] = it
	_items.append(it)


# ------------------------------------------------------------------ public
func _fx_explosion(pos: Vector3, r: float, kind := 0) -> void:
	# kind 0 fire, 1 acid, 2 nuke-white
	var main_s := r * 0.55
	_ball(pos + Vector3(0, r * 0.15, 0), main_s * 0.25, main_s, 0.75 + r * 0.03, 0.0, kind)
	var n := 5 if r > 3.0 else 3
	for i in n:
		var off := Vector3(randf_range(-1, 1), randf_range(0.1, 0.9), randf_range(-1, 1)) * r * 0.45
		_ball(pos + off, r * 0.1, r * randf_range(0.25, 0.4), randf_range(0.5, 0.8), randf_range(0.0, 0.12), kind)
	_emit("smoke", pos + Vector3(0, r * 0.2, 0), r / 4.0)
	_emit("sparks", pos + Vector3(0, 0.3, 0), clampf(r / 4.0, 0.6, 2.5))
	_emit("debris", pos + Vector3(0, 0.3, 0), clampf(r / 4.0, 0.6, 2.5))
	_emit("dust", pos + Vector3(0, 0.2, 0), r * 0.6)
	light(pos + Vector3(0, r * 0.5, 0), r * 3.5, 10.0 if kind != 1 else 6.0, 0.4, Color(1.0, 0.6, 0.25) if kind != 1 else Color(0.4, 1.0, 0.3))
	scorch(pos, r * 1.5)
	if r >= 4.5:
		ring(pos + Vector3(0, 0.4, 0), r * 0.4, r * 2.4, 0.45, Color(1.0, 0.9, 0.7, 0.7))


func _ball(pos: Vector3, s0: float, s1: float, life: float, delay: float, kind := 0) -> void:
	var b := _balls[_ball_i]
	_ball_i = (_ball_i + 1) % _balls.size()
	b.global_position = pos
	b.scale = Vector3.ONE * maxf(0.01, s0)
	b.visible = delay <= 0.0
	b.set_instance_shader_parameter("age", 0.0)
	b.set_instance_shader_parameter("kind", float(kind))
	var it := Item.new()
	it.node = b
	it.kind = "ball"
	it.life = life
	it.delay = delay
	it.size = s1
	it.f = s0
	_add(it)


func _fx_flame(pos: Vector3) -> void:
	var b := _balls[_ball_i]
	_ball_i = (_ball_i + 1) % _balls.size()
	b.global_position = pos
	b.scale = Vector3.ONE * 0.12
	b.visible = true
	b.set_instance_shader_parameter("age", 0.1)
	b.set_instance_shader_parameter("kind", 0.0)
	var it := Item.new()
	it.node = b
	it.kind = "flame"
	it.life = 0.5
	it.size = randf_range(0.18, 0.32)
	it.vel = Vector3(randf_range(-0.3, 0.3), 2.2, randf_range(-0.3, 0.3))
	_add(it)


func _fx_trail(pos: Vector3, s := 0.25) -> void:
	var b := _balls[_ball_i]
	_ball_i = (_ball_i + 1) % _balls.size()
	b.global_position = pos
	b.scale = Vector3.ONE * s * 0.5
	b.visible = true
	b.set_instance_shader_parameter("age", 0.0)
	b.set_instance_shader_parameter("kind", 3.0)
	var it := Item.new()
	it.node = b
	it.kind = "trail"
	it.life = 0.9
	it.size = s
	it.vel = Vector3(randf_range(-0.2, 0.2), 0.5, randf_range(-0.2, 0.2))
	_add(it)


func _fx_light(pos: Vector3, rng: float, energy: float, life: float, col := Color(1.0, 0.6, 0.25)) -> void:
	var l := _lights[_light_i]
	_light_i = (_light_i + 1) % _lights.size()
	l.global_position = pos
	l.omni_range = rng
	l.light_energy = energy
	l.light_color = col
	l.visible = true
	var it := Item.new()
	it.node = l
	it.kind = "light"
	it.life = life
	it.f = energy
	_add(it)


func _fx_scorch(pos: Vector3, size: float) -> void:
	var d := _decals[_decal_i]
	_decal_i = (_decal_i + 1) % _decals.size()
	d.global_position = pos
	d.size = Vector3(size, 3.0, size)
	d.rotation.y = randf() * TAU
	d.visible = true
	d.modulate = Color(1, 1, 1, 1)


func _fx_ring(pos: Vector3, r0: float, r1: float, life: float, tint := Color(1, 0.9, 0.7, 0.8)) -> void:
	var r := _rings[_ring_i]
	_ring_i = (_ring_i + 1) % _rings.size()
	r.global_position = pos
	r.scale = Vector3(r0, r0 * 0.6, r0)
	r.visible = true
	r.set_instance_shader_parameter("age", 0.0)
	r.set_instance_shader_parameter("tint", tint)
	var it := Item.new()
	it.node = r
	it.kind = "ring"
	it.life = life
	it.f = r0
	it.size = r1
	_add(it)


func _fx_tracer(a: Vector3, b: Vector3, col: Color, life := 0.06) -> void:
	var l := a.distance_to(b)
	if l < 0.05:
		return
	var t := _tracers[_tracer_i]
	_tracer_i = (_tracer_i + 1) % _tracers.size()
	var dir := (b - a) / l
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	t.global_transform = Transform3D(Basis.looking_at(dir, up), (a + b) * 0.5)
	t.scale = Vector3(0.05, 0.05, l)
	t.material_override = B3Mats.glow(Color(col.r, col.g, col.b) / maxf(1.0, maxf(col.r, maxf(col.g, col.b))), maxf(col.r, maxf(col.g, col.b)))
	t.visible = true
	var it := Item.new()
	it.node = t
	it.kind = "tracer"
	it.life = life
	it.size = l
	_add(it)
	hit_puff(b, -dir)


## A fat glowing laser beam (robots) that thins out over `life` seconds.
func _fx_beam(a: Vector3, b: Vector3, col: Color, width := 0.16, life := 0.18) -> void:
	var l := a.distance_to(b)
	if l < 0.05:
		return
	var m := _beams[_beam_i]
	_beam_i = (_beam_i + 1) % _beams.size()
	var dir := (b - a) / l
	var ref := Vector3.RIGHT if absf(dir.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	m.global_transform = Transform3D(Basis(x * width, dir * l, z * width), (a + b) * 0.5)
	var mx := maxf(1.0, maxf(col.r, maxf(col.g, col.b)))
	var base := Color(col.r / mx, col.g / mx, col.b / mx)
	m.material_override = B3Mats.glow(Color(base, 0.9), mx)
	m.visible = true
	var it := Item.new()
	it.node = m
	it.kind = "beam"
	it.life = life
	it.size = l
	it.f = width
	_add(it)
	_emit("sparks", b, 0.6)
	light(a.lerp(b, 0.5), minf(l, 14.0), 4.0, life, base)


## One puff of dragon fire: flies along `vel`, growing and fading.
func _fx_breath(pos: Vector3, vel: Vector3, size := 0.5, life := 0.6) -> void:
	var b := _balls[_ball_i]
	_ball_i = (_ball_i + 1) % _balls.size()
	b.global_position = pos
	b.scale = Vector3.ONE * size * 0.3
	b.visible = true
	b.set_instance_shader_parameter("age", 0.0)
	b.set_instance_shader_parameter("kind", 0.0)
	var it := Item.new()
	it.node = b
	it.kind = "breath"
	it.life = life
	it.size = size
	it.vel = vel
	_add(it)


func _fx_hit_puff(pos: Vector3, _n: Vector3) -> void:
	_emit("hit", pos, 0.7)


func _fx_muzzle(pos: Vector3, dir: Vector3, s := 1.0) -> void:
	var m := _muzzles[_muzzle_i]
	_muzzle_i = (_muzzle_i + 1) % _muzzles.size()
	m.global_position = pos + dir * 0.12 * s
	m.scale = Vector3(0.25, 0.25, 0.45) * s
	var up := Vector3.UP if absf(dir.y) < 0.98 else Vector3.RIGHT
	m.global_basis = Basis.looking_at(dir, up).scaled(Vector3(0.25, 0.25, 0.5) * s)
	m.visible = true
	var it := Item.new()
	it.node = m
	it.kind = "muzzle"
	it.life = 0.05
	_add(it)


func _fx_sparks(pos: Vector3, _n := 10) -> void:
	_emit("hit", pos, 1.0)


func _fx_poof(pos: Vector3, s := 1.0) -> void:
	_emit("poof", pos, s)


func _fx_dust(pos: Vector3, r: float) -> void:
	_emit("dust", pos + Vector3(0, 0.15, 0), maxf(0.4, r * 0.6))


func _fx_steam(pos: Vector3, s := 1.0) -> void:
	_emit("steam", pos, s)


func _fx_heal(pos: Vector3) -> void:
	var p := _pluses[_plus_i]
	_plus_i = (_plus_i + 1) % _pluses.size()
	p.global_position = pos
	p.visible = true
	p.scale = Vector3.ONE
	var it := Item.new()
	it.node = p
	it.kind = "plus"
	it.life = 0.9
	_add(it)


func _fx_number(pos: Vector3, v: float) -> void:
	if _num_budget > 6.0:
		return
	_num_budget += 1.0
	var l := _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	l.text = str(int(round(v)))
	var big := v >= 40.0
	l.font_size = 80 if big else 56
	l.modulate = Color("ff8a5c") if big else Color("ffe066")
	l.global_position = pos + Vector3(randf_range(-0.3, 0.3), 0, randf_range(-0.3, 0.3))
	l.visible = true
	var it := Item.new()
	it.node = l
	it.kind = "num"
	it.life = 0.9
	_add(it)


## A cartoon word that pops up and floats away ("HONK!", "BONK!").
func _fx_word(pos: Vector3, text: String, col: Color) -> void:
	if _num_budget > 6.0:
		return
	_num_budget += 1.0
	var l := _labels[_label_i]
	_label_i = (_label_i + 1) % _labels.size()
	l.text = text
	l.font_size = 72
	l.modulate = col
	l.global_position = pos + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))
	l.visible = true
	var it := Item.new()
	it.node = l
	it.kind = "num"
	it.life = 0.8
	_add(it)


func _fx_splash(pos: Vector3, acid: bool) -> void:
	for i in 4:
		var off := Vector3(randf_range(-0.6, 0.6), randf_range(0.0, 0.4), randf_range(-0.6, 0.6))
		_ball(pos + off, 0.1, randf_range(0.3, 0.55), 0.5, randf_range(0.0, 0.1), 1 if acid else 0)
	_emit("steam", pos, 1.0)


# -------------------------------------------------------------------- nuke
func _fx_nuke(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var fire := MeshInstance3D.new()
	fire.mesh = B3Mats.sphere(1.0, 20)
	fire.material_override = B3Mats.shader_mat("fireball")
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	fire.set_instance_shader_parameter("kind", 2.0)
	fire.name = "Fire"
	root.add_child(fire)
	var cm := B3Mats.shader_mat("cloud")
	var stem := MeshInstance3D.new()
	stem.mesh = B3Mats.cyl(0.8, 1.1, 1.0, 16)
	stem.material_override = cm
	stem.name = "Stem"
	root.add_child(stem)
	var cap := Node3D.new()
	cap.name = "Cap"
	root.add_child(cap)
	for i in 9:
		var s := MeshInstance3D.new()
		s.mesh = B3Mats.sphere(1.0, 14)
		s.material_override = cm
		var a := TAU * i / 8.0
		if i == 8:
			s.position = Vector3(0, 0.55, 0)
			s.scale = Vector3(1.0, 0.75, 1.0) * 1.15
		else:
			s.position = Vector3(cos(a) * 0.95, randf_range(-0.1, 0.15), sin(a) * 0.95)
			s.scale = Vector3.ONE * randf_range(0.7, 0.9)
		cap.add_child(s)
	var skirt := MeshInstance3D.new()
	skirt.mesh = B3Mats.torus(0.6, 1.0)
	skirt.material_override = cm
	skirt.name = "Skirt"
	root.add_child(skirt)
	var l := OmniLight3D.new()
	l.light_color = Color(1.0, 0.85, 0.6)
	l.omni_range = 90.0
	l.light_energy = 30.0
	l.name = "Light"
	root.add_child(l)
	var it := Item.new()
	it.node = root
	it.kind = "nuke"
	it.life = 9.0
	_add(it)
	ring(pos + Vector3(0, 0.6, 0), 2.0, 58.0, 1.5, Color(1.0, 0.95, 0.85, 0.9))
	ring(pos + Vector3(0, 3.0, 0), 1.0, 40.0, 2.2, Color(1.0, 0.7, 0.4, 0.6))
	for i in 6:
		var a := TAU * i / 6.0
		_emit("smoke", pos + Vector3(cos(a), 0.2, sin(a)) * 9.0, 3.5)
		_emit("debris", pos + Vector3(cos(a), 0.2, sin(a)) * 6.0, 3.0)
	_emit("sparks", pos, 4.0)
	_emit("dust", pos, 14.0)
	scorch(pos, 34.0)


func _nuke_update(it: Item) -> void:
	var a := it.age
	var root := it.node
	var fire: MeshInstance3D = root.get_node("Fire")
	var stem: MeshInstance3D = root.get_node("Stem")
	var cap: Node3D = root.get_node("Cap")
	var skirt: MeshInstance3D = root.get_node("Skirt")
	var l: OmniLight3D = root.get_node("Light")
	var grow := smoothstep(0.0, 0.6, a)
	fire.scale = Vector3.ONE * (2.0 + 11.0 * grow)
	fire.position.y = 3.0 + 8.0 * smoothstep(0.3, 3.0, a)
	fire.set_instance_shader_parameter("age", clampf(a / 2.4, 0.0, 1.0))
	fire.visible = a < 2.4
	l.light_energy = 30.0 * maxf(0.0, 1.0 - a / 1.6)
	var rise := smoothstep(0.4, 4.5, a)
	var top := 5.0 + 17.0 * rise
	stem.scale = Vector3(2.4 + rise * 1.2, top, 2.4 + rise * 1.2)
	stem.position.y = top * 0.5
	cap.position.y = top + 1.0
	cap.scale = Vector3.ONE * (3.0 + 6.5 * smoothstep(0.3, 5.0, a))
	skirt.scale = Vector3(4.0 + 10.0 * smoothstep(0.2, 3.0, a), 3.0, 4.0 + 10.0 * smoothstep(0.2, 3.0, a))
	skirt.position.y = 0.8
	var heat := clampf(1.0 - a / 3.5, 0.0, 1.0)
	var fade := clampf((it.life - a) / 2.2, 0.0, 1.0)
	var parts: Array[MeshInstance3D] = [stem, skirt]
	for c in cap.get_children():
		parts.append(c as MeshInstance3D)
	for p in parts:
		p.set_instance_shader_parameter("heat", heat)
		p.set_instance_shader_parameter("fade", fade)
	cap.rotation.y += 0.002


# ------------------------------------------------------------------ update
func _process(dt: float) -> void:
	_num_budget = maxf(0.0, _num_budget - dt * 10.0)
	if dt <= 0.0:
		return
	var i := 0
	while i < _items.size():
		var it := _items[i]
		if it.node == null:
			# its node was taken by a newer effect
			_items[i] = _items[_items.size() - 1]
			_items.pop_back()
			continue
		if it.delay > 0.0:
			it.delay -= dt
			if it.delay <= 0.0:
				it.node.visible = true
			i += 1
			continue
		it.age += dt
		var k := clampf(it.age / it.life, 0.0, 1.0)
		var done := it.age >= it.life
		match it.kind:
			"ball":
				var s := lerpf(it.f, it.size, 1.0 - pow(1.0 - minf(1.0, k * 2.5), 3.0))
				it.node.scale = Vector3.ONE * s
				it.node.position.y += dt * 0.8 * it.size * 0.3
				(it.node as MeshInstance3D).set_instance_shader_parameter("age", k)
			"flame", "trail":
				it.node.position += it.vel * dt
				it.node.scale = Vector3.ONE * it.size * (0.5 + k * (0.8 if it.kind == "trail" else 0.3))
				(it.node as MeshInstance3D).set_instance_shader_parameter("age", k if it.kind == "trail" else 0.1 + k * 0.9)
			"light":
				(it.node as OmniLight3D).light_energy = it.f * (1.0 - k) * (1.0 - k)
			"tracer":
				var w := 0.05 * (1.0 - k)
				it.node.scale = Vector3(w, w, it.size)
			"beam":
				var bw := it.f * (1.0 - k * k)
				var bb := it.node.global_basis
				it.node.global_basis = Basis(bb.x.normalized() * bw, bb.y, bb.z.normalized() * bw)
			"breath":
				it.node.position += it.vel * dt
				it.vel *= maxf(0.0, 1.0 - dt * 0.8)
				it.vel.y += dt * 1.5
				it.node.scale = Vector3.ONE * it.size * (0.3 + k * 1.5)
				(it.node as MeshInstance3D).set_instance_shader_parameter("age", 0.2 + k * 0.8)
			"muzzle":
				pass
			"plus":
				it.node.position.y += dt * 1.2
				it.node.scale = Vector3.ONE * (1.0 - k * 0.6)
			"num":
				it.node.position.y += dt * 1.6
				(it.node as Label3D).modulate.a = 1.0 - k * k
				(it.node as Label3D).outline_modulate.a = 1.0 - k * k
			"ring":
				var r := lerpf(it.f, it.size, 1.0 - pow(1.0 - k, 2.5))
				it.node.scale = Vector3(r, maxf(0.3, r * 0.04), r)
				(it.node as MeshInstance3D).set_instance_shader_parameter("age", k)
			"nuke":
				_nuke_update(it)
		if done:
			_owner.erase(it.node)
			if it.kind == "nuke":
				it.node.queue_free()
			else:
				it.node.visible = false
			_items[i] = _items[_items.size() - 1]
			_items.pop_back()
			continue
		i += 1


func clear() -> void:
	for it in _items:
		if it.node == null:
			continue
		if it.kind == "nuke":
			it.node.queue_free()
		else:
			it.node.visible = false
	_items.clear()
	_owner.clear()
	for d in _decals:
		d.visible = false


# ------------------------------------------------- shared with friends (👥)
## Each effect below is recorded for friends' screens (B3Net) and then made.

func explosion(pos: Vector3, r: float, kind := 0) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["explosion", pos, r, kind])
	_fx_depth += 1
	_fx_explosion(pos, r, kind)
	_fx_depth -= 1


func flame(pos: Vector3) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["flame", pos])
	_fx_depth += 1
	_fx_flame(pos)
	_fx_depth -= 1


func trail(pos: Vector3, s := 0.25) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["trail", pos, s])
	_fx_depth += 1
	_fx_trail(pos, s)
	_fx_depth -= 1


func light(pos: Vector3, rng: float, energy: float, life: float, col := Color(1.0, 0.6, 0.25)) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["light", pos, rng, energy, life, col])
	_fx_depth += 1
	_fx_light(pos, rng, energy, life, col)
	_fx_depth -= 1


func scorch(pos: Vector3, size: float) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["scorch", pos, size])
	_fx_depth += 1
	_fx_scorch(pos, size)
	_fx_depth -= 1


func ring(pos: Vector3, r0: float, r1: float, life: float, tint := Color(1, 0.9, 0.7, 0.8)) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["ring", pos, r0, r1, life, tint])
	_fx_depth += 1
	_fx_ring(pos, r0, r1, life, tint)
	_fx_depth -= 1


func tracer(a: Vector3, b: Vector3, col: Color, life := 0.06) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["tracer", a, b, col, life])
	_fx_depth += 1
	_fx_tracer(a, b, col, life)
	_fx_depth -= 1


func beam(a: Vector3, b: Vector3, col: Color, width := 0.16, life := 0.18) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["beam", a, b, col, width, life])
	_fx_depth += 1
	_fx_beam(a, b, col, width, life)
	_fx_depth -= 1


func breath(pos: Vector3, vel: Vector3, size := 0.5, life := 0.6) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["breath", pos, vel, size, life])
	_fx_depth += 1
	_fx_breath(pos, vel, size, life)
	_fx_depth -= 1


func hit_puff(pos: Vector3, _n: Vector3) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["hit_puff", pos, _n])
	_fx_depth += 1
	_fx_hit_puff(pos, _n)
	_fx_depth -= 1


func muzzle(pos: Vector3, dir: Vector3, s := 1.0) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["muzzle", pos, dir, s])
	_fx_depth += 1
	_fx_muzzle(pos, dir, s)
	_fx_depth -= 1


func sparks(pos: Vector3, _n := 10) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["sparks", pos, _n])
	_fx_depth += 1
	_fx_sparks(pos, _n)
	_fx_depth -= 1


func poof(pos: Vector3, s := 1.0) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["poof", pos, s])
	_fx_depth += 1
	_fx_poof(pos, s)
	_fx_depth -= 1


func dust(pos: Vector3, r: float) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["dust", pos, r])
	_fx_depth += 1
	_fx_dust(pos, r)
	_fx_depth -= 1


func steam(pos: Vector3, s := 1.0) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["steam", pos, s])
	_fx_depth += 1
	_fx_steam(pos, s)
	_fx_depth -= 1


func heal(pos: Vector3) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["heal", pos])
	_fx_depth += 1
	_fx_heal(pos)
	_fx_depth -= 1


func number(pos: Vector3, v: float) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["number", pos, v])
	_fx_depth += 1
	_fx_number(pos, v)
	_fx_depth -= 1


func word(pos: Vector3, text: String, col: Color) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["word", pos, text, col])
	_fx_depth += 1
	_fx_word(pos, text, col)
	_fx_depth -= 1


func splash(pos: Vector3, acid: bool) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["splash", pos, acid])
	_fx_depth += 1
	_fx_splash(pos, acid)
	_fx_depth -= 1


func nuke(pos: Vector3) -> void:
	if _fx_depth == 0 and battle and battle.net:
		battle.net.rec_fx(["nuke", pos])
	_fx_depth += 1
	_fx_nuke(pos)
	_fx_depth -= 1
