class_name B3Weather
extends Node3D
## Rain or snow falling over the part of the battlefield the camera sees: the
## ground the overhead view looks at, or around and ahead of you in first
## person. It sits above the real ground (the maps have big hills) and tells
## the world to pull the fog in.

var battle = null
var kind := ""
var _p: CPUParticles3D = null


func set_kind(k: String) -> void:
	if battle != null and battle.world != null and battle.world.has_method("set_weather"):
		battle.world.set_weather(k if k == "rain" or k == "snow" else "")
	if k == kind:
		return
	kind = k
	if _p:
		_p.queue_free()
		_p = null
	if k != "rain" and k != "snow":
		return
	_p = CPUParticles3D.new()
	_p.local_coords = false
	_p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_p.emission_box_extents = Vector3(48, 1, 48)
	_p.direction = Vector3(0, -1, 0)
	_p.spread = 4.0
	_p.gravity = Vector3.ZERO
	_p.visibility_aabb = AABB(Vector3(-60, -60, -60), Vector3(120, 80, 120))
	_p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if k == "rain":
		_p.amount = 1600
		_p.lifetime = 1.3
		_p.initial_velocity_min = 26.0
		_p.initial_velocity_max = 32.0
		var m := BoxMesh.new()
		m.size = Vector3(0.03, 0.9, 0.03)
		m.material = mat
		mat.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
		_p.mesh = m
	else:
		_p.amount = 1400
		_p.lifetime = 7.0
		_p.initial_velocity_min = 3.0
		_p.initial_velocity_max = 5.0
		_p.spread = 25.0
		_p.angular_velocity_min = -90.0
		_p.angular_velocity_max = 90.0
		var m2 := BoxMesh.new()
		m2.size = Vector3(0.14, 0.14, 0.14)
		m2.material = mat
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
		_p.mesh = m2
	add_child(_p)
	_p.preprocess = _p.lifetime
	_follow()


func _process(_d: float) -> void:
	_follow()


func _follow() -> void:
	if _p == null or battle == null or battle.cam == null:
		return
	var up := 36.0 if kind == "rain" else 30.0
	var c: Vector3 = battle.cam.focus
	var cam := get_viewport().get_camera_3d()
	if cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		# first person: around you and a bit ahead, where you're looking
		var f := -cam.global_basis.z
		f.y = 0.0
		c = cam.global_position + (f.normalized() * 16.0 if f.length_squared() > 0.001 else Vector3.ZERO)
		up = 24.0 if kind == "rain" else 20.0
	var gy := 0.0
	if battle.world != null:
		gy = maxf(float(battle.world.height_at(c.x, c.z)), 0.0)
	if cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		gy = maxf(gy, cam.global_position.y - 1.7)
	_p.global_position = Vector3(c.x, gy + up, c.z)
