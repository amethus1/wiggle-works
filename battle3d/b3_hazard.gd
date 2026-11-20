class_name B3Hazard
extends Node3D
## A glowing pool of lava or acid (or a patch of napalm fire). Units inside
## take damage; ragdolls and props that land in it sink with a sizzle.
## Temporary ones (napalm, acid bombs) shrink away after `life` seconds.

var battle = null
var kind := "lava"
var radius := 3.5
var radius0 := 3.5
var surface := 0.0
var life := -1.0
var age := 0.0
var dps := 40.0
var pool: MeshInstance3D = null
var rim: MeshInstance3D = null
var emit: CPUParticles3D = null
var light: OmniLight3D = null
var _t := 0.0

static var _lava_mat: ShaderMaterial = null
static var _acid_mat: ShaderMaterial = null


static func clear_cache() -> void:
	_lava_mat = null
	_acid_mat = null


static func pool_mat(acid: bool) -> ShaderMaterial:
	if acid and _acid_mat:
		return _acid_mat
	if not acid and _lava_mat:
		return _lava_mat
	var m := ShaderMaterial.new()
	m.shader = B3Mats.shader("pool")
	if acid:
		m.set_shader_parameter("col_a", Color(0.15, 0.75, 0.1))
		m.set_shader_parameter("col_b", Color(0.65, 1.0, 0.2))
		m.set_shader_parameter("crust", Color(0.12, 0.3, 0.08))
		m.set_shader_parameter("glow", 1.6)
		m.set_shader_parameter("speed", 0.7)
		_acid_mat = m
	else:
		m.set_shader_parameter("col_a", Color(1.0, 0.22, 0.02))
		m.set_shader_parameter("col_b", Color(1.0, 0.75, 0.12))
		m.set_shader_parameter("crust", Color(0.18, 0.08, 0.05))
		m.set_shader_parameter("glow", 2.6)
		m.set_shader_parameter("speed", 0.9)
		_lava_mat = m
	return m


func setup(b, k: String, r: float, life_s: float, lights_ok: bool) -> void:
	battle = b
	kind = k
	radius = r
	radius0 = r
	life = life_s
	var x := position.x
	var z := position.z
	var lo: float = battle.world.height_at(x, z)
	for i in 8:
		var a := TAU * i / 8.0
		lo = minf(lo, battle.world.height_at(x + cos(a) * r * 0.8, z + sin(a) * r * 0.8))
	surface = lo + 0.06
	position.y = surface
	match kind:
		"lava", "acid":
			dps = 45.0 if kind == "lava" else 32.0
			pool = MeshInstance3D.new()
			pool.mesh = B3Mats.cyl(1.0, 0.92, 2.0, 32)
			pool.material_override = pool_mat(kind == "acid")
			pool.position.y = -1.0
			pool.scale = Vector3(r, 1.0, r)
			pool.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(pool)
			rim = MeshInstance3D.new()
			rim.mesh = B3Mats.torus(0.93, 1.12)
			rim.material_override = B3Mats.mat(Color("3a2a26") if kind == "lava" else Color("3d5236"), 0.95)
			rim.scale = Vector3(r, 0.6, r)
			rim.position.y = 0.02
			add_child(rim)
			emit = battle.fx.make_particles("bubbles")
			emit.emission_sphere_radius = r * 0.8
			emit.material_override = B3Mats.glow(Color(1.0, 0.55, 0.1) if kind == "lava" else Color(0.5, 1.0, 0.3), 2.2)
			emit.amount = int(clampf(r * 5.0, 8, 40))
			emit.position.y = 0.05
			emit.set_deferred("emitting", true)
			add_child(emit)
		"fire":
			dps = 20.0
			emit = battle.fx.make_particles("fire")
			emit.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
			emit.emission_box_extents = Vector3(r * 0.75, 0.2, r * 0.75)
			emit.amount = int(clampf(r * 14.0, 30, 110))
			emit.set_deferred("emitting", true)
			emit.position.y = 0.2
			add_child(emit)
			battle.fx.scorch(position, r * 2.2)
	if lights_ok:
		light = OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.15) if kind != "acid" else Color(0.45, 1.0, 0.3)
		light.omni_range = r * 2.6
		light.light_energy = 1.8 if kind != "acid" else 1.2
		light.position.y = 1.2
		light.shadow_enabled = false
		add_child(light)


func contains(p: Vector3, margin := 0.0) -> bool:
	var dx := p.x - position.x
	var dz := p.z - position.z
	var r := radius + margin
	return dx * dx + dz * dz < r * r and p.y < surface + 1.1 and p.y > surface - 3.0


func _physics_process(dt: float) -> void:
	if dt <= 0.0:
		return
	age += dt
	_t += dt
	if light:
		light.light_energy = (1.8 if kind != "acid" else 1.2) * (0.85 + 0.15 * sin(_t * 7.0) * sin(_t * 3.1))
	if life > 0.0:
		var left := life - age
		if left < 2.0:
			radius = radius0 * maxf(0.05, left / 2.0)
			if pool:
				pool.scale = Vector3(radius, 1.0, radius)
				rim.scale = Vector3(radius, 0.6, radius)
			if emit and left < 1.0:
				emit.emitting = false
		if left <= 0.0:
			battle.remove_hazard(self)
