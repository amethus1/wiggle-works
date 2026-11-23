class_name B3Weather
extends Node3D
## Rain or snow falling over the part of the battlefield the camera sees: the
## ground the overhead view looks at, or around and ahead of you in first
## person. It sits above the real ground (the maps have big hills) and tells
## the world to pull the fog in. The drops are GPU particles, each a flat
## card facing the camera (2 triangles): rain streaks stand upright, snow
## flakes spin. When you zoom out, the patch they fall over grows with the
## view, so it still rains all over the screen: twice the width gets twice
## the drops, each a bit bigger (sqrt 2), so the screen looks as busy as
## before without the sky filling up with thousands of specks too small to
## see. Every drop lives long enough to reach the ground (or a little below:
## the terrain hides it), so none vanish in mid-air.

const HALF := 48.0              # half the patch's width at the usual zoom (and in first person)
const MAX_HALF := 200.0         # ... and when zoomed right out
const RAIN := 2000              # drops over a HALF-sized patch
const SNOW := 2000
const BELOW := 6.0              # metres below the ground under the middle every drop reaches
const RAIN_V := Vector2(26.0, 32.0)     # fall speeds (m/s)
const SNOW_V := Vector2(3.5, 5.0)
const RAIN_SPREAD := 4.0        # degrees off straight down
const SNOW_SPREAD := 20.0
const RAIN_UP := 36.0           # how high above the ground they start (overhead)
const SNOW_UP := 30.0
const PRE_FPS := 10             # snow fills the sky in 0.1 s steps (see set_kind)

var battle = null
var kind := ""
var _p: GPUParticles3D = null
var _pm: ParticleProcessMaterial = null
var _half := -1.0
var _warm := 0                  # frames until the snow goes back to the usual steps


## How long a drop must live to fall from `up` metres to BELOW under the
## ground, going straight down as slowly as it can.
static func life_for(up: float, v: Vector2, spread: float) -> float:
	return (up + BELOW) / (v.x * cos(deg_to_rad(spread)))


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
	_p = make_particles(k, 1.0)
	_pm = _p.process_material as ParticleProcessMaterial
	if k == "snow":
		# the sky starts full: the whole fall (`preprocess`) is worked out at
		# once. Slow flakes in straight lines lose nothing in bigger steps,
		# and it's three times less work for the graphics card than 1/30 s ones.
		_p.fixed_fps = PRE_FPS
		_warm = 2
	_half = -1.0
	add_child(_p)
	_follow()


## The drops for `k` ("rain" or "snow"), with room for `room` times the most
## there can be (zoomed right out). B3Fx._prewarm makes one-drop ones, so
## their shaders are compiled before the weather is first needed.
static func make_particles(k: String, room: float) -> GPUParticles3D:
	var rain := k == "rain"
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(HALF, 1, HALF)
	pm.direction = Vector3(0, -1, 0)
	pm.gravity = Vector3.ZERO
	p.process_material = pm
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-MAX_HALF - 10.0, -60, -MAX_HALF - 10.0), Vector3(MAX_HALF * 2.0 + 20.0, 80, MAX_HALF * 2.0 + 20.0))
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.billboard_keep_scale = true       # (bigger when zoomed out: see _follow)
	var m := QuadMesh.new()
	m.material = mat
	# room for the most drops (zoomed right out); _follow uses a part of them
	var most := MAX_HALF / HALF * room
	if rain:
		p.amount = maxi(1, int(RAIN * most))
		p.lifetime = life_for(RAIN_UP, RAIN_V, RAIN_SPREAD)
		pm.spread = RAIN_SPREAD
		pm.initial_velocity_min = RAIN_V.x
		pm.initial_velocity_max = RAIN_V.y
		m.size = Vector2(0.03, 0.9)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y      # upright streaks
		mat.albedo_color = Color(0.75, 0.85, 1.0, 0.45)
	else:
		p.amount = maxi(1, int(SNOW * most))
		p.lifetime = life_for(SNOW_UP, SNOW_V, SNOW_SPREAD)
		pm.spread = SNOW_SPREAD
		pm.initial_velocity_min = SNOW_V.x
		pm.initial_velocity_max = SNOW_V.y
		# flakes start turned every which way and spin as they fall
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		pm.angular_velocity_min = -90.0
		pm.angular_velocity_max = 90.0
		m.size = Vector2(0.18, 0.18)      # (about as big as the 0.14 m cubes looked)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES    # (turned by the particle's angle)
		mat.albedo_color = Color(1.0, 1.0, 1.0, 0.9)
	p.draw_pass_1 = m
	p.preprocess = p.lifetime
	return p


func _process(_d: float) -> void:
	if _warm > 0:
		_warm -= 1
		if _warm == 0 and _p:
			_p.fixed_fps = 30     # (the usual steps from now on)
	_follow()


func _follow() -> void:
	if _p == null or battle == null or battle.cam == null:
		return
	var up := RAIN_UP if kind == "rain" else SNOW_UP
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
		# twice as wide: twice the drops, each sqrt(2) bigger (as busy on screen)
		_p.amount_ratio = half / MAX_HALF
		var k := sqrt(half / HALF)
		_pm.scale_min = k
		_pm.scale_max = k
	var gy := 0.0
	if battle.world != null:
		gy = maxf(float(battle.world.height_at(c.x, c.z)), 0.0)
	if cam != null and cam.projection == Camera3D.PROJECTION_PERSPECTIVE:
		gy = maxf(gy, cam.global_position.y - 1.7)
	_p.global_position = Vector3(c.x, gy + up, c.z)
