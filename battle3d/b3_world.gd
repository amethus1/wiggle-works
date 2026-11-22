class_name B3World
extends Node3D
## The battlefield: sky, sun and fog, a big height-map terrain, mountains
## (or the sea) past the edge so you never see the end of the world, water,
## and scenery: forests, rocks, roads, fences, walls and buildings.
##
## The map is 384 m across (HALF = 192), with a height sample every 1.5 m
## (N = 257, a size Jolt turns into a fast height field). The middle (about
## ±60 m) stays gentle and open for battles; the outside has hills, forests,
## dirt roads, lakes and farms for driving and flying.
##
## Everything is made from fixed seeds per map id, so every computer builds
## the same map. A built map is remembered (static), so loading it again is
## quick.
##
## Drawing: the terrain is 16 chunks; trees, rocks and grass are MultiMeshes;
## buildings, walls and fences are merged into one mesh per chunk. Physics:
## one height field, one body holding the boxes of all buildings and walls,
## and a small StaticBody3D (meta "scenery") for each tree or rock that big
## blasts can uproot. Those are numbered (scenery_index / uproot_index) so a
## friend's computer can knock over the same tree.

const N := 257                 # height samples per side (2^8 + 1)
const STEP := 1.5              # metres between samples
const HALF := 192.0            # half the map width: (N - 1) * STEP / 2
const CH := 4                  # terrain and scenery are cut into CH x CH chunks (culling)
const CELLS := 64              # terrain cells per chunk side
const DEEP := 0.9              # water deeper than this pushes walkers back to the shore
## Rows of the mountain ring, in metres past the map edge.
const RING := [0.0, 5.0, 12.0, 22.0, 35.0, 52.0, 74.0, 102.0, 138.0, 182.0, 236.0, 300.0, 380.0, 480.0, 600.0, 760.0]
## Collision of scenery that blasts can uproot: [radius, height] (height 0 = sphere).
const SHAPES := {
	"tree": [0.3, 2.4], "pine": [0.3, 2.4], "pine_snow": [0.3, 2.4], "cactus": [0.35, 2.6],
	"deadtree": [0.25, 2.6], "palm": [0.28, 4.2], "olive": [0.3, 2.0], "rock": [0.85, 0.0],
}
const NO_SHADOW := ["tuft", "pebble", "wheat", "corn", "cabbage"]
## First person: how far each kind of ground detail shows (metres; it fades
## out over the last DETAIL_FADE). For that it's cut into DETAIL_CELL-sized
## pieces (the overhead view looks at it all from far above and keeps the
## big chunks).
const DETAIL_FAR := {"tuft": 75.0, "pebble": 75.0, "cabbage": 95.0, "wheat": 125.0, "corn": 155.0}
const DETAIL_FADE := 20.0
const DETAIL_CELL := 48.0
## Per map: fog distance (first person, by day), height of the far
## mountains, snow line, and the ring's mid / rock colours.
const CFG := {
	"grassland": {"fog": 820.0, "mh": 75.0, "snow": 95.0, "c1": Color("4e8a3c"), "c2": Color("8c8a7e")},
	"desert": {"fog": 720.0, "mh": 44.0, "snow": 999.0, "c1": Color("dca86c"), "c2": Color("c06a40")},
	"snow": {"fog": 560.0, "mh": 130.0, "snow": 26.0, "c1": Color("e2ecf6"), "c2": Color("8f9aa8")},
	"volcano": {"fog": 480.0, "mh": 80.0, "snow": 999.0, "c1": Color("3d3331"), "c2": Color("2a2423")},
	"beach": {"fog": 860.0, "mh": 45.0, "snow": 999.0, "c1": Color("5f9a45"), "c2": Color("8a8a80")},
	"farmland": {"fog": 820.0, "mh": 42.0, "snow": 999.0, "c1": Color("5d9a42"), "c2": Color("7f8a62")},
	"pass": {"fog": 740.0, "mh": 150.0, "snow": 108.0, "c1": Color("8f9a5a"), "c2": Color("a8957a")},
	"town": {"fog": 780.0, "mh": 50.0, "snow": 999.0, "c1": Color("5a9a45"), "c2": Color("8a8a80")},
}
## Desert mesas: x, z, radius, height.
const MESAS := [Vector4(118, -112, 24, 22), Vector4(-134, 62, 30, 26), Vector4(20, 162, 17, 17),
	Vector4(-84, -142, 22, 20), Vector4(158, 76, 12, 30)]
const FIELD := 56.0            # farmland field size

static var _memo := {}         # map id -> built data (the last few maps)
static var _memo_keys: Array[String] = []
static var _kmesh := {}        # scenery kind -> ArrayMesh
static var _prims := {}        # primitive key -> mesh arrays
static var _clouds: NoiseTexture2D = null
static var _water_shader: Shader = null

var map_id := "grassland"
var mdef: Dictionary = {}
var heights := PackedFloat32Array()
var env: Environment
var sun: DirectionalLight3D
var terrain: StaticBody3D
var scenery: Node3D
var trees: Array[Node3D] = []
var builtin_pools: Array = []    # [{kind, pos, radius}] lava/acid pools that come with the map
var waters: Array = []           # [{kind: "sea", level, zmin}] or [{kind: "lake", level, x, z, r}]
var roads: Array = []            # centre lines (PackedVector2Array), for anything that wants to follow them
var _bodies: Array[StaticBody3D] = []
var _by_sid := {}                # scenery number -> StaticBody3D
var _noise := FastNoiseLite.new()
var _hill := FastNoiseLite.new()
var _mask := FastNoiseLite.new()
var _mnt := FastNoiseLite.new()
var _sky_mat: ProceduralSkyMaterial
var _hor := Color.WHITE
var _time := "day"
var _weather := ""
var _view := -1                  # 0 overhead (orthographic), 1 first person
var _ground_mat: StandardMaterial3D
var _glass_day: StandardMaterial3D
var _glass_night: StandardMaterial3D
var _glass_mi: MeshInstance3D = null
var _water_mat: ShaderMaterial
var _ice_mat: StandardMaterial3D
var _nodes: Array[Node] = []     # everything made for the current map
var _detail: Array[MultiMeshInstance3D] = []     # ground detail chunks (tufts, crops...)
var _detail_fp: Array[MultiMeshInstance3D] = []  # first person: the same in finer pieces that fade out
var _detail_inst := {}           # kind -> its [transform, colour, ...] (for _detail_fp)
var _detail_mm: Array[MultiMesh] = []    # _detail_fp's MultiMeshes, kept for the next time
# only used while building a map
var _d: Dictionary = {}
var _cols := PackedColorArray()
var _road_d := PackedFloat32Array()
var _road_h := PackedFloat32Array()
var _road_hw := 2.8
var _busy := PackedByteArray()
var _bld: Array[Builder] = []
var _glass: Builder = null
var _shapes: Array = []
var _inst: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _slot := -1                  # number for the next uprootable thing planted


func _ready() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	_sky_mat = ProceduralSkyMaterial.new()
	_sky_mat.sky_curve = 0.12
	_sky_mat.ground_curve = 0.05
	_sky_mat.sky_cover = cloud_texture()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8d4ff")
	env.ambient_light_energy = 0.45
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 0.95
	env.tonemap_white = 4.0
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_strength = 1.0
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	env.set_glow_level(0, false)
	env.set_glow_level(1, true)
	env.set_glow_level(2, true)
	env.set_glow_level(3, true)
	env.set_glow_level(4, true)
	env.set_glow_level(5, false)
	env.ssao_enabled = true
	env.ssao_radius = 1.2
	env.ssao_intensity = 1.6
	env.ssao_power = 1.4
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_HIGH)
	sun = DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.shadow_blur = 1.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.directional_shadow_split_1 = 0.35
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2
	sun.rotation_degrees = Vector3(-52, -28, 0)
	add_child(sun)
	scenery = Node3D.new()
	scenery.name = "Scenery"
	add_child(scenery)
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	_ground_mat.vertex_color_is_srgb = true
	_ground_mat.roughness = 0.95
	_glass_day = StandardMaterial3D.new()
	_glass_day.albedo_color = Color("3d5266")
	_glass_day.roughness = 0.15
	_glass_day.metallic_specular = 0.8
	_glass_night = StandardMaterial3D.new()
	_glass_night.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glass_night.albedo_color = Color(2.2, 1.7, 0.8)
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = water_shader()
	_ice_mat = StandardMaterial3D.new()
	_ice_mat.albedo_color = Color("cfe6f4")
	_ice_mat.roughness = 0.08
	_ice_mat.metallic_specular = 0.9


## Half the width of the map in metres (the camera pans this far).
func half_size() -> float:
	return HALF


func load_map(id: String) -> void:
	map_id = id if B3Defs.MAPS.has(id) else "grassland"
	mdef = B3Defs.MAPS[map_id]
	_setup_noise()
	var dat: Dictionary = _memo.get(map_id, {})
	if dat.is_empty():
		dat = _build()
		_memo[map_id] = dat
		_memo_keys.append(map_id)
		if _memo_keys.size() > 3:
			_memo.erase(_memo_keys.pop_front())
	else:
		_memo_keys.erase(map_id)
		_memo_keys.append(map_id)
	_instantiate(dat)
	set_time(_time)


func _setup_noise() -> void:
	var sd: int = hash(map_id) % 10000
	_noise.seed = sd
	_noise.frequency = 0.035
	_noise.fractal_octaves = 3
	_hill.seed = sd + 17
	_hill.frequency = 0.0065
	_hill.fractal_octaves = 4
	_mask.seed = sd + 29
	_mask.frequency = 0.012
	_mask.fractal_octaves = 2
	_mnt.seed = sd + 41
	_mnt.frequency = 0.004
	_mnt.fractal_octaves = 4
	_mnt.fractal_type = FastNoiseLite.FRACTAL_RIDGED


# --------------------------------------------------------------- sky & fog
## Day, sunset or night lighting over the current map (call after load_map).
func set_time(t: String) -> void:
	_time = t
	if mdef.is_empty():
		return
	var top: Color = mdef.sky_top
	var hor: Color = mdef.sky_horizon
	var sun_c: Color = mdef.sun
	var sun_e := float(mdef.sun_energy)
	var amb_c: Color = (mdef.sky_top as Color).lerp(Color.WHITE, 0.45)
	if map_id == "volcano":
		amb_c = Color("ffb08a")
	var amb_e := float(mdef.ambient)
	var rot := Vector3(-52, -28, 0)
	var exposure := 0.95
	var cloud := Color(1.0, 1.0, 1.0, 0.85)
	var water_k := 1.0
	match t:
		"sunset":
			top = top.lerp(Color("4a3a7a"), 0.7)
			hor = hor.lerp(Color("ff8f52"), 0.85)
			sun_c = Color(1.0, 0.62, 0.36)
			sun_e *= 0.9
			rot = Vector3(-22, -28, 0)
			amb_c = amb_c.lerp(Color("ffb38a"), 0.55)
			amb_e *= 0.8
			cloud = Color(1.0, 0.72, 0.58, 0.8)
			water_k = 0.85
		"night":
			top = Color("070b24")
			hor = Color("1f2a55")
			sun_c = Color(0.62, 0.72, 1.0)
			sun_e = 0.3
			rot = Vector3(-62, 34, 0)
			amb_c = Color("5a6fb8")
			amb_e = 0.24
			exposure = 1.05
			cloud = Color(0.3, 0.36, 0.55, 0.3)
			water_k = 0.4
	if map_id == "volcano" and t != "night":
		cloud = Color(0.75, 0.6, 0.55, 0.7)
	_sky_mat.sky_top_color = top
	_sky_mat.sky_horizon_color = hor
	_sky_mat.ground_horizon_color = hor
	_sky_mat.ground_bottom_color = hor
	_sky_mat.sky_cover_modulate = cloud
	_hor = hor
	sun.light_color = sun_c
	sun.light_energy = sun_e
	sun.rotation_degrees = rot
	env.ambient_light_color = amb_c
	env.ambient_light_energy = amb_e
	env.tonemap_exposure = exposure
	_water_mat.set_shader_parameter("bright", water_k)
	if _glass_mi:
		_glass_mi.material_override = _glass_night if t == "night" else _glass_day
	_apply_fog()


## Rain and snow pull the fog in (called by B3Weather).
func set_weather(k: String) -> void:
	_weather = k
	_apply_fog()


func _apply_fog() -> void:
	if env == null:
		return
	var cfg: Dictionary = CFG.get(map_id, CFG.grassland)
	var far := float(cfg.fog)
	var near := 70.0
	var col := _hor
	var scatter := 0.1
	match _time:
		"sunset":
			far *= 0.9
			scatter = 0.35
		"night":
			far *= 0.55
			near = 25.0
			scatter = 0.0
	match _weather:
		"rain":
			far *= 0.42
			near *= 0.5
			col = col.lerp(Color(0.55, 0.6, 0.66) * (0.4 if _time == "night" else 1.0), 0.55)
		"snow":
			far *= 0.4
			near *= 0.5
			col = col.lerp(Color(0.86, 0.89, 0.94) * (0.4 if _time == "night" else 1.0), 0.6)
	env.fog_light_color = col
	env.fog_light_energy = 1.0
	env.fog_sun_scatter = scatter
	env.fog_aerial_perspective = 0.35 if _weather == "" else 0.0
	env.fog_sky_affect = 0.0 if _weather == "" else 0.9
	if _view == 1:
		env.fog_depth_begin = near
		env.fog_depth_end = far
		env.fog_depth_curve = 1.0
		env.fog_density = 1.0
	else:
		# overhead: the camera is ~260 m back, so the fog starts past the ground it looks at
		var back := 260.0
		var bt := get_parent()
		if bt != null and bt.get("cam") != null:
			back = float(bt.get("cam").get("dist"))
		env.fog_depth_begin = back + 60.0 + (0.0 if _weather == "" else -60.0)
		env.fog_depth_end = back + maxf(far * 0.6, 260.0)
		env.fog_depth_curve = 1.3
		env.fog_density = 0.9


## First person wants crisp shadows near the eyes; the overhead view wants
## them over the ground it looks at (an orthographic camera ignores the max
## distance and spreads the splits over near..far).
func _apply_shadows() -> void:
	if _view == 1:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
		sun.directional_shadow_max_distance = 160.0
		sun.directional_shadow_split_1 = 0.05
		sun.directional_shadow_split_2 = 0.15
		sun.directional_shadow_split_3 = 0.4
		sun.directional_shadow_blend_splits = true
		sun.directional_shadow_fade_start = 0.85
	else:
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
		sun.directional_shadow_max_distance = 220.0
		sun.directional_shadow_split_1 = 0.4
		sun.directional_shadow_blend_splits = false
		sun.directional_shadow_fade_start = 0.8


func _process(_dt: float) -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var v := 1 if cam.projection == Camera3D.PROJECTION_PERSPECTIVE else 0
	if v != _view:
		_view = v
		_apply_fog()
		_apply_shadows()
		_apply_detail()


## Overhead: the ground detail in its big chunks. First person: in finer
## pieces, each fading out past DETAIL_FAR (far-off tufts and crops are a
## pixel or two, and there are thousands of them).
func _apply_detail() -> void:
	var fp := _view == 1
	if fp and _detail_fp.is_empty():
		if _detail_mm.is_empty():
			_detail_mm = _detail_cells()
		for mm in _detail_mm:
			var kind := String(mm.get_meta("kind"))
			var far: float = DETAIL_FAR.get(kind, 100.0)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = B3Mats.vcol()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = far
			mmi.visibility_range_end_margin = DETAIL_FADE
			mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			scenery.add_child(mmi)
			_detail_fp.append(mmi)
	elif not fp:
		for m in _detail_fp:
			if is_instance_valid(m):
				m.queue_free()
		_detail_fp.clear()
	for m in _detail:
		if is_instance_valid(m):
			m.visible = not fp


## The ground detail cut into DETAIL_CELL squares (one MultiMesh per kind
## and square, with meta "kind").
func _detail_cells() -> Array[MultiMesh]:
	var out: Array[MultiMesh] = []
	var n := ceili(2.0 * HALF / DETAIL_CELL)
	for kv in _detail_inst:
		var kind := String(kv)
		var cells := {}
		for ev in (_detail_inst[kv] as Array):
			var e: Array = ev
			var o: Transform3D = e[0]
			var ci := Vector2i(clampi(int((o.origin.x + HALF) / DETAIL_CELL), 0, n - 1), clampi(int((o.origin.z + HALF) / DETAIL_CELL), 0, n - 1))
			if not cells.has(ci):
				cells[ci] = []
			(cells[ci] as Array).append(e)
		for ci in cells:
			var grp: Array = cells[ci]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = kind_mesh(kind)
			mm.instance_count = grp.size()
			for j in grp.size():
				var e2: Array = grp[j]
				mm.set_instance_transform(j, e2[0])
				mm.set_instance_color(j, e2[1])
			mm.set_meta("kind", kind)
			out.append(mm)
	return out


# ------------------------------------------------------------------ queries
## Terrain height (matches the collider: two triangles per 1.5 m cell).
func height_at(x: float, z: float) -> float:
	var fx := clampf((x + HALF) / STEP, 0.0, N - 1.001)
	var fz := clampf((z + HALF) / STEP, 0.0, N - 1.001)
	var xi := int(fx)
	var zi := int(fz)
	var tx := fx - xi
	var tz := fz - zi
	var i := zi * N + xi
	var a := heights[i]
	var b := heights[i + 1]
	var c := heights[i + N]
	var d := heights[i + N + 1]
	if tx + tz <= 1.0:
		return a + (b - a) * tx + (c - a) * tz
	return d + (c - d) * (1.0 - tx) + (b - d) * (1.0 - tz)


func normal_at(x: float, z: float) -> Vector3:
	var hx := height_at(x + 0.75, z) - height_at(x - 0.75, z)
	var hz := height_at(x, z + 0.75) - height_at(x, z - 0.75)
	return Vector3(-hx / 1.5, 1.0, -hz / 1.5).normalized()


