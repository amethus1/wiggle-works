class_name B3Weather
extends Node3D
## Rain or snow falling over the part of the battlefield the camera sees: the
## ground the overhead view looks at, or around and ahead of you in first
## person. It sits above the real ground (the maps have big hills) and tells
## the world to pull the fog in. The drops are GPU particles: when you zoom
## out, the patch they fall over grows with the view (just as thick), so it
## still rains all over the screen.

const HALF := 48.0              # half the patch's width at the usual zoom (and in first person)
const MAX_HALF := 200.0         # ... and when zoomed right out
const RAIN := 1600              # drops over a HALF-sized patch
const SNOW := 1400

var battle = null
var kind := ""
var _p: GPUParticles3D = null
var _pm: ParticleProcessMaterial = null
var _half := -1.0


func set_kind(k: String) -> void:
	if battle != null and battle.world != null and battle.world.has_method("set_weather"):
		battle.world.set_weather(k if k == "rain" or k == "snow" else "")
	if k == kind:
		return
	kind = k
	if _p:
		_p.queue_free()
		_p = null
		_pm = null
	if k != "rain" and k != "snow":
		return
	var most := (MAX_HALF / HALF) * (MAX_HALF / HALF)
	_p = GPUParticles3D.new()
	_pm = ParticleProcessMaterial.new()
	_pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_pm.emission_box_extents = Vector3(HALF, 1, HALF)
	_pm.direction = Vector3(0, -1, 0)
	_pm.spread = 4.0
	_pm.gravity = Vector3.ZERO
	_p.process_material = _pm
	_p.local_coords = false
	_p.visibility_aabb = AABB(Vector3(-MAX_HALF - 10.0, -60, -MAX_HALF - 10.0), Vector3(MAX_HALF * 2.0 + 20.0, 80, MAX_HALF * 2.0 + 20.0))
	_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if k == "rain":
		_p.amount = int(RAIN * most)
		_p.lifetime = 1.3
		_pm.initial_velocity_min = 26.0
		_pm.initial_velocity_max = 32.0
		var m := BoxMesh.new()
		m.size = Vector3(0.03, 0.9, 0.03)
		m.material = mat
		mat.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
		_p.draw_pass_1 = m
	else:
		_p.amount = int(SNOW * most)
		_p.lifetime = 7.0
		_pm.initial_velocity_min = 3.0
		_pm.initial_velocity_max = 5.0
		_pm.spread = 25.0
		_pm.angular_velocity_min = -90.0
		_pm.angular_velocity_max = 90.0
		var m2 := BoxMesh.new()
		m2.size = Vector3(0.14, 0.14, 0.14)
		m2.material = mat
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		_p.draw_pass_1 = m2
	_half = -1.0
	_p.preprocess = _p.lifetime
	add_child(_p)
	_follow()


func _process(_d: float) -> void:
	_follow()


func _follow() -> void:
	if _p == null or battle == null or battle.cam == null:
		return
	var up := 36.0 if kind == "rain" else 30.0
	var c: Vector3 = battle.cam.focus
	var cam := get_viewport().get_camera_3d()
	var half := HALF
	if cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# first person: around you and a bit ahead, where you're looking
		var f := -cam.global_basis.z
		f.y = 0.0
		c = cam.global_position + (f.normalized() * 16.0 if f.length_squared() > 0.001 else Vector3.ZERO)
		up = 24.0 if kind == "rain" else 20.0
	elif cam != null:
		# overhead: big enough to cover the screen (the view is turned, so its diagonal)
		var vs := get_viewport().get_visible_rect().size
		var w := cam.size * vs.x / maxf(vs.y, 1.0)
		var d := cam.size / sin(deg_to_rad(maxf(float(battle.cam.pitch), 10.0)))
		half = clampf(0.55 * sqrt(w * w + d * d), HALF, MAX_HALF)
	if absf(half - _half) > 0.5:
		_half = half
		_pm.emission_box_extents = Vector3(half, 1, half)
		# as many drops per square metre as ever
		_p.amount_ratio = (half / MAX_HALF) * (half / MAX_HALF)
	var gy := 0.0
	if battle.world != null:
		gy = maxf(float(battle.world.height_at(c.x, c.z)), 0.0)
	if cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		gy = maxf(gy, cam.global_position.y - 1.7)
	_p.global_position = Vector3(c.x, gy + up, c.z)