## Height of the water surface at (x, z), or -1e9 where there is none.
## (Frozen lakes are ice you can walk on, so they don't count.)
func water_level_at(x: float, z: float) -> float:
	for wv in waters:
		var w: Dictionary = wv
		if String(w.kind) == "sea":
			if z > float(w.zmin):
				return float(w.level)
		else:
			var dx := x - float(w.x)
			var dz := z - float(w.z)
			var r := float(w.r) + 8.0
			if dx * dx + dz * dz < r * r:
				return float(w.level)
	return -1e9


## How deep the water is at (x, z) (0 on dry land).
func water_depth(x: float, z: float) -> float:
	if waters.is_empty():
		return 0.0
	var l := water_level_at(x, z)
	if l < -1e8:
		return 0.0
	return maxf(0.0, l - height_at(x, z))


## AI helper: turns a walking direction `w` along the shore instead of into
## deep water. Returns `w` unchanged on dry maps.
func steer_dry(p: Vector3, w: Vector3, r: float) -> Vector3:
	if waters.is_empty() or w == Vector3.ZERO:
		return w
	var n := w.normalized()
	var a := p + n * (r + 1.6)
	if water_depth(a.x, a.z) < DEEP * 0.7:
		return w
	var g := _uphill(a.x, a.z)
	if g == Vector3.ZERO:
		return Vector3.ZERO
	var t := Vector3(-g.z, 0.0, g.x)
	if t.dot(n) < 0.0:
		t = -t
	return (t + g * 0.6).normalized() * w.length()


func _uphill(x: float, z: float) -> Vector3:
	var g := Vector3(height_at(x + 1.5, z) - height_at(x - 1.5, z), 0.0, height_at(x, z + 1.5) - height_at(x, z - 1.5))
	if g.length_squared() < 0.0001:
		return Vector3.ZERO
	return g.normalized()


## Deep water pushes walkers (and cars) back towards the shore, like a soft
## wall. Ragdolls, flyers and things in the air aren't touched.
func _physics_process(_dt: float) -> void:
	if waters.is_empty():
		return
	var bt := get_parent()
	if bt == null or bt.get("units") == null or bt.get("puppet") == true:
		return
	var us: Array = bt.get("units")
	for o in us:
		var u := o as B3Unit
		if u == null or u.dead or u.down or u.flying or u.held:
			continue
		var p := u.position
		var lv := water_level_at(p.x, p.z)
		if lv < -1e8 or p.y > lv + 0.6:
			continue
		if lv - height_at(p.x, p.z) < DEEP:
			continue
		if bool(u.def.get("boat", false)):
			continue
		var g := _uphill(p.x, p.z)
		if g == Vector3.ZERO:
			continue
		var v := u.linear_velocity
		var out := v.x * g.x + v.z * g.z
		if out < 2.5:
			u.linear_velocity = v + g * (2.5 - out)


## The number of an uprootable tree or rock, or -1. Numbers come from where
## the thing was planted (each spot has its own fixed seed), so they're the
## same on every computer, and one odd spot can't shift the others.
func scenery_index(sb: Node) -> int:
	if sb == null or not is_instance_valid(sb) or not sb.has_meta("sid"):
		return -1
	return int(sb.get_meta("sid"))


## Uproots scenery number `i` (see scenery_index), like uproot().
func uproot_index(i: int, vel: Vector3, battle) -> void:
	var o: Variant = _by_sid.get(i)
	if o != null and is_instance_valid(o):
		uproot(o as StaticBody3D, vel, battle)


## Knock trees/rocks over (big blasts): they become flying physics props.
func uproot(sb: StaticBody3D, vel: Vector3, battle) -> void:
	if not is_instance_valid(sb) or sb.has_meta("gone"):
		return
	sb.set_meta("gone", true)
	trees.erase(sb)
	_by_sid.erase(int(sb.get_meta("sid", -1)))
	var rb := RigidBody3D.new()
	rb.collision_layer = B3Defs.L_PROP
	rb.collision_mask = B3Defs.L_TERRAIN | B3Defs.L_STRUCT | B3Defs.L_PROP | B3Defs.L_RAGDOLL
	rb.mass = 60.0
	rb.set_meta("debris", true)
	var xf := sb.global_transform
	battle.prop_root.add_child(rb)
	rb.global_transform = xf.translated(Vector3(0, 0.15, 0))
	if sb.has_meta("mm"):
		var mm: MultiMesh = sb.get_meta("mm")
		var mi: int = sb.get_meta("mi")
		var ixf := mm.get_instance_transform(mi)
		mm.set_instance_transform(mi, Transform3D(Basis.from_scale(Vector3.ZERO), ixf.origin))
		var vis := MeshInstance3D.new()
		vis.mesh = kind_mesh(String(sb.get_meta("scenery")))
		# keep its tint (volcano rocks stay dark, desert rocks sandy)
		vis.material_override = B3Mats.vcol(false, false, sb.get_meta("tint", Color.WHITE) as Color)
		vis.scale = Vector3.ONE * float(sb.get_meta("ks"))
		rb.add_child(vis)
	for c in sb.get_children():
		(c as Node).reparent(rb, true)
	sb.queue_free()
	rb.linear_velocity = vel
	var spin := RandomNumberGenerator.new()
	spin.seed = int(sb.get_meta("sid", 0)) + 1
	rb.angular_velocity = Vector3(spin.randf_range(-3, 3), spin.randf_range(-1, 1), spin.randf_range(-3, 3))
	battle.chunks.append(rb)


# ================================================================= building
## Makes everything for map_id as plain data (meshes, transforms, shapes).
func _build() -> Dictionary:
	_rng.seed = hash(map_id + "terrain")
	_d = {"roads": [], "lakes": [], "pads": [], "lines": [], "props": [], "pools": [], "sea": false, "zmin": 0.0}
	_road_hw = 2.8
	_busy = PackedByteArray()
	_busy.resize(N * N)
	_layout()
	_make_heights()
	_make_colors()
	var out := {}
	out.heights = heights
	var hm := HeightMapShape3D.new()
	hm.map_width = N
	hm.map_depth = N
	var scaled := heights.duplicate()
	for i in scaled.size():
		scaled[i] /= STEP
	hm.map_data = scaled
	out.shape = hm
	out.terrain = _terrain_meshes()
	out.ring = _ring_mesh()
	_scenery()
	var dec: Array = []
	for b in _bld:
		dec.append(b.commit())
	out.decor = dec
	out.glass = _glass.commit()
	out.shapes = _shapes
	out.inst = _inst
	out.pools = []
	for p in (_d.pools as Array):
		var pd: Dictionary = p
		(out.pools as Array).append({"kind": String(pd.kind), "pos": Vector3(float(pd.x), 0, float(pd.z)), "radius": float(pd.r)})
	var ws: Array = []
	if bool(_d.sea):
		ws.append({"kind": "sea", "level": 0.0, "zmin": float(_d.zmin)})
	var lakes: Array = []
	for lv in (_d.lakes as Array):
		var lk: Dictionary = lv
		lakes.append(lk)
		if not bool(lk.ice):
			ws.append({"kind": "lake", "level": float(lk.level), "x": float(lk.x), "z": float(lk.z), "r": float(lk.r)})
	out.waters = ws
	out.lakes = lakes
	out.sea = bool(_d.sea)
	var rl: Array = []
	for rv in (_d.roads as Array):
		rl.append((rv as Dictionary).pts)
	out.roads = rl
	# done with the scratch data
	_d = {}
	_cols = PackedColorArray()
	_road_d = PackedFloat32Array()
	_busy = PackedByteArray()
	_bld = []
	_glass = null
	_shapes = []
	_inst = {}
	return out


## Turns built data into nodes.
func _instantiate(dat: Dictionary) -> void:
	for n in _nodes:
		if is_instance_valid(n):
			n.queue_free()
	_nodes.clear()
	for c in scenery.get_children():
		c.queue_free()
	trees.clear()
	_bodies.clear()
	_by_sid.clear()
	_glass_mi = null
	_detail.clear()
	_detail_fp.clear()
	_detail_inst = {}
	_detail_mm.clear()
	heights = dat.heights
	builtin_pools = (dat.pools as Array).duplicate(true)
	waters = dat.waters
	roads = dat.roads
	terrain = StaticBody3D.new()
	terrain.name = "Terrain"
	terrain.collision_layer = B3Defs.L_TERRAIN
	terrain.collision_mask = 0
	var cs := CollisionShape3D.new()
	cs.shape = dat.shape
	cs.scale = Vector3.ONE * STEP
	terrain.add_child(cs)
	for m in (dat.terrain as Array):
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = _ground_mat
		mi.layers = 1 | 2
		terrain.add_child(mi)
	_keep(terrain)
	var ring := MeshInstance3D.new()
	ring.mesh = dat.ring
	ring.material_override = _ground_mat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_keep(ring)
	if bool(dat.sea):
		var sea := MeshInstance3D.new()
		sea.mesh = _sea_mesh()
		sea.material_override = _water_mat
		sea.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_keep(sea)
	for lv in (dat.lakes as Array):
		var lk: Dictionary = lv
		var disc := MeshInstance3D.new()
		var ice := bool(lk.ice)
		disc.mesh = _disc_mesh(float(lk.r) + (1.5 if ice else 8.0))
		disc.position = Vector3(float(lk.x), float(lk.level) + (0.03 if ice else 0.0), float(lk.z))
		disc.material_override = _ice_mat if ice else _water_mat
		disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_keep(disc)
	var dmat := B3Mats.vcol()
	for m in (dat.decor as Array):
		if m == null:
			continue
		var mi2 := MeshInstance3D.new()
		mi2.mesh = m
		mi2.material_override = dmat
		_keep(mi2)
	if dat.glass != null:
		_glass_mi = MeshInstance3D.new()
		_glass_mi.mesh = dat.glass
		_glass_mi.material_override = _glass_day
		_glass_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_keep(_glass_mi)
	var shp: Array = dat.shapes
	if not shp.is_empty():
		var sb := StaticBody3D.new()
		sb.name = "Buildings"
		sb.collision_layer = B3Defs.L_SCENERY
		sb.collision_mask = 0
		for sv in shp:
			var s: Array = sv
			var c2 := CollisionShape3D.new()
			var dim: Vector3 = s[2]
			match String(s[0]):
				"box":
					var bx := BoxShape3D.new()
					bx.size = dim
					c2.shape = bx
				"cyl":
					var cy := CylinderShape3D.new()
					cy.radius = dim.x
					cy.height = dim.y
					c2.shape = cy
				_:
					var sp := SphereShape3D.new()
					sp.radius = dim.x
					c2.shape = sp
			c2.transform = s[1]
			sb.add_child(c2)
		_keep(sb)
	if map_id == "volcano":
		_far_volcano()
	_make_instances(dat.inst)
	if _view == 1:
		_apply_detail()


func _keep(n: Node) -> void:
	_nodes.append(n)
	add_child(n)


func _make_instances(inst: Dictionary) -> void:
	var mat := B3Mats.vcol()
	for kv in inst:
		var kind := String(kv)
		var all: Array = inst[kv]
		var groups: Array = []
		for g in CH * CH:
			groups.append([])
		for ev in all:
			var e: Array = ev
			var o: Transform3D = e[0]
			(groups[_chunk_of(o.origin)] as Array).append(e)
		var km := kind_mesh(kind)
		var shadow := not NO_SHADOW.has(kind)
		if not shadow:
			_detail_inst[kind] = all
		for gv in groups:
			var grp: Array = gv
			if grp.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = km
			mm.instance_count = grp.size()
			for j in grp.size():
				var e2: Array = grp[j]
				mm.set_instance_transform(j, e2[0])
				mm.set_instance_color(j, e2[1])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			if not shadow:
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				_detail.append(mmi)
			scenery.add_child(mmi)
			for j in grp.size():
				var e3: Array = grp[j]
				if bool(e3[2]):
					_scenery_body(kind, e3, mm, j)


func _scenery_body(kind: String, e: Array, mm: MultiMesh, j: int) -> void:
	var xf: Transform3D = e[0]
	var s: float = e[3]
	var sb := StaticBody3D.new()
	sb.collision_layer = B3Defs.L_SCENERY
	sb.collision_mask = 0
	sb.position = xf.origin
	sb.rotation.y = float(e[4])
	var cs := CollisionShape3D.new()
	var spec: Array = SHAPES[kind]
	if float(spec[1]) <= 0.0:
		var sp := SphereShape3D.new()
		sp.radius = float(spec[0]) * s
		cs.shape = sp
		cs.position.y = 0.15 * s
	else:
		var cy := CylinderShape3D.new()
		cy.radius = float(spec[0]) * s
		cy.height = float(spec[1]) * s
		cs.shape = cy
		cs.position.y = cy.height * 0.5
	sb.add_child(cs)
	sb.set_meta("scenery", kind)
	sb.set_meta("mm", mm)
	sb.set_meta("mi", j)
	sb.set_meta("ks", s)
	sb.set_meta("tint", e[1])
	var sid := int(e[5])
	sb.set_meta("sid", sid)
	_by_sid[sid] = sb
	_bodies.append(sb)
	scenery.add_child(sb)
	if kind != "rock":
		trees.append(sb)


func _chunk_of(p: Vector3) -> int:
	var cx := clampi(int((p.x + HALF) / (2.0 * HALF / CH)), 0, CH - 1)
	var cz := clampi(int((p.z + HALF) / (2.0 * HALF / CH)), 0, CH - 1)
	return cz * CH + cx


# ------------------------------------------------------------------ layout
## Roads, lakes, buildings, walls and features for each map.
func _layout() -> void:
	match map_id:
		"grassland":
			_lay_grassland()
		"desert":
			_lay_desert()
		"snow":
			_lay_snow()
		"volcano":
			_lay_volcano()
		"beach":
			_lay_beach()
		"farmland":
			_lay_farmland()
		"pass":
			_lay_pass()
		"town":
			_lay_town()


func _road(ctrl: Array, closed := false, straight := false) -> void:
	var c := PackedVector2Array()
	for p in ctrl:
		c.append(p)
	var out := PackedVector2Array()
	var n := c.size()
	var segs := n if closed else n - 1
	for i in segs:
		var p1 := c[i]
		var p2 := c[(i + 1) % n]
		var p0 := c[(i - 1 + n) % n] if (closed or i > 0) else c[0]
		var p3 := c[(i + 2) % n] if (closed or i + 2 < n) else c[n - 1]
		var k := maxi(2, int(p1.distance_to(p2) / 1.5))
		for j in k:
			var t := float(j) / k
			out.append(p1.lerp(p2, t) if straight else p1.cubic_interpolate(p2, p0, p3, t))
	if not closed:
		out.append(c[n - 1])
	else:
		out.append(c[0])
	(_d.roads as Array).append({"pts": out, "hw": _road_hw})


func _pad(t: String, x: float, z: float, yaw: float, hw: float, hd: float, extra := {}) -> void:
	var p := {"t": t, "x": x, "z": z, "yaw": yaw, "hw": hw, "hd": hd}
	p.merge(extra)
	(_d.pads as Array).append(p)


func _line(t: String, a: Vector2, b: Vector2) -> void:
	(_d.lines as Array).append({"t": t, "a": a, "b": b})


func _prop(t: String, x: float, z: float, s := 1.0, yaw := 0.0) -> void:
	(_d.props as Array).append({"t": t, "x": x, "z": z, "s": s, "yaw": yaw})


func _lake(x: float, z: float, r: float, ice := false) -> void:
	(_d.lakes as Array).append({"x": x, "z": z, "r": r, "ice": ice, "level": 0.0})


func _pool(kind: String, x: float, z: float, r: float) -> void:
	(_d.pools as Array).append({"kind": kind, "x": x, "z": z, "r": r, "flat": true})


func _lay_grassland() -> void:
	var loop: Array = []
	for i in 14:
		var a := TAU * i / 14.0
		var r := 98.0 + 9.0 * sin(a * 3.0 + 0.7)
		loop.append(Vector2(cos(a), sin(a)) * r)
	_road(loop, true)
	_road([loop[12], Vector2(110, -82), Vector2(150, -76), Vector2(194, -84)])
	_road([loop[5], Vector2(-110, 118), Vector2(-150, 128), Vector2(-194, 150)])
	_road([loop[3], Vector2(36, 126), Vector2(48, 140)])
	_lake(-112, -100, 22)
	_pad("house", 128, -102, 0.2, 3.8, 4.8)
	_pad("barn", 152, -120, 0.2, 5.2, 7.2)
	_pad("silo", 166, -100, 0.0, 2.6, 2.6)
	_pad("house", -150, 40, -1.1, 3.8, 4.8)
	_pad("house", -55, -152, 0.5, 3.8, 4.8)
	_pad("windmill", 56, 150, 2.6, 3.6, 3.6)
	_line("fence", Vector2(116, -90), Vector2(116, -136))
	_line("fence", Vector2(116, -136), Vector2(178, -136))
	_line("fence", Vector2(178, -136), Vector2(178, -92))
	_line("wall", Vector2(60, -150), Vector2(118, -170))
	_line("wall", Vector2(-172, -28), Vector2(-128, 30))
	_line("wall", Vector2(92, 118), Vector2(160, 104))
	_prop("tor", -48, 128, 6.0)
	_prop("tor", 108, 160, 5.0)
	_prop("tor", -165, -152, 7.0)
	_prop("tor", 172, 22, 4.5)


func _lay_desert() -> void:
	_road([Vector2(-194, -40), Vector2(-130, -70), Vector2(-60, -88), Vector2(10, -86), Vector2(70, -70),
		Vector2(120, -30), Vector2(150, 20), Vector2(194, 40)])
	_road([Vector2(150, 20), Vector2(122, 72), Vector2(100, 100), Vector2(64, 150), Vector2(40, 194)])
	_lake(-72, 100, 13)
	var village := [[114, 124, 0.3], [130, 138, -0.5], [112, 148, 0.9], [138, 116, 1.2], [128, 160, 0.1], [148, 142, -1.0]]
	for v in village:
		var w := _rng.randf_range(5.5, 7.5)
		var d := _rng.randf_range(5.5, 7.5)
		_pad("adobe", float(v[0]), float(v[1]), float(v[2]), w * 0.5 + 0.4, d * 0.5 + 0.4, {"w": w, "d": d, "f": _rng.randf_range(2.8, 3.8)})
	_prop("palms", -72, 100, 13.0)
	_prop("arch", -150, -112, 1.0, 0.6)
	_prop("tor", 46, -150, 4.0)
	_prop("tor", -172, 12, 5.0)
	_prop("tor", 160, -64, 4.0)


func _lay_snow() -> void:
	var loop: Array = []
	for i in 14:
		var a := TAU * i / 14.0
		var r := 104.0 + 8.0 * sin(a * 2.0 + 1.3)
		loop.append(Vector2(cos(a), sin(a)) * r)
	_road(loop, true)
	_road([loop[6], Vector2(-118, 66), Vector2(-132, 84)])
	_lake(110, 104, 22, true)
	_pad("cabin", -128, 96, 0.3, 3.8, 4.4)
	_pad("cabin", -150, 70, -0.4, 3.8, 4.4)
	_pad("cabin", -108, 112, 1.1, 3.8, 4.4)
	_pad("cabin", 130, -120, 0.6, 3.8, 4.4)
	_pad("cabin", -40, -166, 0.0, 3.8, 4.4)
	_prop("snowman", -120, 80, 1.0, 0.4)
	_prop("snowman", -140, 106, 1.0, -0.6)
	_prop("snowman", 124, -104, 1.0, 2.6)
	_prop("snowman", -28, -154, 1.0, 0.0)
	_prop("tor", 64, -132, 5.0)
	_prop("tor", -162, -60, 6.0)
	_prop("tor", 152, 28, 4.0)


func _lay_volcano() -> void:
	# the three pools in the middle (dug by _h_classic), then more outside
	(_d.pools as Array).append({"kind": "lava", "x": 14.0, "z": 6.0, "r": 4.2, "flat": false})
	(_d.pools as Array).append({"kind": "lava", "x": -12.0, "z": 12.0, "r": 4.0, "flat": false})
	(_d.pools as Array).append({"kind": "acid", "x": 4.0, "z": -16.0, "r": 4.0, "flat": false})
	_pool("lava", 96, -66, 7.0)
	_pool("lava", -112, 96, 8.0)
	_pool("acid", -150, -46, 6.5)
	_pool("lava", 24, -130, 7.5)
	(_d.pools as Array).append({"kind": "lava", "x": 105.0, "z": 95.0, "r": 6.0, "flat": false})
	_road([Vector2(-194, 30), Vector2(-130, 52), Vector2(-80, 92), Vector2(-30, 124), Vector2(40, 150), Vector2(60, 194)])
	_prop("basalt", -128, -16, 6.0)
	_prop("basalt", 60, -152, 5.0)
	_prop("basalt", -150, -130, 7.0)
	_prop("basalt", 150, -24, 5.0)
	_prop("tor", -60, -152, 5.0)
	_prop("tor", 170, -120, 4.0)


func _lay_beach() -> void:
	_d.sea = true
	_d.zmin = 30.0
	_road([Vector2(-194, -98), Vector2(-120, -102), Vector2(-58, -96), Vector2(0, -102), Vector2(72, -96),
		Vector2(130, -106), Vector2(194, -100)])
	_road([Vector2(-55, 36), Vector2(-56, 0), Vector2(-57, -44), Vector2(-58, -96)])
	_road([Vector2(70, 30), Vector2(71, -16), Vector2(72, -56), Vector2(72, -96)])
	_road([Vector2(-58, -96), Vector2(-84, -132), Vector2(-112, -162), Vector2(-130, -194)])
	_pad("house", -102, -124, 0.2, 3.8, 4.8)
	_pad("house", -128, -140, -0.4, 3.8, 4.8)
	_pad("house", -96, -156, 0.7, 3.8, 4.8)
	_pad("house", -142, -114, 0.1, 3.8, 4.8)
	_pad("house", 112, -138, 0.3, 3.8, 4.8)
	_pad("barn", 136, -158, 0.3, 5.2, 7.2)
	_pad("lighthouse", 168, 60, 0.0, 3.6, 3.6)
	_line("hedge", Vector2(-40, -128), Vector2(40, -128))
	_line("hedge", Vector2(-30, -166), Vector2(90, -166))
	_line("hedge", Vector2(8, -114), Vector2(8, -190))
	_line("hedge", Vector2(-160, -122), Vector2(-160, -190))
	_line("hedge", Vector2(150, -122), Vector2(150, -186))
	_line("hedge", Vector2(-186, -150), Vector2(-150, -150))
	_prop("stack", 176, 128, 7.0)
	_prop("stack", -174, 124, 6.0)
	_prop("stack", 188, 108, 4.0)
	_prop("tor", -166, 80, 5.0)


func _lay_farmland() -> void:
	_road([Vector2(-80, -194), Vector2(-76, -110), Vector2(-82, -20), Vector2(-78, 90), Vector2(-80, 194)])
	_road([Vector2(-194, 76), Vector2(-100, 72), Vector2(0, 78), Vector2(100, 72), Vector2(194, 76)])
	_road([Vector2(-76, -110), Vector2(0, -128), Vector2(60, -124), Vector2(118, -144), Vector2(150, -150)])
	_road([Vector2(100, 72), Vector2(116, 100), Vector2(124, 116)])
	_pad("house", 112, 130, 0.0, 3.8, 4.8)
	_pad("barn", 140, 142, 0.0, 5.2, 7.2)
	_pad("silo", 154, 122, 0.0, 2.6, 2.6)
	_pad("house", -116, -126, 0.3, 3.8, 4.8)
	_pad("barn", -142, -146, 0.3, 5.2, 7.2)
	_pad("silo", -154, -122, 0.0, 2.6, 2.6)
	_pad("house", 162, -164, -0.4, 3.8, 4.8)
	_pad("shed", 140, -172, 0.2, 2.6, 2.2)
	_pad("house", -126, 122, -0.2, 3.8, 4.8)
	_pad("barn", -152, 144, -0.2, 5.2, 7.2)
	_pad("windmill", 24, -162, 0.4, 3.6, 3.6)
	_lake(66, 150, 11)
	for x0 in [-186.0, 92.0]:
		_line("fence", Vector2(x0, 84), Vector2(x0 + 94.0, 84))
		_line("fence", Vector2(x0, 66), Vector2(x0 + 94.0, 66))
	for z0 in [-186.0, 92.0]:
		_line("fence", Vector2(-72, z0), Vector2(-72, z0 + 94.0))
		_line("fence", Vector2(-88, z0), Vector2(-88, z0 + 94.0))
	_line("wall", Vector2(-70, -142), Vector2(94, -142))
	_line("wall", Vector2(150, -86), Vector2(150, 26))
	_line("wall", Vector2(-130, -30), Vector2(-130, 60))
	_line("wall", Vector2(-70, 138), Vector2(38, 138))
	_line("hedge", Vector2(94, 26), Vector2(186, 26))
	_line("hedge", Vector2(38, -86), Vector2(38, -136))
	_prop("orchard", -158, -2, 1.0)


func _lay_pass() -> void:
	_d.sea = true
	_d.zmin = 35.0
	_road([Vector2(-194, 6), Vector2(-120, 3), Vector2(-60, 1), Vector2(0, 0), Vector2(60, -1), Vector2(120, 2), Vector2(194, 5)])
	var village := [[146, -46, 0.2], [162, -62, -0.3], [138, -68, 0.6], [172, -36, 1.4], [154, -84, 0.0]]
	for v in village:
		var w := _rng.randf_range(5.5, 7.5)
		var d := _rng.randf_range(5.5, 7.0)
		_pad("villa", float(v[0]), float(v[1]), float(v[2]), w * 0.5 + 0.4, d * 0.5 + 0.4, {"w": w, "d": d, "f": _rng.randf_range(3.0, 4.0)})
	_pad("ruins", -142, -54, 0.3, 5.6, 8.6)
	_line("wall", Vector2(-170, -96), Vector2(-112, -100))
	_line("wall", Vector2(110, -112), Vector2(168, -106))
	_prop("tor", -104, 34, 5.0)
	_prop("tor", 122, 32, 4.0)
	_prop("tor", -170, -140, 6.0)
	_prop("tor", 92, -150, 6.0)


## Town: a square in the middle, streets in a grid, houses along them.
func _lay_town() -> void:
	_road_hw = 4.5
	var segs: Array = [
		[Vector2(-48, -48), Vector2(48, -48)], [Vector2(48, -48), Vector2(48, 48)],
		[Vector2(48, 48), Vector2(-48, 48)], [Vector2(-48, 48), Vector2(-48, -48)],
		[Vector2(0, 48), Vector2(0, 196)], [Vector2(0, -48), Vector2(0, -196)],
		[Vector2(48, 0), Vector2(196, 0)], [Vector2(-48, 0), Vector2(-196, 0)],
		[Vector2(124, -196), Vector2(124, 196)], [Vector2(-124, -196), Vector2(-124, 196)],
		[Vector2(-196, 124), Vector2(196, 124)], [Vector2(-196, -124), Vector2(196, -124)],
	]
	for s in segs:
		_road(s, false, true)
	var rects: Array = []      # placed buildings: Rect2 (with a gap)
	# a church facing the north avenue
	_pad("church", 26, 86, -PI * 0.5, 6.0, 11.5)
	rects.append(Rect2(26 - 12, 86 - 7.5, 24, 15))
	var cols := [Color("e8d9b8"), Color("c9776a"), Color("9cc3d9"), Color("b8d8a8"), Color("f2d98a"), Color("e3b5a4"), Color("d8d8d0"), Color("a8a0c8")]
	for s in segs:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var along := (b - a).normalized()
		var side := Vector2(-along.y, along.x)
		var length := a.distance_to(b)
		for sgn in [1.0, -1.0]:
			var t := 8.0
			while t < length - 8.0:
				var w := _rng.randf_range(8.0, 14.0)
				var d := _rng.randf_range(8.0, 12.0)
				var c: Vector2 = a + along * (t + w * 0.5) + side * float(sgn) * (_road_hw + 2.8 + d * 0.5)
				var ok := absf(c.x) < HALF - 12.0 and absf(c.y) < HALF - 12.0
				var ex := absf(along.x) * w * 0.5 + absf(along.y) * d * 0.5
				var ez := absf(along.y) * w * 0.5 + absf(along.x) * d * 0.5
				var rc := Rect2(c.x - ex - 1.0, c.y - ez - 1.0, ex * 2.0 + 2.0, ez * 2.0 + 2.0)
				var body := Rect2(c.x - ex + 0.2, c.y - ez + 0.2, ex * 2.0 - 0.4, ez * 2.0 - 0.4)
				if ok and rc.intersects(Rect2(-46, -46, 92, 92)):
					ok = false
				if ok:
					for o in rects:
						if rc.intersects(o):
							ok = false
							break
				if ok:
					for s2 in segs:
						if _seg_rect_hit(s2[0], s2[1], _road_hw + 2.4, body):
							ok = false
							break
				if ok and _rng.randf() < 0.12:
					ok = false           # a gap: a little park
					t += w
				if ok:
					rects.append(rc)
					# the front (+z in building space) faces the street
					var face := -side * float(sgn)
					var yaw := atan2(face.x, face.y)
					var near := c.length() < 110.0
					_pad("townhouse", c.x, c.y, yaw, w * 0.5 + 0.3, d * 0.5 + 0.3, {"w": w, "d": d,
						"f": _rng.randi_range(3, 5) if near else _rng.randi_range(2, 3),
						"col": cols[_rng.randi() % cols.size()], "roof": _rng.randf() < (0.35 if near else 0.7)})
					t += w + _rng.randf_range(1.5, 3.5)
				else:
					t += 3.0


## True if an axis-aligned road a-b (grown by `hw`) touches rect `r`.
func _seg_rect_hit(a: Vector2, b: Vector2, hw: float, r: Rect2) -> bool:
	var lo := Vector2(minf(a.x, b.x) - hw, minf(a.y, b.y) - hw)
	var hi := Vector2(maxf(a.x, b.x) + hw, maxf(a.y, b.y) + hw)
	return Rect2(lo, hi - lo).intersects(r)


# ----------------------------------------------------------------- heights
func _make_heights() -> void:
	heights = PackedFloat32Array()
	heights.resize(N * N)
	for zi in N:
		var z := zi * STEP - HALF
		for xi in N:
			heights[zi * N + xi] = _height(xi * STEP - HALF, z)
	# roads: flatten across, smooth along
	_road_d = PackedFloat32Array()
	_road_d.resize(N * N)
	_road_d.fill(1e6)
	_road_h = PackedFloat32Array()
	_road_h.resize(N * N)
	for rv in (_d.roads as Array):
		_stamp_road((rv as Dictionary).pts)
	var reach := _road_hw + 5.0
	for k in N * N:
		var d := _road_d[k]
		if d < reach:
			heights[k] = lerpf(heights[k], _road_h[k], 1.0 - smoothstep(_road_hw, reach, d))
	_road_h = PackedFloat32Array()
	for lv in (_d.lakes as Array):
		_stamp_lake(lv)
	for pv in (_d.pads as Array):
		_stamp_pad(pv)
	for pv in (_d.pools as Array):
		_stamp_pool(pv)


func _height(x: float, z: float) -> float:
	var h := 0.0
	match map_id:
		"beach":
			h = _h_beach(x, z)
		"farmland":
			h = _h_farm(x, z)
		"pass":
			h = _h_pass(x, z)
		"town":
			h = _h_town(x, z)
		_:
			h = _h_classic(x, z)
	var m := maxf(absf(x), absf(z))
	if m > HALF - 40.0:
		h = lerpf(h, _edge_h(x, z), smoothstep(HALF - 40.0, HALF - 2.0, m))
	return h


func _bump(x: float, z: float, cx: float, cz: float, r: float, h: float) -> float:
	var d2 := ((x - cx) * (x - cx) + (z - cz) * (z - cz)) / (r * r)
	return h * exp(-d2)


## The four first maps: the same middle as before, hills and more outside.
func _h_classic(x: float, z: float) -> float:
	var d := sqrt(x * x + z * z)
	var calm := smoothstep(16.0, 46.0, d)   # flat battle area in the middle
	var n := _noise.get_noise_2d(x, z)
	var o := smoothstep(62.0, 125.0, d)      # the outside
	var hn := _hill.get_noise_2d(x, z) if o > 0.0 else 0.0
	var h := 0.0
	match map_id:
		"grassland":
			h = n * 1.2 + calm * (n * 3.5 + 1.5)
			h += _bump(x, z, -22, 18, 7, 1.6) + _bump(x, z, 25, -14, 8, 1.4) + _bump(x, z, 8, 30, 6, 1.0)
			h += o * (hn * 14.0 + 3.0)
		"desert":
			h = 0.6 * sin(x * 0.11 + z * 0.05) + 0.35 * sin(z * 0.17 - x * 0.04) + n * 0.6
			h += calm * (2.5 * sin(x * 0.09) * cos(z * 0.07) + 2.5)
			h += _bump(x, z, 20, 20, 9, 1.8) + _bump(x, z, -26, -10, 10, 2.0)
			h += o * (3.5 * sin(x * 0.045 + hn * 3.0) * (0.6 + 0.4 * cos(z * 0.03)) + hn * 6.0 + 1.0)
			if o > 0.0:
				for mv in MESAS:
					var me: Vector4 = mv
					if absf(x - me.x) > me.z + 12.0 or absf(z - me.y) > me.z + 12.0:
						continue
					var md := Vector2(x - me.x, z - me.y).length() + _noise.get_noise_2d(x * 2.0, z * 2.0) * 4.0
					var top := me.w + n * 0.5
					h = maxf(h, lerpf(h, top, 1.0 - smoothstep(me.z - 1.0, me.z + 4.5, md)))
		"snow":
			h = n * 1.6 + calm * (n * 5.0 + 3.0)
			h += _bump(x, z, -18, -22, 9, 2.2) + _bump(x, z, 24, 16, 8, 1.6)
			h += o * (hn * 18.0 + 6.0)
		"volcano":
			h = n * 1.0 + calm * (n * 3.0 + 1.0)
			# the volcano itself, at the back
			var vd := Vector2(x + 36.0, z + 36.0).length()
			var cone := 17.0 * (1.0 - smoothstep(4.0, 26.0, vd))
			var crater := 6.0 * (1.0 - smoothstep(2.0, 5.5, vd))
			h += cone - crater
			for p in [Vector2(14, 6), Vector2(-12, 12), Vector2(4, -16)]:
				var pd := Vector2(x, z).distance_to(p)
				h = lerpf(h, -0.25, 1.0 - smoothstep(4.0, 7.0, pd))
			h += o * (hn * 11.0 + 2.0)
			# a big one further out, with lava in its crater
			var bd := Vector2(x - 105.0, z - 95.0).length()
			if bd < 70.0:
				h += 40.0 * (1.0 - smoothstep(9.0, 64.0, bd)) - 11.0 * (1.0 - smoothstep(5.0, 10.0, bd))
	return h


## The sea's edge: the beach and the pass have the sea on the +z side.
func _coast(x: float) -> float:
	if map_id == "pass":
		return 62.0 + 8.0 * sin(x * 0.017)
	return 48.0 + 5.0 * sin(x * 0.018) + 46.0 * smoothstep(135.0, 185.0, absf(x))


func _sea_floor(s: float, n: float) -> float:
	var h := -minf(s * 0.065, 1.0) - maxf(0.0, s - 15.0) * 0.09
	return maxf(h, -9.0) + n * 0.12


## D-Day beach: sea at +z, wet sand, a shingle bank, grassy bluffs with two
## gullies ("draws"), fields and hedges behind, rocky headlands at the ends.
func _h_beach(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z)
	var hn := _hill.get_noise_2d(x, z)
	var ax := absf(x)
	var dz := _coast(x) - z
	if dz < 0.0:
		return _sea_floor(-dz, n)
	var h := minf(dz * 0.036, 2.2) + n * 0.25 + maxf(0.0, dz - 60.0) * 0.012
	var bl := smoothstep(78.0, 112.0, dz)
	var draw := maxf(exp(-pow((x + 55.0) / 13.0, 2.0)), exp(-pow((x - 70.0) / 13.0, 2.0)))
	h += bl * (12.0 + hn * 4.0) * (1.0 - 0.7 * draw)
	h += smoothstep(105.0, 170.0, dz) * (hn * 7.0 + n * 1.5)
	var head := smoothstep(140.0, 178.0, ax)
	h += head * smoothstep(0.0, 14.0, dz) * (9.0 + hn * 6.0)
	return h


## Green rolling farm country.
func _h_farm(x: float, z: float) -> float:
	var d := sqrt(x * x + z * z)
	var n := _noise.get_noise_2d(x, z)
	return n * 0.9 + smoothstep(30.0, 110.0, d) * (_hill.get_noise_2d(x, z) * 7.0 + 1.0)


## Thermopylae: a pass about 20 m wide along x, tall cliffs to the south,
## a steep bank and the sea to the north, open valleys at both ends.
func _h_pass(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x, z)
	var hn := _hill.get_noise_2d(x, z)
	var ax := absf(x)
	var dz := _coast(x) - z
	if dz < 0.0:
		return _sea_floor(-dz, n)
	var ridge := 1.0 - smoothstep(58.0, 100.0, ax)
	var w := 10.6 + 1.0 * _noise.get_noise_2d(x * 0.4, 50.0) + 1.4 * _noise.get_noise_2d(x * 1.4, 90.0) + maxf(0.0, ax - 46.0) * 0.9
	var h := 2.0 * smoothstep(0.0, 18.0, dz) + n * 0.7 + hn * 3.5 * smoothstep(50.0, 110.0, ax)
	if z < 0.0:
		var e2 := -z - w
		var t := smoothstep(0.0, 4.0, e2) * 0.55 + smoothstep(6.0 + n * 2.0, 10.0 + n * 2.0, e2) * 0.45
		h += t * (26.0 + hn * 8.0 + n * 3.0 + maxf(e2, 0.0) * 0.16) * ridge
		h += smoothstep(30.0, 175.0, -z) * (22.0 + hn * 10.0) * (1.0 - ridge)
	else:
		var t2 := smoothstep(w, w + 3.5, z)
		h += t2 * (6.5 + hn * 1.5) * ridge * smoothstep(4.0, 16.0, dz)
	return h


func _h_town(x: float, z: float) -> float:
	var n := _noise.get_noise_2d(x * 0.5, z * 0.5)
	var hn := _hill.get_noise_2d(x, z)
	var m := maxf(absf(x), absf(z))
	return n * 0.5 + hn * 1.2 + smoothstep(135.0, 185.0, m) * (6.0 + hn * 6.0)


## Height the terrain climbs to at the map edge (hills all round, or the sea).
func _edge_h(x: float, z: float) -> float:
	var e := _hill.get_noise_2d(x * 0.6 + 500.0, z * 0.6)
	match map_id:
		"desert":
			return 9.0 + e * 6.0
		"snow":
			return 22.0 + e * 10.0
		"volcano":
			return 14.0 + e * 9.0
		"farmland", "town":
			return 9.0 + e * 5.0
		"beach":
			return lerpf(16.0 + e * 6.0, -9.0, _sea_w(x, z))
		"pass":
			var land := 32.0 + e * 10.0 - 24.0 * exp(-pow(z / 55.0, 2.0)) * smoothstep(120.0, 180.0, absf(x))
			return lerpf(land, -9.0, _sea_w(x, z))
	return 15.0 + e * 9.0


## 0 on land, 1 out at sea (beach and pass only).
func _sea_w(x: float, z: float) -> float:
	if map_id != "beach" and map_id != "pass":
		return 0.0
	var c := _coast(clampf(x, -HALF, HALF))
	return smoothstep(c - 4.0, c + 30.0, z)


func _k(x: float, z: float) -> int:
	var xi := clampi(roundi((x + HALF) / STEP), 0, N - 1)
	var zi := clampi(roundi((z + HALF) / STEP), 0, N - 1)
	return zi * N + xi


func _stamp_road(pts: PackedVector2Array) -> void:
	var n := pts.size()
	var hs := PackedFloat32Array()
	hs.resize(n)
	for i in n:
		hs[i] = height_at(pts[i].x, pts[i].y)
	for pass_i in 2:
		var sm := hs.duplicate()
		for i in n:
			var s := 0.0
			var c := 0
			for j in range(maxi(0, i - 6), mini(n, i + 7)):
				s += hs[j]
				c += 1
			sm[i] = s / c
		hs = sm
	var reach := _road_hw + 5.0
	var rc := int(ceil(reach / STEP))
	for i in n:
		var p := pts[i]
		var cx := roundi((p.x + HALF) / STEP)
		var cz := roundi((p.y + HALF) / STEP)
		for dz in range(-rc, rc + 1):
			var zi := cz + dz
			if zi < 0 or zi >= N:
				continue
			var gz := zi * STEP - HALF - p.y
			for dx in range(-rc, rc + 1):
				var xi := cx + dx
				if xi < 0 or xi >= N:
					continue
				var gx := xi * STEP - HALF - p.x
				var d := sqrt(gx * gx + gz * gz)
				var k := zi * N + xi
				if d < _road_d[k]:
					_road_d[k] = d
					_road_h[k] = hs[i]


func _stamp_lake(lk: Dictionary) -> void:
	var cx := float(lk.x)
	var cz := float(lk.z)
	var r := float(lk.r)
	var ice := bool(lk.ice)
	var avg := 0.0
	for a in 16:
		var an := TAU * a / 16.0
		avg += height_at(cx + cos(an) * (r + 10.0), cz + sin(an) * (r + 10.0))
	avg /= 16.0
	var level := avg - 0.5
	lk.level = level
	var reach := r + 18.0
	var rc := int(ceil(reach / STEP))
	var ci := roundi((cx + HALF) / STEP)
	var cj := roundi((cz + HALF) / STEP)
	for dj in range(-rc, rc + 1):
		var zi := cj + dj
		if zi < 0 or zi >= N:
			continue
		for di in range(-rc, rc + 1):
			var xi := ci + di
			if xi < 0 or xi >= N:
				continue
			var gx := xi * STEP - HALF - cx
			var gz := zi * STEP - HALF - cz
			var d := sqrt(gx * gx + gz * gz)
			d *= 1.0 + 0.1 * sin(atan2(gz, gx) * 3.0 + cx)
			if d > reach:
				continue
			var k := zi * N + xi
			var h := lerpf(heights[k], avg, 1.0 - smoothstep(r + 6.0, reach, d))
			if ice:
				if d < r + 1.0:
					h = level
				else:
					h = lerpf(level, maxf(h, level + 0.2), smoothstep(r + 1.0, r + 6.0, d))
			elif d < r:
				h = minf(h, level - 0.3 - 2.6 * (1.0 - (d / r) * (d / r)))
			elif d < r + 6.0:
				h = lerpf(level - 0.3, maxf(h, level + 0.4), smoothstep(r, r + 6.0, d))
			heights[k] = h
			if d < r + 3.0:
				_busy[k] = 1


func _stamp_pad(p: Dictionary) -> void:
	var cx := float(p.x)
	var cz := float(p.z)
	var yaw := float(p.yaw)
	var hw := float(p.hw)
	var hd := float(p.hd)
	var cs := cos(yaw)
	var sn := sin(yaw)
	var lvl := height_at(cx, cz)
	for c in [Vector2(hw, hd), Vector2(-hw, hd), Vector2(hw, -hd), Vector2(-hw, -hd)]:
		var lc: Vector2 = c
		lvl += height_at(cx + lc.x * cs + lc.y * sn, cz - lc.x * sn + lc.y * cs)
	lvl /= 5.0
	p.y = lvl
	var reach := sqrt(hw * hw + hd * hd) + 7.0
	var rc := int(ceil(reach / STEP))
	var ci := roundi((cx + HALF) / STEP)
	var cj := roundi((cz + HALF) / STEP)
	for dj in range(-rc, rc + 1):
		var zi := cj + dj
		if zi < 0 or zi >= N:
			continue
		for di in range(-rc, rc + 1):
			var xi := ci + di
			if xi < 0 or xi >= N:
				continue
			var dx := xi * STEP - HALF - cx
			var dz := zi * STEP - HALF - cz
			var lx := dx * cs - dz * sn
			var lz := dx * sn + dz * cs
			var ex := maxf(absf(lx) - hw, 0.0)
			var ez := maxf(absf(lz) - hd, 0.0)
			var d := sqrt(ex * ex + ez * ez)
			var k := zi * N + xi
			var w := 1.0 - smoothstep(1.0, 6.5, d)
			if w > 0.0:
				heights[k] = lerpf(heights[k], lvl, w)
			if d < 1.5:
				_busy[k] = 1


func _stamp_pool(p: Dictionary) -> void:
	if not bool(p.get("flat", true)):
		return
	var cx := float(p.x)
	var cz := float(p.z)
	var r := float(p.r)
	var lvl := height_at(cx, cz)
	for a in 8:
		var an := TAU * a / 8.0
		lvl = minf(lvl, height_at(cx + cos(an) * r, cz + sin(an) * r))
	lvl -= 0.3
	var reach := r + 5.0
	var rc := int(ceil(reach / STEP))
	var ci := roundi((cx + HALF) / STEP)
	var cj := roundi((cz + HALF) / STEP)
	for dj in range(-rc, rc + 1):
		var zi := cj + dj
		if zi < 0 or zi >= N:
			continue
		for di in range(-rc, rc + 1):
			var xi := ci + di
			if xi < 0 or xi >= N:
				continue
			var gx := xi * STEP - HALF - cx
			var gz := zi * STEP - HALF - cz
			var d := sqrt(gx * gx + gz * gz)
			var k := zi * N + xi
			heights[k] = lerpf(heights[k], lvl, 1.0 - smoothstep(r * 0.85, reach, d))
			if d < r + 2.0:
				_busy[k] = 1


# ------------------------------------------------------------------ colours
func _make_colors() -> void:
	_cols = PackedColorArray()
	_cols.resize(N * N)
	var inv := 1.0 / (4.0 * STEP * STEP)
	for zi in N:
		var z := zi * STEP - HALF
		for xi in N:
			var k := zi * N + xi
			var hx := heights[zi * N + mini(xi + 1, N - 1)] - heights[zi * N + maxi(xi - 1, 0)]
			var hz := heights[mini(zi + 1, N - 1) * N + xi] - heights[maxi(zi - 1, 0) * N + xi]
			var ny := 1.0 / sqrt(1.0 + (hx * hx + hz * hz) * inv)
			var c := _color(xi * STEP - HALF, z, heights[k], 1.0 - ny, k)
			var f := 1.0 + (_rng.randf() - 0.5) * 0.07
			_cols[k] = Color(c.r * f, c.g * f, c.b * f)


func _forest(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	return smoothstep(0.06, 0.3, _mask.get_noise_2d(x, z)) * smoothstep(70.0, 95.0, r)


func _color(x: float, z: float, h: float, slope: float, k: int) -> Color:
	var g: Color = mdef.ground
	var g2: Color = mdef.ground2
	var nd := _noise.get_noise_2d(x * 2.3 + 100.0, z * 2.3)
	var c := g.lerp(g2, clampf(nd * 1.6 + 0.5, 0.0, 1.0))
	var road := Color("a8875a")
	match map_id:
		"grassland":
			c = c.lerp(Color("8a7a52"), clampf((slope - 0.35) * 2.0, 0.0, 0.6))
			c = c.lerp(Color("a6dc6a"), clampf(h * 0.06, 0.0, 0.25))
			c = c.lerp(Color("3f7a33"), _forest(x, z) * 0.45)
			c = c.lerp(Color("8d8a80"), clampf((slope - 0.6) * 2.5, 0.0, 0.8))
		"snow":
			c = c.lerp(Color("aebfd2"), clampf((slope - 0.3) * 2.0, 0.0, 0.7))
			c = c.lerp(Color("7d8794"), clampf((slope - 0.65) * 3.0, 0.0, 0.8))
			c = c.lerp(Color("c9d6e6"), _forest(x, z) * 0.35)
			road = Color("b9c6d6")
		"desert":
			c = c.lerp(Color("d4a35e"), clampf(-h * 0.2 + 0.1, 0.0, 0.35))
			var strata := 0.5 + 0.5 * sin(h * 1.1)
			var rock := Color("c8693e").lerp(Color("e0a36a"), strata)
			c = c.lerp(rock, clampf((slope - 0.3) * 2.2, 0.0, 1.0))
			c = c.lerp(Color("d99a5c"), clampf((h - 12.0) * 0.2, 0.0, 0.8))
			road = Color("c49a62")
		"volcano":
			var vd := Vector2(x + 36.0, z + 36.0).length()
			c = c.lerp(Color("2e2624"), clampf(h * 0.04, 0.0, 0.6))
			if vd < 6.0:
				c = Color("ff7a2a").lerp(Color("3a2a26"), clampf((vd - 2.5) / 3.0, 0.0, 1.0))
			var bd := Vector2(x - 105.0, z - 95.0).length()
			if bd < 11.0:
				c = Color("ff7a2a").lerp(Color("3a2a26"), clampf((bd - 6.0) / 4.0, 0.0, 1.0))
			c = c.lerp(Color("241e1d"), clampf((slope - 0.5) * 2.0, 0.0, 0.6))
			road = Color("6e625c")
		"beach":
			var dz := _coast(x) - z
			var sand := Color("ead6a0").lerp(Color("f2e2b0"), clampf(nd + 0.5, 0.0, 1.0))
			if h < 0.5 and dz > -40.0:
				sand = sand.lerp(Color("c9b27c"), 1.0 - smoothstep(-0.2, 0.5, h))
			var grass := Color("6aaa45").lerp(Color("86c05a"), clampf(nd + 0.5, 0.0, 1.0))
			grass = grass.lerp(Color("3f7a33"), _forest(x, z) * 0.4)
			c = sand.lerp(grass, maxf(smoothstep(62.0, 84.0, dz), smoothstep(3.5, 6.0, h) * smoothstep(118.0, 145.0, absf(x))))
			c = c.lerp(Color("9a8558"), clampf((slope - 0.35) * 2.0, 0.0, 0.7))
			c = c.lerp(Color("8f8b82"), clampf((slope - 0.55) * 2.5, 0.0, 0.85))
			if h < -0.3:
				c = c.lerp(Color("8a7d5a"), clampf(-h * 0.15, 0.0, 0.6))
		"farmland":
			c = _field_color(x, z, c)
			c = c.lerp(Color("8a7a52"), clampf((slope - 0.35) * 2.0, 0.0, 0.6))
		"pass":
			var dz2 := _coast(x) - z
			c = c.lerp(Color("8fb05a"), smoothstep(70.0, 130.0, absf(x)) * 0.45)
			var strata2 := smoothstep(-0.3, 0.3, sin(h * 0.9 + nd * 1.5))
			var rk := Color("c4ad8c").lerp(Color("97836a"), strata2)
			rk = rk.darkened(clampf(_noise.get_noise_2d(x * 3.0, h * 3.0) * 0.5, 0.0, 0.25))
			c = c.lerp(rk, clampf((slope - 0.3) * 2.2, 0.0, 1.0))
			if dz2 < 10.0:
				c = c.lerp(Color("e3cf9c"), 1.0 - smoothstep(2.0, 10.0, dz2))
			c = c.lerp(Color("6d8a45"), _forest(x, z) * 0.35)
			road = Color("c2a77a")
		"town":
			road = Color("54565c")
			if absf(x) < 40.5 and absf(z) < 40.5:
				var tile := (int(floorf(x / 6.0)) + int(floorf(z / 6.0))) & 1
				c = Color("d8cdb6").lerp(Color("cdbfa4"), clampf(nd + 0.5, 0.0, 1.0))
				if tile == 1:
					c = c.darkened(0.05)
			c = c.lerp(Color("3f7a33"), _forest(x, z) * 0.35)
	# roads
	var rd := _road_d[k]
	if rd < _road_hw + 3.5:
		if map_id == "town":
			var sw := 1.0 - smoothstep(_road_hw + 2.2, _road_hw + 2.8, rd)
			c = c.lerp(Color("b4b2ac"), sw)
		c = c.lerp(road, 1.0 - smoothstep(_road_hw - 0.6, _road_hw + 0.9, rd))
	return c


## Farmland: a patchwork of fields with crop stripes.
func _field_color(x: float, z: float, base: Color) -> Color:
	var fx := floori((x + 18.0) / FIELD)
	var fz := floori((z + 30.0) / FIELD)
	var crop := _crop(fx, fz)
	var lx := x + 18.0 - fx * FIELD
	var lz := z + 30.0 - fz * FIELD
	var edge := minf(minf(lx, FIELD - lx), minf(lz, FIELD - lz))
	if edge < 2.2:
		return base.lerp(Color("7cc04e"), 0.4)
	var along := lx if _stripe_x(fx, fz) else lz
	var s := sin(along * TAU / 6.0)
	var on := smoothstep(-0.3, 0.3, s)
	match crop:
		0:
			return Color("e6c25c").lerp(Color("cfa443"), on)
		1:
			return Color("5faa3c").lerp(Color("82c652"), on)
		2:
			return Color("8a6440").lerp(Color("6f4f32"), on)
		4:
			return Color("4f8f30").lerp(Color("6aa83e"), on)
		5:
			return Color("f0d23a").lerp(Color("dcbf32"), on)
	return base


## Crop of field (fx, fz): 0 wheat, 1 cabbages, 2 ploughed, 3 meadow, 4 corn, 5 yellow flowers.
func _crop(fx: int, fz: int) -> int:
	if fx == 0 and fz == 0:
		return 3
	var hs := absi((fx * 73856093) ^ (fz * 19349663) ^ 7919)
	return hs % 6


func _stripe_x(fx: int, fz: int) -> bool:
	return (absi((fx * 83492791) ^ (fz * 2654435)) >> 3) & 1 == 0


# ------------------------------------------------------------------ meshes
func _terrain_meshes() -> Array:
	var w := CELLS + 1
	var idx := _grid_index(w, w)
	var out: Array = []
	var inv := 1.0 / (2.0 * STEP)
	for cz in CH:
		for cx in CH:
			var pv := PackedVector3Array()
			pv.resize(w * w)
			var pn := PackedVector3Array()
			pn.resize(w * w)
			var pc := PackedColorArray()
			pc.resize(w * w)
			var j := 0
			for lz in w:
				var zi := cz * CELLS + lz
				for lx in w:
					var xi := cx * CELLS + lx
					var k := zi * N + xi
					pv[j] = Vector3(xi * STEP - HALF, heights[k], zi * STEP - HALF)
					var hx := heights[zi * N + mini(xi + 1, N - 1)] - heights[zi * N + maxi(xi - 1, 0)]
					var hz := heights[mini(zi + 1, N - 1) * N + xi] - heights[maxi(zi - 1, 0) * N + xi]
					pn[j] = Vector3(-hx * inv, 1.0, -hz * inv).normalized().lerp(Vector3.UP, 0.2).normalized()
					pc[j] = _cols[k]
					j += 1
			out.append(_mesh(pv, pn, pc, idx))
	return out


## Triangle indices for a w x h grid of vertices (rows along x).
static func _grid_index(w: int, h: int) -> PackedInt32Array:
	var idx := PackedInt32Array()
	idx.resize((w - 1) * (h - 1) * 6)
	var k := 0
	for z in h - 1:
		for x in w - 1:
			var i00 := z * w + x
			idx[k] = i00
			idx[k + 1] = i00 + 1
			idx[k + 2] = i00 + w
			idx[k + 3] = i00 + w + 1
			idx[k + 4] = i00 + w
			idx[k + 5] = i00 + 1
			k += 6
	return idx


static func _mesh(pv: PackedVector3Array, pn: PackedVector3Array, pc: PackedColorArray, idx: PackedInt32Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = pv
	arrays[Mesh.ARRAY_NORMAL] = pn
	arrays[Mesh.ARRAY_COLOR] = pc
	arrays[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return m


## Mountains (or the sea floor) all round the map, out to the fog. The
## first row is the map's own edge, so there is no gap.
func _ring_mesh() -> ArrayMesh:
	var per: Array[Vector2i] = []
	for xi in N - 1:
		per.append(Vector2i(xi, 0))
	for zi in N - 1:
		per.append(Vector2i(N - 1, zi))
	for xi in range(N - 1, 0, -1):
		per.append(Vector2i(xi, N - 1))
	for zi in range(N - 1, 0, -1):
		per.append(Vector2i(0, zi))
	var P := per.size()
	var R := RING.size()
	var soft := PackedColorArray()
	soft.resize(P)
	for j in P:
		var acc := Color(0, 0, 0, 0)
		for q in range(-8, 9):
			var g2 := per[(j + q + P) % P]
			var k2 := g2.y * N + g2.x
			acc += _cols[k2] if _road_d[k2] > _road_hw + 2.0 else (mdef.ground as Color)
		soft[j] = acc / 17.0
	var pv := PackedVector3Array()
	pv.resize(P * R)
	var pc := PackedColorArray()
	pc.resize(P * R)
	for j in P:
		var g := per[j]
		var k := g.y * N + g.x
		var p0 := Vector2(g.x * STEP - HALF, g.y * STEP - HALF)
		var e0 := heights[k]
		var dir := p0.normalized()
		for r in R:
			var d: float = RING[r]
			var p := p0 + dir * d
			if r == 0:
				pv[j] = Vector3(p.x, e0, p.y)
				pc[j] = _cols[k]
			else:
				var h := _beyond_h(p.x, p.y, d, e0)
				pv[r * P + j] = Vector3(p.x, h, p.y)
				pc[r * P + j] = _ring_col(p.x, p.y, h, e0, d, soft[j])
	var pn := PackedVector3Array()
	pn.resize(P * R)
	for r in R:
		for j in P:
			var a := pv[r * P + (j + 1) % P] - pv[r * P + (j - 1 + P) % P]
			var b := pv[mini(r + 1, R - 1) * P + j] - pv[maxi(r - 1, 0) * P + j]
			var nn := a.cross(b).normalized()
			if nn.y < 0.0:
				nn = -nn
			pn[r * P + j] = nn
	var idx := PackedInt32Array()
	idx.resize((R - 1) * P * 6)
	# which way round makes the faces point up?
	var t0 := pv[0]
	var t1 := pv[1]
	var t2 := pv[P]
	var flip := (t2 - t0).cross(t1 - t0).y < 0.0
	var q := 0
	for r in R - 1:
		for j in P:
			var a := r * P + j
			var b := r * P + (j + 1) % P
			var c := a + P
			var d := b + P
			if flip:
				idx[q] = a
				idx[q + 1] = c
				idx[q + 2] = b
				idx[q + 3] = d
				idx[q + 4] = b
				idx[q + 5] = c
			else:
				idx[q] = a
				idx[q + 1] = b
				idx[q + 2] = c
				idx[q + 3] = d
				idx[q + 4] = c
				idx[q + 5] = b
			q += 6
	return _mesh(pv, pn, pc, idx)


func _beyond_h(x: float, z: float, d: float, e0: float) -> float:
	var cfg: Dictionary = CFG.get(map_id, CFG.grassland)
	var t := smoothstep(0.0, 260.0, d)
	var mn := _mnt.get_noise_2d(x, z) * 0.5 + 0.5
	var h := e0 + t * float(cfg.mh) * (0.2 + 0.8 * mn * mn)
	match map_id:
		"desert":
			if t > 0.15:
				var q := h / 9.0
				var fq := floorf(q)
				h = lerpf(h, (fq + smoothstep(0.7, 1.0, q - fq)) * 9.0, 0.85)
		"beach", "pass":
			h = lerpf(h, -10.0, _sea_w(x, z))
		"town", "farmland":
			h += t * 6.0 * (0.5 + 0.5 * _hill.get_noise_2d(x, z))
	return h


func _ring_col(x: float, z: float, h: float, e0: float, d: float, edge: Color) -> Color:
	var cfg: Dictionary = CFG.get(map_id, CFG.grassland)
	var c0: Color = mdef.skirt
	var c1: Color = cfg.c1
	var c2: Color = cfg.c2
	var rel := h - e0
	var nd := _noise.get_noise_2d(x * 0.05, z * 0.05)
	var c := edge.lerp(c0, smoothstep(0.0, 40.0, d))
	c = c.lerp(c1, smoothstep(4.0, 30.0, rel) * (0.7 + 0.3 * nd))
	c = c.lerp(c2, smoothstep(30.0, 90.0, rel) * (0.6 + 0.4 * nd))
	if map_id == "desert":
		c = c.lerp(Color("c8693e"), (0.5 + 0.5 * sin(h * 0.7)) * smoothstep(10.0, 30.0, rel) * 0.6)
	var sl := float(cfg.snow)
	c = c.lerp(Color("f2f6fa"), smoothstep(sl, sl + 18.0, h))
	if (map_id == "beach" or map_id == "pass") and h < 0.0:
		c = Color("b8a87a").lerp(Color("6f6a55"), clampf(-h / 8.0, 0.0, 1.0))
	return c


## The sea: a flat grid, fine near the map (for the waves) and coarse far out.
func _sea_mesh() -> ArrayMesh:
	var xs: Array = [-1400.0, -900.0, -600.0, -420.0, -300.0, -240.0]
	var x := -204.0
	while x <= 204.0:
		xs.append(x)
		x += 4.0
	xs.append_array([240.0, 300.0, 420.0, 600.0, 900.0, 1400.0])
	var zs: Array = []
	var z := 24.0
	while z <= 228.0:
		zs.append(z)
		z += 4.0
	zs.append_array([270.0, 330.0, 420.0, 600.0, 900.0, 1400.0])
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pc := PackedColorArray()
	for zz in zs:
		for xx in xs:
			pv.append(Vector3(float(xx), 0.0, float(zz)))
			pn.append(Vector3.UP)
			pc.append(Color.WHITE)
	return _mesh(pv, pn, pc, _grid_index(xs.size(), zs.size()))


## A flat round lake (or ice) surface of radius r.
static func _disc_mesh(r: float) -> ArrayMesh:
	var seg := 40
	var rings := 6
	var pv := PackedVector3Array()
	var pn := PackedVector3Array()
	var pc := PackedColorArray()
	pv.append(Vector3.ZERO)
	pn.append(Vector3.UP)
	pc.append(Color.WHITE)
	for ri in rings:
		var rr := r * float(ri + 1) / rings
		for s in seg:
			var a := TAU * s / seg
			pv.append(Vector3(cos(a) * rr, 0.0, sin(a) * rr))
			pn.append(Vector3.UP)
			pc.append(Color.WHITE)
	var idx := PackedInt32Array()
	for s in seg:
		idx.append_array(PackedInt32Array([0, 1 + (s + 1) % seg, 1 + s]))
	for ri in rings - 1:
		var b0 := 1 + ri * seg
		var b1 := b0 + seg
		for s in seg:
			var s1 := (s + 1) % seg
			idx.append_array(PackedInt32Array([b0 + s, b0 + s1, b1 + s, b1 + s1, b1 + s, b0 + s1]))
	# make sure the faces point up
	var t0 := pv[idx[0]]
	var t1 := pv[idx[1]]
	var t2 := pv[idx[2]]
	if (t2 - t0).cross(t1 - t0).y < 0.0:
		for i in range(0, idx.size(), 3):
			var tmp := idx[i + 1]
			idx[i + 1] = idx[i + 2]
			idx[i + 2] = tmp
	return _mesh(pv, pn, pc, idx)


## A big smoking volcano on the horizon (volcano map).
func _far_volcano() -> void:
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var o := Transform3D(Basis.IDENTITY, Vector3(-430, -10, -320))
	b.add_flat(prim("cyl:18:0.16"), o * _xf(Vector3(0, 90, 0), Vector3(470, 180, 470)), Color("3a302e"), 0.25, rng)
	b.add_flat(prim("cyl:12:0.5"), o * _xf(Vector3(0, 30, 0), Vector3(560, 60, 520), Vector3(0, 20, 0)), Color("2f2826"), 0.2, rng)
	var mi := MeshInstance3D.new()
	mi.mesh = b.commit()
	mi.material_override = B3Mats.vcol()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_keep(mi)
	var lava := MeshInstance3D.new()
	lava.mesh = B3Mats.cyl(34.0, 34.0, 1.0, 18)
	lava.material_override = B3Mats.glow(Color(1.0, 0.42, 0.12), 3.0)
	lava.position = Vector3(-430, 169.0, -320)
	lava.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_keep(lava)
	var smoke := CPUParticles3D.new()
	smoke.amount = 14
	smoke.lifetime = 14.0
	smoke.preprocess = 14.0
	smoke.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	smoke.emission_sphere_radius = 18.0
	smoke.direction = Vector3(0.3, 1, 0)
	smoke.spread = 12.0
	smoke.gravity = Vector3.ZERO
	smoke.initial_velocity_min = 6.0
	smoke.initial_velocity_max = 9.0
	smoke.scale_amount_min = 30.0
	smoke.scale_amount_max = 55.0
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	smoke.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.32, 0.29, 0.28, 0.55)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smoke.material_override = smat
	smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	smoke.position = Vector3(-430, 175.0, -320)
	smoke.visibility_aabb = AABB(Vector3(-120, -20, -120), Vector3(240, 260, 240))
	_keep(smoke)


# ================================================================== scenery
func _scenery() -> void:
	_rng.seed = hash(map_id + "scenery")
	_inst = {}
	_bld = []
	for i in CH * CH:
		_bld.append(Builder.new())
	_glass = Builder.new()
	_shapes = []
	for pv in (_d.pads as Array):
		_put(pv)
	for lv in (_d.lines as Array):
		_draw_line(lv)
	for pv in (_d.props as Array):
		_put_prop(pv)
	for pv in (_d.pools as Array):
		var pd: Dictionary = pv
		if bool(pd.get("flat", true)):
			_mark(float(pd.x), float(pd.z), float(pd.r) + 3.0)
	if map_id == "town":
		_town_streets()
	if map_id == "pass":
		_pass_rocks()
	_near_ring()
	_wild()
	_ground_detail()
	if map_id == "farmland":
		_crops()


func _mark(x: float, z: float, r: float) -> void:
	var rc := int(ceil(r / STEP))
	var ci := roundi((x + HALF) / STEP)
	var cj := roundi((z + HALF) / STEP)
	for dj in range(-rc, rc + 1):
		for di in range(-rc, rc + 1):
			var xi := ci + di
			var zi := cj + dj
			if xi < 0 or zi < 0 or xi >= N or zi >= N:
				continue
			if di * di + dj * dj <= rc * rc:
				_busy[zi * N + xi] = 1


## Is (x, z) free for a tree or a rock?
func _free(x: float, z: float, clear := 1.5, max_slope := 0.45) -> bool:
	if absf(x) > HALF - 3.0 or absf(z) > HALF - 3.0:
		return false
	var k := _k(x, z)
	if _busy[k] != 0 or _road_d[k] < _road_hw + clear:
		return false
	if _wet(x, z):
		return false
	return 1.0 - normal_at(x, z).y <= max_slope


## In or right next to water (during building, before `waters` is set).
func _wet(x: float, z: float) -> bool:
	if bool(_d.sea) and z > float(_d.zmin) and height_at(x, z) < 0.35:
		return true
	for lv in (_d.lakes as Array):
		var lk: Dictionary = lv
		var dx := x - float(lk.x)
		var dz := z - float(lk.z)
		var r := float(lk.r) + 4.0
		if dx * dx + dz * dz < r * r:
			return true
	return false


## Adds one tree/rock/bush instance. `body`: it gets a collider that blasts can uproot.
func _plant(kind: String, x: float, z: float, s: float, tint: Color, body := true, yaw := -1.0) -> void:
	if yaw < 0.0:
		yaw = _rng.randf() * TAU
	var y := height_at(x, z) - 0.05
	var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s, s)), Vector3(x, y, z))
	if not _inst.has(kind):
		_inst[kind] = []
	var col := body and SHAPES.has(kind) and absf(x) < B3Defs.BOUNDS and absf(z) < B3Defs.BOUNDS and _slot >= 0
	(_inst[kind] as Array).append([xf, tint, col, s, yaw, _slot if col else -1])
	_slot = -1


## Starts planting spot number `slot`: its own random numbers, and the
## number an uprootable thing planted there gets.
func _spot(slot: int) -> void:
	_slot = slot
	_rng.seed = hash(map_id) * 1000003 + slot * 7919


func _leaf_tint() -> Color:
	var b := _rng.randf_range(0.86, 1.04)
	return Color(b * _rng.randf_range(0.92, 1.06), b * _rng.randf_range(0.95, 1.04), b * _rng.randf_range(0.88, 1.0))


func _rock_tint() -> Color:
	var t := Color(0.72, 0.71, 0.69)
	match map_id:
		"desert":
			t = Color(0.95, 0.74, 0.5)
		"snow":
			t = Color(0.84, 0.88, 0.94)
		"volcano":
			t = Color(0.3, 0.27, 0.26)
		"pass":
			t = Color(0.86, 0.79, 0.67)
		"beach":
			t = Color(0.76, 0.74, 0.7)
	var b := _rng.randf_range(0.9, 1.08)
	return Color(t.r * b, t.g * b, t.b * b)


## Fallen boulders along the foot of the cliffs in the pass.
func _pass_rocks() -> void:
	for step in 21:
		for si in 2:
			var side := -1.0 if si == 0 else 1.0
			_spot(300000 + step * 2 + si)
			var x := -52.0 + step * 5.0 + _rng.randf_range(-1.5, 1.5)
			var base := height_at(x, 0.0)
			var z := 6.0 * float(side)
			while absf(z) < 24.0 and height_at(x, z) < base + 0.8:
				z += 0.75 * float(side)
			var zz := z - float(side) * _rng.randf_range(0.2, 1.0)
			if _rng.randf() < 0.7 and absf(zz) > 7.0 and _road_d[_k(x, zz)] > _road_hw + 1.0:
				_plant("rock", x, zz, _rng.randf_range(0.8, 1.9), _rock_tint())


## A few trees and rocks around the battle area (like the old maps), none
## in the middle.
func _near_ring() -> void:
	var tree := ""
	match map_id:
		"grassland":
			tree = "tree"
		"desert":
			tree = "cactus"
		"snow":
			tree = "pine_snow"
		"volcano":
			tree = "deadtree"
		"pass":
			tree = "olive"
	if tree == "":
		return
	var placed := 0
	var tries := 0
	while placed < 26 and tries < 400:
		tries += 1
		_spot(100000 + tries)
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(34.0, 64.0)
		var x := cos(a) * d
		var z := sin(a) * d
		if map_id == "volcano" and Vector2(x + 36, z + 36).length() < 24.0:
			continue
		if map_id == "pass" and absf(z) < 16.0:
			continue
		if not _free(x, z, 2.0, 0.5):
			continue
		var rock := _rng.randf() < (0.45 if map_id == "volcano" else 0.3)
		if rock:
			_plant("rock", x, z, _rng.randf_range(0.7, 1.4), _rock_tint())
		else:
			_plant(tree, x, z, _rng.randf_range(0.85, 1.3), _leaf_tint())
		placed += 1


## Forests, scattered trees, bushes and rocks over the outside of the map.
func _wild() -> void:
	var sp := 5.5
	var cells := int(2.0 * HALF / sp)
	for gz in cells:
		for gx in cells:
			_spot(200000 + gz * cells + gx)
			var x := -HALF + (gx + _rng.randf()) * sp
			var z := -HALF + (gz + _rng.randf()) * sp
			var r := sqrt(x * x + z * z)
			var roll := _rng.randf()
			if r < 68.0:
				continue
			var f := _forest(x, z)
			var h := height_at(x, z)
			var kind := ""
			var body := true
			var s := _rng.randf_range(0.85, 1.35)
			match map_id:
				"grassland":
					if roll < f * 0.85 + 0.015:
						kind = "pine" if h > 16.0 and _rng.randf() < 0.6 else "tree"
					elif roll < f * 0.85 + 0.015 + (0.12 if f > 0.02 and f < 0.5 else 0.01):
						kind = "bush"
					elif roll > 0.988:
						kind = "rock"
				"snow":
					if roll < f * 0.9 + 0.03:
						kind = "pine_snow"
					elif roll > 0.985:
						kind = "rock"
				"desert":
					if roll < 0.022:
						kind = "cactus"
					elif roll < 0.05:
						kind = "shrub"
					elif roll > 0.978:
						kind = "rock"
				"volcano":
					if roll < f * 0.22 + 0.02:
						kind = "deadtree"
					elif roll > 0.95:
						kind = "rock"
				"beach":
					var dz := _coast(x) - z
					if dz < 70.0:
						if absf(x) > 140.0 and roll > 0.9 and dz > 0.0:
							kind = "rock"
					elif dz < 112.0:
						if roll < 0.06:
							kind = "bush"
						elif roll > 0.985:
							kind = "rock"
					elif roll < f * 0.7 + 0.03:
						kind = "tree"
					elif roll < f * 0.7 + 0.08:
						kind = "bush"
				"farmland":
					if roll < 0.006:
						kind = "tree"
					elif roll < 0.012:
						kind = "bush"
				"pass":
					var hp := h > 14.0
					if hp and roll < f * 0.5 + 0.06:
						kind = "pine"
					elif not hp and absf(x) > 60.0 and roll < 0.05 + f * 0.3:
						kind = "olive"
					elif roll < 0.13:
						kind = "shrub"
					elif roll > 0.955:
						kind = "rock"
				"town":
					var m := maxf(absf(x), absf(z))
					if m > 145.0 and roll < f * 0.6 + 0.05:
						kind = "tree"
					elif roll < 0.025:
						kind = "tree"
					elif roll < 0.04:
						kind = "bush"
			if kind == "":
				continue
			var steep := 0.5 if kind == "rock" else 0.42
			if map_id == "pass" and kind == "rock":
				steep = 0.8
			if not _free(x, z, 1.8, steep):
				continue
			if kind == "rock":
				s = _rng.randf_range(0.7, 2.2) if map_id != "volcano" else _rng.randf_range(0.8, 2.6)
				_plant(kind, x, z, s, _rock_tint())
			elif kind == "bush" or kind == "shrub":
				_plant(kind, x, z, _rng.randf_range(0.7, 1.3), _leaf_tint(), false)
			else:
				_plant(kind, x, z, s, _leaf_tint(), body)


## Grass tufts, pebbles and snow lumps (no collision), thickest in the middle.
func _ground_detail() -> void:
	var kind := "tuft"
	if map_id == "desert" or map_id == "volcano" or map_id == "snow":
		kind = "pebble"
	var flowers := map_id == "grassland" or map_id == "farmland" or map_id == "town"
	for i in 6400:
		var x: float
		var z: float
		if i < 1100:
			x = _rng.randf_range(-62.0, 62.0)
			z = _rng.randf_range(-62.0, 62.0)
			if map_id == "volcano" and Vector2(x + 36, z + 36).length() < 20.0:
				x = -x
				z = -z
		else:
			x = _rng.randf_range(-HALF + 2.0, HALF - 2.0)
			z = _rng.randf_range(-HALF + 2.0, HALF - 2.0)
		var k := _k(x, z)
		if _road_d[k] < _road_hw + 0.5 or _busy[k] != 0 or _wet(x, z):
			continue
		if map_id == "town" and absf(x) < 40.0 and absf(z) < 40.0:
			continue
		var kk := kind
		if map_id == "beach" and _coast(x) - z < 64.0:
			kk = "pebble" if _rng.randf() < 0.3 else ""
			if kk == "":
				continue
		var c := _cols[k].darkened(_rng.randf_range(0.05, 0.25))
		if kk == "tuft" and flowers and _rng.randf() < 0.08:
			c = [Color("ffe066"), Color("ff8fb8"), Color("ffffff"), Color("9fd0ff")][_rng.randi() % 4]
		var s := _rng.randf_range(0.6, 1.4)
		var y := height_at(x, z) + 0.03
		var b := Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s * _rng.randf_range(0.8, 1.5), s))
		if not _inst.has(kk):
			_inst[kk] = []
		(_inst[kk] as Array).append([Transform3D(b, Vector3(x, y, z)), c, false, s, 0.0])


## Farmland: rows of wheat, corn and cabbages in the outer fields, and bales.
func _crops() -> void:
	var count := 0
	for fz in range(-3, 4):
		for fx in range(-3, 4):
			var crop := _crop(fx, fz)
			if crop != 0 and crop != 1 and crop != 4:
				continue
			var x0 := fx * FIELD - 18.0
			var z0 := fz * FIELD - 30.0
			var cx := x0 + FIELD * 0.5
			var cz := z0 + FIELD * 0.5
			if sqrt(cx * cx + cz * cz) < 70.0 or sqrt(cx * cx + cz * cz) > 175.0:
				continue
			var kind: String = ["wheat", "cabbage", "", "", "corn"][crop]
			var sx := _stripe_x(fx, fz)
			var row := 3.0 if kind != "corn" else 1.5
			var stepv := 2.4 if kind == "wheat" else (1.6 if kind == "cabbage" else 1.4)
			var a := 3.0 + row * 0.5
			while a < FIELD - 3.0:
				var b := 3.0
				while b < FIELD - 3.0:
					var x := x0 + (b if sx else a)
					var z := z0 + (a if sx else b)
					b += stepv
					var k := _k(x, z)
					if _road_d[k] < _road_hw + 1.5 or _busy[k] != 0 or _wet(x, z) or count > 8000:
						continue
					var s := _rng.randf_range(0.85, 1.15)
					var tint := Color.WHITE.darkened(_rng.randf_range(0.0, 0.15))
					var xf := Transform3D(Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, height_at(x, z) - 0.03, z))
					if not _inst.has(kind):
						_inst[kind] = []
					(_inst[kind] as Array).append([xf, tint, false, s, 0.0])
					count += 1
				a += row
			if kind == "wheat":
				for i in _rng.randi_range(3, 6):
					var bx := x0 + _rng.randf_range(6.0, FIELD - 6.0)
					var bz := z0 + _rng.randf_range(6.0, FIELD - 6.0)
					if _free(bx, bz, 2.0, 0.3):
						_plant("bale", bx, bz, 1.0, Color.WHITE, false)


# ------------------------------------------------------- buildings & things
func _bd(p: Vector3) -> Builder:
	return _bld[_chunk_of(p)]


static func _xf(p: Vector3, s := Vector3.ONE, rot := Vector3.ZERO) -> Transform3D:
	var bs := Basis.IDENTITY
	if rot != Vector3.ZERO:
		bs = Basis.from_euler(rot * (PI / 180.0))
	return Transform3D(bs * Basis.from_scale(s), p)


## A box in building space `o` (centre c, size s, turned by rot degrees).
func _box(o: Transform3D, c: Vector3, s: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	_bd(o.origin).add(prim("box"), o * _xf(c, s, rot), col)


func _part(o: Transform3D, key: String, c: Vector3, s: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	_bd(o.origin).add(prim(key), o * _xf(c, s, rot), col)


func _rockpart(o: Transform3D, key: String, c: Vector3, s: Vector3, col: Color, rot := Vector3.ZERO) -> void:
	_bd(o.origin).add_flat(prim(key), o * _xf(c, s, rot), col, 0.18, _rng)


## A window pane (glows at night).
func _win(o: Transform3D, c: Vector3, s: Vector3) -> void:
	_glass.add(prim("box"), o * _xf(c, s), Color.WHITE)


func _solid(o: Transform3D, c: Vector3, s: Vector3) -> void:
	_shapes.append(["box", o * Transform3D(Basis.IDENTITY, c), s])


func _solid_cyl(o: Transform3D, c: Vector3, r: float, h: float) -> void:
	_shapes.append(["cyl", o * Transform3D(Basis.IDENTITY, c), Vector3(r, h, r)])


func _put(pv: Dictionary) -> void:
	var t := String(pv.t)
	var x := float(pv.x)
	var z := float(pv.z)
	var o := Transform3D(Basis(Vector3.UP, float(pv.yaw)), Vector3(x, float(pv.get("y", height_at(x, z))) - 0.05, z))
	match t:
		"house":
			var walls := [Color("f2ead8"), Color("f4e1b8"), Color("e8d2c0"), Color("dfe8ef")]
			var roofs := [Color("b8473a"), Color("6a4a42"), Color("4d6a8a"), Color("8a3d33")]
			_house(o, 6.0, 8.0, walls[_rng.randi() % walls.size()], roofs[_rng.randi() % roofs.size()])
		"barn":
			_barn(o)
		"silo":
			_silo(o)
		"shed":
			_box(o, Vector3(0, 1.2, 0), Vector3(4.0, 2.4, 3.2), Color("9c7a52"))
			_box(o, Vector3(0, 2.55, 0), Vector3(4.6, 0.25, 3.8), Color("5c4a3a"), Vector3(8, 0, 0))
			_solid(o, Vector3(0, 1.3, 0), Vector3(4.0, 2.6, 3.2))
		"cabin":
			_cabin(o)
		"adobe":
			_adobe(o, float(pv.w), float(pv.d), float(pv.f))
		"villa":
			_villa(o, float(pv.w), float(pv.d), float(pv.f))
		"lighthouse":
			_lighthouse(o)
		"windmill":
			_windmill(o)
		"church":
			_church(o)
		"townhouse":
			_townhouse(o, float(pv.w), float(pv.d), int(pv.f), pv.col, bool(pv.roof))
		"ruins":
			_ruins(o)


func _house(o: Transform3D, w: float, d: float, wall: Color, roof: Color) -> void:
	var h := 3.0
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), wall)
	_box(o, Vector3(0, 0.2, 0), Vector3(w + 0.3, 0.4, d + 0.3), wall.darkened(0.3))
	_part(o, "prism", Vector3(0, h + 1.15, 0), Vector3(w + 0.8, 2.3, d + 0.6), roof)
	_box(o, Vector3(0, 1.0, d * 0.5 + 0.03), Vector3(1.0, 2.0, 0.1), Color("6b4428"))
	for sx in [-1.0, 1.0]:
		_win(o, Vector3(sx * w * 0.3, 1.75, d * 0.5 + 0.04), Vector3(0.9, 0.9, 0.06))
		_win(o, Vector3(sx * w * 0.3, 1.75, -d * 0.5 - 0.04), Vector3(0.9, 0.9, 0.06))
		_win(o, Vector3(sx * (w * 0.5 + 0.04), 1.75, d * 0.2), Vector3(0.06, 0.9, 0.9))
		_win(o, Vector3(sx * (w * 0.5 + 0.04), 1.75, -d * 0.2), Vector3(0.06, 0.9, 0.9))
	_box(o, Vector3(w * 0.25, h + 2.0, -d * 0.2), Vector3(0.6, 1.8, 0.6), Color("8a5a48"))
	_solid(o, Vector3(0, (h + 1.6) * 0.5, 0), Vector3(w, h + 1.6, d))


func _barn(o: Transform3D) -> void:
	var w := 9.0
	var d := 13.0
	var h := 5.0
	var red := Color("b23a2e")
	var white := Color("f2efe6")
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), red)
	_part(o, "prism", Vector3(0, h + 1.8, 0), Vector3(w + 0.9, 3.6, d + 0.6), Color("5a3a34"))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_box(o, Vector3(sx * w * 0.5, h * 0.5, sz * d * 0.5), Vector3(0.32, h, 0.32), white)
	_box(o, Vector3(0, 1.9, d * 0.5 + 0.05), Vector3(3.8, 3.8, 0.1), Color("8e2c24"))
	_box(o, Vector3(0, 1.9, d * 0.5 + 0.12), Vector3(0.25, 5.2, 0.1), white, Vector3(0, 0, 45))
	_box(o, Vector3(0, 1.9, d * 0.5 + 0.12), Vector3(0.25, 5.2, 0.1), white, Vector3(0, 0, -45))
	_box(o, Vector3(0, 3.85, d * 0.5 + 0.1), Vector3(4.0, 0.25, 0.12), white)
	_box(o, Vector3(0, h + 1.1, d * 0.5 + 0.34), Vector3(1.5, 1.5, 0.1), white)
	_box(o, Vector3(0, h + 1.1, d * 0.5 + 0.4), Vector3(1.1, 1.1, 0.1), Color("3a2a26"))
	_solid(o, Vector3(0, (h + 2.0) * 0.5, 0), Vector3(w, h + 2.0, d))


func _silo(o: Transform3D) -> void:
	_part(o, "cyl:14:1", Vector3(0, 5.5, 0), Vector3(4.2, 11.0, 4.2), Color("c9ced6"))
	for y in [3.0, 6.0, 9.0]:
		_part(o, "cyl:14:1", Vector3(0, y, 0), Vector3(4.32, 0.25, 4.32), Color("99a2ad"))
	_part(o, "sph:14", Vector3(0, 11.0, 0), Vector3(4.3, 2.6, 4.3), Color("8fa6bf"))
	_solid_cyl(o, Vector3(0, 6.0, 0), 2.1, 12.0)


func _cabin(o: Transform3D) -> void:
	var w := 6.0
	var d := 7.0
	var h := 2.8
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), Color("8a5a35"))
	for i in 5:
		_box(o, Vector3(0, 0.35 + i * 0.55, 0), Vector3(w + 0.12, 0.1, d + 0.12), Color("6b4428"))
	_part(o, "prism", Vector3(0, h + 1.05, 0), Vector3(w + 1.0, 2.2, d + 0.9), Color("6b4428"))
	_part(o, "prism", Vector3(0, h + 1.17, 0), Vector3(w + 0.8, 2.15, d + 0.8), Color("f4f8ff"))
	_box(o, Vector3(0, 0.95, d * 0.5 + 0.06), Vector3(1.0, 1.9, 0.1), Color("4a2e1c"))
	for sx in [-1.0, 1.0]:
		_win(o, Vector3(sx * 1.8, 1.6, d * 0.5 + 0.08), Vector3(0.8, 0.8, 0.06))
	_box(o, Vector3(-w * 0.28, h + 1.9, -d * 0.2), Vector3(0.7, 2.0, 0.7), Color("8f949c"))
	_solid(o, Vector3(0, (h + 1.5) * 0.5, 0), Vector3(w, h + 1.5, d))


func _adobe(o: Transform3D, w: float, d: float, h: float) -> void:
	var cols := [Color("d9a877"), Color("e0b48a"), Color("c99566"), Color("e6c29a")]
	var c: Color = cols[_rng.randi() % cols.size()]
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), c)
	_box(o, Vector3(0, h + 0.2, d * 0.5 - 0.15), Vector3(w, 0.4, 0.3), c.darkened(0.08))
	_box(o, Vector3(0, h + 0.2, -d * 0.5 + 0.15), Vector3(w, 0.4, 0.3), c.darkened(0.08))
	_box(o, Vector3(w * 0.5 - 0.15, h + 0.2, 0), Vector3(0.3, 0.4, d), c.darkened(0.08))
	_box(o, Vector3(-w * 0.5 + 0.15, h + 0.2, 0), Vector3(0.3, 0.4, d), c.darkened(0.08))
	_box(o, Vector3(0, 1.0, d * 0.5 + 0.04), Vector3(1.1, 2.0, 0.1), Color("5a3a24"))
	_win(o, Vector3(w * 0.3, 1.8, d * 0.5 + 0.05), Vector3(0.7, 0.7, 0.06))
	_win(o, Vector3(-w * 0.3, 1.8, d * 0.5 + 0.05), Vector3(0.7, 0.7, 0.06))
	for i in 4:
		_part(o, "cyl:6:1", Vector3(-w * 0.36 + i * w * 0.24, h - 0.35, d * 0.5 + 0.3), Vector3(0.2, 0.7, 0.2), Color("6b4a2c"), Vector3(90, 0, 0))
	_solid(o, Vector3(0, (h + 0.4) * 0.5, 0), Vector3(w, h + 0.4, d))


func _villa(o: Transform3D, w: float, d: float, h: float) -> void:
	var white := Color("f6f3ec")
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), white)
	if _rng.randf() < 0.5:
		_part(o, "prism", Vector3(0, h + 0.7, 0), Vector3(w + 0.5, 1.4, d + 0.4), Color("c8643c"))
	else:
		_box(o, Vector3(0, h + 0.15, 0), Vector3(w + 0.2, 0.3, d + 0.2), Color("e8e2d6"))
	var blue := Color("2f6fb5")
	_box(o, Vector3(0, 1.0, d * 0.5 + 0.05), Vector3(1.0, 2.0, 0.1), blue)
	for sx in [-1.0, 1.0]:
		_win(o, Vector3(sx * w * 0.3, 2.0, d * 0.5 + 0.05), Vector3(0.7, 0.9, 0.06))
		_box(o, Vector3(sx * w * 0.3 - 0.55, 2.0, d * 0.5 + 0.06), Vector3(0.35, 1.0, 0.08), blue)
		_box(o, Vector3(sx * w * 0.3 + 0.55, 2.0, d * 0.5 + 0.06), Vector3(0.35, 1.0, 0.08), blue)
	_solid(o, Vector3(0, (h + 0.8) * 0.5, 0), Vector3(w, h + 0.8, d))


func _lighthouse(o: Transform3D) -> void:
	_part(o, "cyl:12:1", Vector3(0, 1.0, 0), Vector3(6.6, 2.0, 6.6), Color("9a948a"))
	var cols := [Color("f4f2ec"), Color("d23a32"), Color("f4f2ec")]
	var r := 2.2
	for i in 3:
		var r2 := r - 0.22
		_part(o, "cyl:14:%.3f" % (r2 / r), Vector3(0, 2.0 + i * 5.0 + 2.5, 0), Vector3(r * 2.0, 5.0, r * 2.0), cols[i])
		r = r2
	_part(o, "cyl:14:1", Vector3(0, 17.2, 0), Vector3(4.2, 0.3, 4.2), Color("3a3d44"))
	_glass.add(prim("cyl:12:1"), o * _xf(Vector3(0, 18.3, 0), Vector3(2.6, 1.9, 2.6)), Color.WHITE)
	_part(o, "cyl:12:0", Vector3(0, 20.0, 0), Vector3(3.2, 1.6, 3.2), Color("d23a32"))
	_solid_cyl(o, Vector3(0, 10.0, 0), 2.3, 20.0)


func _windmill(o: Transform3D) -> void:
	_part(o, "cyl:12:0.72", Vector3(0, 5.5, 0), Vector3(6.4, 11.0, 6.4), Color("ece4d4"))
	_part(o, "cyl:12:0", Vector3(0, 12.4, 0), Vector3(5.4, 3.0, 5.4), Color("7a4a32"))
	_box(o, Vector3(0, 1.1, 3.0), Vector3(1.2, 2.2, 0.3), Color("6b4428"))
	_win(o, Vector3(0, 6.5, 2.65), Vector3(0.8, 1.0, 0.1))
	var hub := Vector3(0, 11.0, 3.2)
	_part(o, "sph:8", hub, Vector3.ONE * 0.9, Color("4a3a30"))
	for k in 4:
		var a := deg_to_rad(45.0 + 90.0 * k)
		var c := hub + Vector3(sin(a), cos(a), 0.0) * 4.4
		_box(o, c + Vector3(0, 0, 0.1), Vector3(1.2, 7.6, 0.08), Color("f2ede2"), Vector3(0, 0, -rad_to_deg(a)))
		_box(o, c + Vector3(0, 0, 0.16), Vector3(0.18, 8.2, 0.12), Color("6b4428"), Vector3(0, 0, -rad_to_deg(a)))
	_solid_cyl(o, Vector3(0, 6.0, 0), 3.1, 12.0)


func _church(o: Transform3D) -> void:
	var stone := Color("e8e2d6")
	_box(o, Vector3(0, 4.0, -2.0), Vector3(10.0, 8.0, 16.0), stone)
	_part(o, "prism", Vector3(0, 10.2, -2.0), Vector3(10.8, 4.4, 16.6), Color("6a4a42"))
	_box(o, Vector3(0, 8.0, 8.5), Vector3(5.0, 16.0, 5.0), stone.darkened(0.05))
	_part(o, "cyl:4:0", Vector3(0, 20.5, 8.5), Vector3(6.6, 9.0, 6.6), Color("4a5a6a"), Vector3(0, 45, 0))
	_part(o, "cyl:16:1", Vector3(0, 13.0, 11.03), Vector3(2.2, 0.1, 2.2), Color("f8f6f0"), Vector3(90, 0, 0))
	_box(o, Vector3(0, 1.4, 11.04), Vector3(1.8, 2.8, 0.1), Color("5a3a24"))
	for i in 4:
		for sx in [-1.0, 1.0]:
			_win(o, Vector3(sx * 5.04, 4.5, -8.0 + i * 4.0), Vector3(0.08, 3.0, 1.1))
	_solid(o, Vector3(0, 5.0, -2.0), Vector3(10.0, 10.0, 16.0))
	_solid(o, Vector3(0, 8.0, 8.5), Vector3(5.0, 16.0, 5.0))


func _townhouse(o: Transform3D, w: float, d: float, floors: int, col: Color, gable: bool) -> void:
	var h := floors * 3.0 + 0.6
	_box(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d), col)
	_box(o, Vector3(0, 0.25, 0), Vector3(w + 0.1, 0.5, d + 0.1), col.darkened(0.3))
	if gable:
		_part(o, "prism", Vector3(0, h + 1.2, 0), Vector3(w + 0.5, 2.4, d + 0.4), [Color("8a3d33"), Color("5a5f6a"), Color("6a4a42")][_rng.randi() % 3])
	else:
		_box(o, Vector3(0, h + 0.25, 0), Vector3(w + 0.3, 0.5, d + 0.3), col.darkened(0.18))
	var nx := maxi(1, int(w / 3.0))
	for f in floors:
		for i in nx:
			var x := -w * 0.5 + (i + 0.5) * w / nx
			var y := 1.7 + f * 3.0
			if f == 0 and i == nx >> 1:
				_box(o, Vector3(x, 1.1, d * 0.5 + 0.05), Vector3(1.2, 2.2, 0.1), col.darkened(0.55))
			else:
				_win(o, Vector3(x, y, d * 0.5 + 0.04), Vector3(1.0, 1.3, 0.06))
			_win(o, Vector3(x, y, -d * 0.5 - 0.04), Vector3(1.0, 1.3, 0.06))
	if _rng.randf() < 0.35:
		var aw: Color = [Color("d23a32"), Color("2f8f5a"), Color("2f6fb5"), Color("e0a020")][_rng.randi() % 4]
		_box(o, Vector3(0, 2.9, d * 0.5 + 0.7), Vector3(w * 0.85, 0.12, 1.5), aw, Vector3(-16, 0, 0))
	_solid(o, Vector3(0, h * 0.5, 0), Vector3(w, h, d))


func _ruins(o: Transform3D) -> void:
	var marble := Color("ece6d6")
	_box(o, Vector3(0, 0.5, 0), Vector3(10.4, 1.0, 16.4), marble.darkened(0.08))
	_box(o, Vector3(0, 1.1, 0), Vector3(9.2, 0.25, 15.2), marble)
	var spots: Array[Vector2] = []
	for i in 6:
		spots.append(Vector2(-4.0, -7.0 + i * 2.8))
		spots.append(Vector2(4.0, -7.0 + i * 2.8))
	for sv in spots:
		if _rng.randf() < 0.25:
			continue
		var full := _rng.randf() < 0.4
		var hh := 6.0 if full else _rng.randf_range(1.2, 4.5)
		_part(o, "cyl:10:0.88", Vector3(sv.x, 1.2 + hh * 0.5, sv.y), Vector3(1.1, hh, 1.1), marble)
		if full:
			_box(o, Vector3(sv.x, 7.35, sv.y), Vector3(1.4, 0.3, 1.4), marble)
		_solid_cyl(o, Vector3(sv.x, 1.2 + hh * 0.5, sv.y), 0.55, hh)
	_box(o, Vector3(0, 7.7, -5.6), Vector3(9.4, 0.6, 1.4), marble)
	_part(o, "cyl:10:1", Vector3(7.5, 0.55, 2.0), Vector3(1.1, 5.0, 1.1), marble, Vector3(90, 30, 0))
	_solid(o, Vector3(0, 0.6, 0), Vector3(10.4, 1.2, 16.4))


## Fences, stone walls and hedges, following the ground.
func _draw_line(lv: Dictionary) -> void:
	var t := String(lv.t)
	var a: Vector2 = lv.a
	var b: Vector2 = lv.b
	var length := a.distance_to(b)
	var piece := 2.4 if t == "fence" else (1.3 if t == "wall" else 1.6)
	var n := maxi(1, int(ceil(length / piece)))
	var prev := Vector3.ZERO
	var have := false
	var seg_start := Vector3.ZERO
	var seg_n := 0
	for i in n + 1:
		var p2 := a.lerp(b, float(i) / n)
		var k := _k(p2.x, p2.y)
		var gap := _road_d[k] < _road_hw + 1.5 or _wet(p2.x, p2.y) or (_busy[k] != 0 and t != "fence")
		var p := Vector3(p2.x, height_at(p2.x, p2.y), p2.y)
		if gap:
			have = false
			if seg_n > 0 and t == "wall":
				_wall_solid(seg_start, prev)
			seg_n = 0
			continue
		var o := Transform3D(Basis.IDENTITY, p)
		match t:
			"fence":
				_box(o, Vector3(0, 0.55, 0), Vector3(0.14, 1.1, 0.14), Color("8a6a48"))
				if have:
					for y in [0.45, 0.9]:
						_beam(prev + Vector3(0, y, 0), p + Vector3(0, y, 0), Vector2(0.07, 0.12), Color("a07c55"))
			"wall":
				if have:
					var mid := (prev + p) * 0.5
					var dir := (p - prev)
					var yaw := atan2(dir.x, dir.z) + _rng.randf_range(-0.06, 0.06)
					var g := _rng.randf_range(0.6, 0.8)
					var sc := Color(g, g * 0.98, g * 0.94)
					var hh := _rng.randf_range(0.7, 0.95)
					_bd(mid).add(prim("box"), Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(Vector3(0.75, hh, dir.length() + 0.1)), mid + Vector3(0, hh * 0.5 - 0.05, 0)), sc)
					if _rng.randf() < 0.6:
						var g2 := g * 1.08
						_bd(mid).add(prim("box"), Transform3D(Basis(Vector3.UP, yaw + 0.1) * Basis.from_scale(Vector3(0.55, 0.28, dir.length() * 0.7)), mid + Vector3(0, hh + 0.08, 0)), Color(g2, g2, g2 * 0.96))
				if seg_n == 0:
					seg_start = p
				seg_n += 1
				if seg_n >= 4:
					_wall_solid(seg_start, p)
					seg_start = p
					seg_n = 1
			"hedge":
				var hh2 := _rng.randf_range(1.4, 1.9)
				var hc := Color("3f7f35").lerp(Color("4f9440"), _rng.randf())
				_bd(p).add(prim("box"), _xf(p + Vector3(0, hh2 * 0.5 - 0.1, 0), Vector3(1.5, hh2, 1.5), Vector3(0, rad_to_deg(atan2(b.x - a.x, b.y - a.y)), 0)), hc)
				_bd(p).add_flat(prim("sph:7"), _xf(p + Vector3(0, hh2 - 0.1, 0), Vector3(1.9, 1.1, 1.9)), hc.lightened(0.05), 0.12, _rng)
		_mark(p.x, p.z, 1.6)
		prev = p
		have = true
	if t == "wall" and seg_n > 1:
		_wall_solid(seg_start, prev)


func _wall_solid(a: Vector3, b: Vector3) -> void:
	var d := b - a
	if Vector2(d.x, d.z).length() < 0.5:
		return
	var mid := (a + b) * 0.5
	_shapes.append(["box", Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), mid + Vector3(0, 0.45, 0)), Vector3(0.75, 1.0, Vector2(d.x, d.z).length())])


## A thin box from a to b (fence rails).
func _beam(a: Vector3, b: Vector3, th: Vector2, col: Color) -> void:
	var z := b - a
	var length := z.length()
	if length < 0.01:
		return
	z /= length
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	var bs := Basis(x, y, z) * Basis.from_scale(Vector3(th.x, th.y, length))
	_bd(a).add(prim("box"), Transform3D(bs, (a + b) * 0.5), col)


func _put_prop(pv: Dictionary) -> void:
	var t := String(pv.t)
	var x := float(pv.x)
	var z := float(pv.z)
	var s := float(pv.s)
	var o := Transform3D(Basis(Vector3.UP, float(pv.yaw)), Vector3(x, height_at(x, z), z))
	match t:
		"tor":
			_tor(o, s)
			_mark(x, z, s * 1.3)
		"basalt":
			_basalt(o, s)
			_mark(x, z, s * 1.2)
		"arch":
			_arch(o)
			_mark(x, z, 10.0)
		"stack":
			_stack(o, s)
		"snowman":
			_snowman(o)
			_mark(x, z, 1.2)
		"palms":
			for i in 11:
				_spot(400000 + int(absf(x) * 7.0 + absf(z)) * 16 + i)
				var a := TAU * i / 11.0 + _rng.randf_range(-0.2, 0.2)
				var rr := s + _rng.randf_range(3.0, 7.0)
				_plant("palm", x + cos(a) * rr, z + sin(a) * rr, _rng.randf_range(0.85, 1.15), _leaf_tint())
		"orchard":
			var ox := -24.0
			while ox <= 24.0:
				var oz := -24.0
				while oz <= 24.0:
					_spot(500000 + int((ox + 24.0) / 6.0) * 16 + int((oz + 24.0) / 6.0))
					if _free(x + ox, z + oz, 1.0, 0.5):
						_plant("tree", x + ox, z + oz, _rng.randf_range(0.75, 0.9), Color(1.0, 0.98, 0.9).darkened(_rng.randf() * 0.1), true, _rng.randf() * TAU)
					oz += 6.0
				ox += 6.0


func _rock_color() -> Color:
	var t := _rock_tint()
	return Color(0.82 * t.r / 0.72, 0.8 * t.g / 0.71, 0.78 * t.b / 0.69) * 0.86


## A pile of big boulders.
func _tor(o: Transform3D, s: float) -> void:
	var c := _rock_color()
	var n := _rng.randi_range(4, 6)
	for i in n:
		var a := TAU * i / n + _rng.randf_range(-0.3, 0.3)
		var d := s * _rng.randf_range(0.35, 0.7)
		var sz := Vector3(s * _rng.randf_range(0.7, 1.0), s * _rng.randf_range(0.5, 0.8), s * _rng.randf_range(0.6, 0.9))
		var p := Vector3(cos(a) * d, sz.y * 0.35, sin(a) * d)
		_rockpart(o, "sph:7", p, sz, c.darkened(_rng.randf() * 0.15), Vector3(_rng.randf_range(-15, 15), _rng.randf() * 360.0, 0))
		_shapes.append(["sphere", o * Transform3D(Basis.IDENTITY, p), Vector3.ONE * (sz.x + sz.y + sz.z) / 6.0 * 0.9])
	var top := Vector3(s * 0.8, s * 0.6, s * 0.7)
	_rockpart(o, "sph:7", Vector3(0, s * 0.62, 0), top, c.lightened(0.05), Vector3(10, _rng.randf() * 360.0, 0))
	_shapes.append(["sphere", o * Transform3D(Basis.IDENTITY, Vector3(0, s * 0.62, 0)), Vector3.ONE * s * 0.32])


## Hexagonal basalt columns (volcano).
func _basalt(o: Transform3D, s: float) -> void:
	var n := _rng.randi_range(10, 16)
	for i in n:
		var a := _rng.randf() * TAU
		var d := s * sqrt(_rng.randf())
		var hh := (1.0 - d / s) * s * 1.6 + _rng.randf_range(1.0, 3.0)
		var p := Vector3(cos(a) * d, hh * 0.5 - 0.3, sin(a) * d)
		_rockpart(o, "cyl:6:1", p, Vector3(1.5, hh, 1.5), Color("3a3434").lightened(_rng.randf() * 0.08), Vector3(0, _rng.randf() * 60.0, 0))
		_solid_cyl(o, p, 0.7, hh)


## A red rock arch (desert).
func _arch(o: Transform3D) -> void:
	var c1 := Color("c7683d")
	var c2 := Color("d98a55")
	for sx in [-1.0, 1.0]:
		for i in 4:
			var p := Vector3(sx * 6.0 + _rng.randf_range(-0.4, 0.4), 1.4 + i * 2.6, _rng.randf_range(-0.3, 0.3))
			_rockpart(o, "box", p, Vector3(3.4 - i * 0.2, 2.8, 3.2), c1 if i % 2 == 0 else c2, Vector3(0, _rng.randf_range(-10, 10), 0))
		_solid(o, Vector3(sx * 6.0, 5.4, 0), Vector3(3.2, 10.8, 3.0))
	_rockpart(o, "box", Vector3(0, 11.6, 0), Vector3(15.5, 2.6, 3.4), c2, Vector3(0, 0, 0))
	_rockpart(o, "sph:8", Vector3(-3.5, 12.6, 0), Vector3(6.0, 2.6, 3.4), c1)
	_rockpart(o, "sph:8", Vector3(3.8, 12.4, 0), Vector3(6.5, 2.4, 3.2), c1)
	_solid(o, Vector3(0, 11.6, 0), Vector3(15.5, 2.6, 3.4))


## A rock pillar standing in the sea.
func _stack(o: Transform3D, s: float) -> void:
	var c := Color("9a9184")
	var y := -9.0
	var w := s
	while y < s * 1.8:
		var hh := s * 0.7
		_rockpart(o, "box", Vector3(_rng.randf_range(-0.4, 0.4), y + hh * 0.5, _rng.randf_range(-0.4, 0.4)), Vector3(w, hh, w * 0.9), c.darkened(_rng.randf() * 0.15), Vector3(0, _rng.randf() * 90.0, 0))
		y += hh * 0.85
		w *= 0.86
	_rockpart(o, "sph:7", Vector3(0, y + w * 0.1, 0), Vector3(w * 1.1, w * 0.5, w), Color("6f9a4a"))


func _snowman(o: Transform3D) -> void:
	var white := Color("f6f9ff")
	_part(o, "sph:12", Vector3(0, 0.55, 0), Vector3.ONE * 1.2, white)
	_part(o, "sph:12", Vector3(0, 1.38, 0), Vector3.ONE * 0.9, white)
	_part(o, "sph:12", Vector3(0, 2.02, 0), Vector3.ONE * 0.64, white)
	for sx in [-1.0, 1.0]:
		_part(o, "sph:6", Vector3(sx * 0.11, 2.1, 0.28), Vector3.ONE * 0.08, Color("1a1a1a"))
		_part(o, "cyl:5:0.5", Vector3(sx * 0.62, 1.55, 0), Vector3(0.06, 0.9, 0.06), Color("5a3a24"), Vector3(0, 0, -sx * 55.0))
	_part(o, "cyl:6:0", Vector3(0, 2.0, 0.42), Vector3(0.12, 0.38, 0.12), Color("ff8a2a"), Vector3(90, 0, 0))
	_part(o, "cyl:10:1", Vector3(0, 2.28, 0), Vector3(0.8, 0.05, 0.8), Color("222222"))
	_part(o, "cyl:10:1", Vector3(0, 2.5, 0), Vector3(0.5, 0.45, 0.5), Color("222222"))
	_box(o, Vector3(0, 1.75, 0), Vector3(0.72, 0.14, 0.72), Color("d23a32"))


## Town: road surfaces with kerbs and lane marks, and street lamps.
func _town_streets() -> void:
	var asphalt := Color("4a4c52")
	for rv in (_d.roads as Array):
		var pts: PackedVector2Array = (rv as Dictionary).pts
		var i := 0
		while i + 2 < pts.size():
			var a := pts[i]
			var b := pts[i + 2]
			i += 2
			var dir := (b - a).normalized()
			var bend := (pts[i - 1] - a).normalized().dot(dir) < 0.98
			var sd := Vector2(-dir.y, dir.x)
			var ya := height_at(a.x, a.y)
			var yb := height_at(b.x, b.y)
			var am := Vector3(a.x, ya + 0.05, a.y)
			var bm := Vector3(b.x, yb + 0.05, b.y)
			var s3 := Vector3(sd.x, 0, sd.y)
			_bd(am).quad(am - s3 * _road_hw, am + s3 * _road_hw, bm + s3 * _road_hw, bm - s3 * _road_hw, asphalt)
			# kerbs and pavement (not across other streets)
			for sg in [-1.0, 1.0]:
				var mid := (a + b) * 0.5 + sd * float(sg) * (_road_hw + 1.2)
				if bend or _road_d[_k(mid.x, mid.y)] < _road_hw + 0.6:
					continue
				var o1 := am + s3 * float(sg) * _road_hw + Vector3(0, 0.07, 0)
				var o2 := am + s3 * float(sg) * (_road_hw + 2.4) + Vector3(0, 0.07, 0)
				var o3 := bm + s3 * float(sg) * (_road_hw + 2.4) + Vector3(0, 0.07, 0)
				var o4 := bm + s3 * float(sg) * _road_hw + Vector3(0, 0.07, 0)
				_bd(am).quad(o1, o2, o3, o4, Color("b9b6ae"))
			if i % 4 == 0:
				var cm := (am + bm) * 0.5 + Vector3(0, 0.02, 0)
				_bd(cm).add(prim("box"), Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)) * Basis.from_scale(Vector3(0.22, 0.04, 2.0)), cm), Color("f2f0e6"))
		# lamps every 24 m, alternating sides
		var j := 6
		var sgn := 1.0
		while j < pts.size() - 6:
			var p := pts[j]
			var dir2 := (pts[j + 1] - pts[j - 1]).normalized()
			var sd2 := Vector2(-dir2.y, dir2.x) * sgn
			var lp := p + sd2 * (_road_hw + 1.6)
			var k := _k(lp.x, lp.y)
			if _road_d[k] > _road_hw + 1.0 and absf(lp.x) < HALF - 4.0 and absf(lp.y) < HALF - 4.0:
				var face := -sd2
				_lamp(Transform3D(Basis(Vector3.UP, atan2(face.x, face.y)), Vector3(lp.x, height_at(lp.x, lp.y), lp.y)))
			j += 16
			sgn = -sgn
	# lamps round the square
	for c in [Vector2(38, 38), Vector2(-38, 38), Vector2(38, -38), Vector2(-38, -38), Vector2(0, 38), Vector2(0, -38), Vector2(38, 0), Vector2(-38, 0)]:
		var cv: Vector2 = c
		_lamp(Transform3D(Basis(Vector3.UP, atan2(-cv.x, -cv.y)), Vector3(cv.x, height_at(cv.x, cv.y), cv.y)))


func _lamp(o: Transform3D) -> void:
	_part(o, "cyl:6:1", Vector3(0, 2.25, 0), Vector3(0.18, 4.5, 0.18), Color("3a3d44"))
	_box(o, Vector3(0, 4.45, 0.45), Vector3(0.1, 0.1, 1.0), Color("3a3d44"))
	_glass.add(prim("sph:8"), o * _xf(Vector3(0, 4.3, 0.9), Vector3.ONE * 0.45), Color.WHITE)


# ========================================================= meshes & helpers
## Collects many small meshes into one ArrayMesh with vertex colours.
class Builder:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var ix := PackedInt32Array()

	func add(a: Array, xf: Transform3D, col: Color) -> void:
		var pv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var pn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var base := v.size()
		v.append_array(xf * pv)
		var nb := xf.basis.inverse().transposed()
		for q in pn:
			n.append((nb * q).normalized())
		var cc := PackedColorArray()
		cc.resize(pv.size())
		cc.fill(col)
		c.append_array(cc)
		for q in pi:
			ix.append(base + q)

	## Same, but each face gets its own flat normal (chunky low-poly look).
	func add_flat(a: Array, xf: Transform3D, col: Color, shade := 0.0, rng: RandomNumberGenerator = null) -> void:
		var pv: PackedVector3Array = xf * (a[Mesh.ARRAY_VERTEX] as PackedVector3Array)
		var pi: PackedInt32Array = a[Mesh.ARRAY_INDEX]
		var base := v.size()
		var t := 0
		while t + 2 < pi.size():
			var p0 := pv[pi[t]]
			var p1 := pv[pi[t + 1]]
			var p2 := pv[pi[t + 2]]
			var fn := (p2 - p0).cross(p1 - p0).normalized()
			var fc := col
			if rng != null and shade > 0.0:
				fc = col.darkened(rng.randf() * shade)
			v.append(p0)
			v.append(p1)
			v.append(p2)
			n.append(fn)
			n.append(fn)
			n.append(fn)
			c.append(fc)
			c.append(fc)
			c.append(fc)
			ix.append(base)
			ix.append(base + 1)
			ix.append(base + 2)
			base += 3
			t += 3

	## A flat quad a-b-c-d (seen from above when the corners go clockwise).
	func quad(a: Vector3, b: Vector3, cc: Vector3, d: Vector3, col: Color) -> void:
		var base := v.size()
		var fn := (d - a).cross(b - a).normalized()
		if fn.y < 0.0:
			fn = -fn
			var tmp := b
			b = d
			d = tmp
		v.append_array(PackedVector3Array([a, b, cc, d]))
		n.append_array(PackedVector3Array([fn, fn, fn, fn]))
		c.append_array(PackedColorArray([col, col, col, col]))
		ix.append_array(PackedInt32Array([base, base + 1, base + 3, base + 1, base + 2, base + 3]))

	func commit() -> ArrayMesh:
		if v.is_empty():
			return null
		return B3World._mesh(v, n, c, ix)


## Mesh arrays of a unit-sized primitive: "box", "sph:<segs>",
## "cyl:<segs>:<top/bottom>", "prism", "cap:<r>:<h>".
static func prim(key: String) -> Array:
	var a: Array = _prims.get(key, [])
	if not a.is_empty():
		return a
	var s := key.split(":")
	var m: PrimitiveMesh = null
	match s[0]:
		"box":
			m = BoxMesh.new()
		"sph":
			var sm := SphereMesh.new()
			sm.radius = 0.5
			sm.height = 1.0
			sm.radial_segments = s[1].to_int()
			sm.rings = maxi(3, s[1].to_int() >> 1)
			m = sm
		"cyl":
			var cm := CylinderMesh.new()
			cm.bottom_radius = 0.5
			cm.top_radius = 0.5 * s[2].to_float()
			cm.height = 1.0
			cm.radial_segments = s[1].to_int()
			cm.rings = 0
			m = cm
		"prism":
			m = PrismMesh.new()
		"cap":
			var cp := CapsuleMesh.new()
			cp.radius = s[1].to_float()
			cp.height = s[2].to_float()
			cp.radial_segments = 10
			cp.rings = 3
			m = cp
	a = m.get_mesh_arrays()
	_prims[key] = a
	return a


## The merged mesh of one kind of tree, rock, bush or crop (made once).
static func kind_mesh(kind: String) -> ArrayMesh:
	var m: ArrayMesh = _kmesh.get(kind)
	if m != null:
		return m
	var b := Builder.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(kind)
	match kind:
		"tree":
			b.add(prim("cyl:7:0.7"), _xf(Vector3(0, 0.9, 0), Vector3(0.52, 1.8, 0.52)), Color("7a4e2c"))
			b.add(prim("sph:10"), _xf(Vector3(0, 2.6, 0), Vector3.ONE * 2.5), Color("4fa83f"))
			b.add(prim("sph:8"), _xf(Vector3(0.6, 3.2, 0.2), Vector3.ONE * 1.7), Color("6cc24a"))
			b.add(prim("sph:8"), _xf(Vector3(-0.55, 2.3, -0.4), Vector3.ONE * 1.6), Color("3e8f36"))
		"pine", "pine_snow":
			b.add(prim("cyl:7:0.68"), _xf(Vector3(0, 0.6, 0), Vector3(0.44, 1.2, 0.44)), Color("6b4426"))
			for i in 3:
				var r := 1.4 - i * 0.35
				b.add(prim("cyl:9:0"), _xf(Vector3(0, 1.6 + i * 0.85, 0), Vector3(r * 2.0, 1.5, r * 2.0)), Color("2f6e4a").lightened(i * 0.05))
				if kind == "pine_snow":
					b.add(prim("cyl:9:0"), _xf(Vector3(0, 2.15 + i * 0.85, 0), Vector3(r * 1.5, 0.6, r * 1.5)), Color("f4f8ff"))
		"cactus":
			var g := Color("4f9a4a")
			b.add(prim("cap:0.28:2.6"), _xf(Vector3(0, 1.3, 0)), g)
			b.add(prim("cap:0.18:1.0"), _xf(Vector3(0.5, 1.5, 0)), g)
			b.add(prim("cap:0.18:0.8"), _xf(Vector3(-0.45, 1.2, 0)), g)
			b.add(prim("cyl:6:1"), _xf(Vector3(0.25, 1.25, 0), Vector3(0.5, 0.25, 0.25), Vector3(0, 0, 90)), g)
			b.add(prim("cyl:6:1"), _xf(Vector3(-0.22, 0.95, 0), Vector3(0.44, 0.22, 0.22), Vector3(0, 0, 90)), g)
			b.add(prim("sph:6"), _xf(Vector3(0, 2.62, 0), Vector3.ONE * 0.24), Color("ff7ab0"))
		"deadtree":
			var bark := Color("3a302c")
			b.add(prim("cyl:7:0.48"), _xf(Vector3(0, 1.3, 0), Vector3(0.5, 2.6, 0.5)), bark)
			b.add(prim("cyl:6:0.5"), _xf(Vector3(0.35, 2.0, 0), Vector3(0.2, 1.2, 0.2), Vector3(0, 0, -40)), bark)
			b.add(prim("cyl:6:0.5"), _xf(Vector3(-0.3, 1.6, 0), Vector3(0.18, 1.0, 0.18), Vector3(0, 0, 45)), bark)
		"palm":
			var top := Vector3.ZERO
			for i in 6:
				var p := Vector3(0.035 * i * i, 0.42 + i * 0.8, 0)
				b.add(prim("cyl:7:0.85"), _xf(p, Vector3(0.38 - i * 0.025, 0.86, 0.38 - i * 0.025), Vector3(0, 0, -i * 3.0)), Color("8a6a45").lightened((i % 2) * 0.08))
				top = p + Vector3(0.05, 0.4, 0)
			for i in 7:
				var a := TAU * i / 7.0
				var p2 := top + Vector3(sin(a), -0.15, cos(a)) * 1.1
				b.add(prim("sph:8"), _xf(p2, Vector3(0.55, 0.12, 2.4), Vector3(22, rad_to_deg(a), 0)), Color("4f9e3a").lightened((i % 3) * 0.05))
			for i in 3:
				var a2 := TAU * i / 3.0
				b.add(prim("sph:6"), _xf(top + Vector3(sin(a2) * 0.25, -0.25, cos(a2) * 0.25), Vector3.ONE * 0.3), Color("6b4a2a"))
		"olive":
			b.add(prim("cyl:6:0.6"), _xf(Vector3(0, 0.7, 0), Vector3(0.42, 1.4, 0.42), Vector3(0, 0, 8)), Color("6e5a46"))
			b.add(prim("sph:8"), _xf(Vector3(0.1, 1.9, 0), Vector3(2.3, 1.3, 2.1)), Color("8a9a5b"))
			b.add(prim("sph:7"), _xf(Vector3(0.8, 2.3, 0.3), Vector3(1.5, 1.0, 1.4)), Color("9aab68"))
			b.add(prim("sph:7"), _xf(Vector3(-0.7, 1.8, -0.3), Vector3(1.4, 0.9, 1.4)), Color("7d8c50"))
		"rock":
			b.add_flat(prim("sph:7"), _xf(Vector3(0, 0.3, 0), Vector3(2.16, 1.26, 1.8), Vector3(25, 0, 0)), Color("d0ccc6"), 0.12, rng)
			b.add_flat(prim("sph:6"), _xf(Vector3(0.7, 0.2, 0.3), Vector3(1.1, 0.88, 1.21)), Color("dad6d0"), 0.12, rng)
		"bush", "shrub":
			var c0 := Color("4f9a3f") if kind == "bush" else Color("8f8a55")
			b.add(prim("sph:8"), _xf(Vector3(0, 0.45, 0), Vector3(1.5, 1.1, 1.5)), c0)
			b.add(prim("sph:7"), _xf(Vector3(0.55, 0.4, 0.2), Vector3.ONE * 1.0), c0.lightened(0.1))
			b.add(prim("sph:7"), _xf(Vector3(-0.5, 0.35, -0.2), Vector3.ONE * 0.9), c0.darkened(0.1))
		"tuft":
			b.add(prim("cyl:5:0"), _xf(Vector3(0, 0.175, 0), Vector3(0.18, 0.35, 0.18)), Color.WHITE)
		"pebble":
			b.add(prim("sph:6"), _xf(Vector3.ZERO, Vector3.ONE * 0.24), Color.WHITE)
		"wheat":
			for i in 4:
				var a3 := TAU * i / 4.0
				b.add(prim("cyl:4:0"), _xf(Vector3(sin(a3) * 0.14, 0.4, cos(a3) * 0.14), Vector3(0.14, 0.8, 0.14), Vector3(sin(a3) * 8.0, 0, cos(a3) * 8.0)), Color("e8c45a"))
		"corn":
			b.add(prim("cyl:5:0.5"), _xf(Vector3(0, 0.85, 0), Vector3(0.12, 1.7, 0.12)), Color("5f9e3a"))
			b.add(prim("sph:6"), _xf(Vector3(0, 0.9, 0.3), Vector3(0.12, 0.06, 0.8), Vector3(-25, 0, 0)), Color("6aa83e"))
			b.add(prim("sph:6"), _xf(Vector3(0, 1.2, -0.3), Vector3(0.12, 0.06, 0.8), Vector3(25, 0, 0)), Color("6aa83e"))
			b.add(prim("sph:6"), _xf(Vector3(0.09, 1.15, 0), Vector3(0.14, 0.34, 0.14)), Color("f2d24a"))
			b.add(prim("cyl:4:0"), _xf(Vector3(0, 1.85, 0), Vector3(0.1, 0.3, 0.1)), Color("d8c070"))
		"cabbage":
			b.add(prim("sph:7"), _xf(Vector3(0, 0.15, 0), Vector3(0.7, 0.45, 0.7)), Color("7cc45a"))
		"bale":
			b.add(prim("cyl:12:1"), _xf(Vector3(0, 0.75, 0), Vector3(1.5, 1.3, 1.5), Vector3(0, 0, 90)), Color("e2c26a"))
	m = b.commit()
	_kmesh[kind] = m
	return m


static func cloud_texture() -> NoiseTexture2D:
	if _clouds == null:
		var fn := FastNoiseLite.new()
		fn.seed = 4242
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.007
		fn.fractal_octaves = 5
		fn.fractal_gain = 0.55
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.56, 0.74, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(1, 1, 1, 0.75), Color(1, 1, 1, 0.95)])
		var nt := NoiseTexture2D.new()
		nt.width = 1024
		nt.height = 512
		nt.seamless = true
		nt.noise = fn
		nt.color_ramp = g
		_clouds = nt
	return _clouds


static func water_shader() -> Shader:
	if _water_shader == null:
		_water_shader = Shader.new()
		_water_shader.code = WATER_SHADER
	return _water_shader


const WATER_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

uniform vec4 shallow : source_color = vec4(0.36, 0.86, 0.84, 1.0);
uniform vec4 deep : source_color = vec4(0.05, 0.36, 0.62, 1.0);
uniform float wave = 0.12;
uniform float bright = 1.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 wpos;

float wv(vec2 p, float t) {
	return sin(p.x * 0.13 + t * 1.1) * 0.5 + sin(p.y * 0.19 - t * 1.3) * 0.35 + sin((p.x + p.y) * 0.07 + t * 0.6) * 0.45;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = wave * (1.0 - smoothstep(200.0, 330.0, length(wpos.xz)));
	float h = wv(wpos.xz, TIME) * amp;
	float hx = wv(wpos.xz + vec2(0.6, 0.0), TIME) * amp - h;
	float hz = wv(wpos.xz + vec2(0.0, 0.6), TIME) * amp - h;
	VERTEX.y += h;
	wpos.y += h;
	NORMAL = normalize(vec3(-hx / 0.6, 1.0, -hz / 0.6));
}

void fragment() {
	float zd = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, zd) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, zd);
#endif
	vec4 vp = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	vp.xyz /= vp.w;
	vec3 ground = (INV_VIEW_MATRIX * vec4(vp.xyz, 1.0)).xyz;
	float d = max(wpos.y - ground.y, 0.0);
	float k = smoothstep(0.0, 3.5, d);
	vec3 col = mix(shallow.rgb, deep.rgb, k);
	float sparkle = sin(wpos.x * 1.3 + TIME * 1.7) * sin(wpos.z * 1.1 - TIME * 1.3);
	col += vec3(0.05) * smoothstep(0.6, 1.0, sparkle);
	float lap = 0.07 + 0.06 * sin(TIME * 0.9 + wpos.x * 0.05);
	float foam = 1.0 - smoothstep(lap, lap + 0.05, d);
	foam = max(foam, (1.0 - smoothstep(0.0, 0.035, abs(d - lap - 0.3))) * 0.45);
	col = mix(col, vec3(1.0), foam * 0.85);
	ALBEDO = col * bright;
	ALPHA = max(mix(0.55, 0.94, k), foam * 0.9);
	ROUGHNESS = 0.1;
	SPECULAR = 0.6;
}
"""
