class_name B3Mats
## Shared meshes and materials for 3D Battle. Everything is made once and
## reused, so a hundred soldiers share a handful of resources.

static var _mats := {}
static var _meshes := {}
static var _ko := {}
static var _shaders := {}
static var flash_mat: StandardMaterial3D = null
static var font: Font = null


## Drops the shared resources (called when leaving 3D Battle), and the
## models' merged meshes made from them (B3Rig).
static func clear_cache() -> void:
	_mats.clear()
	_meshes.clear()
	_ko.clear()
	_shaders.clear()
	flash_mat = null
	B3Rig.clear_cache()


static func mat(c: Color, rough := 0.75, metal := 0.0) -> StandardMaterial3D:
	var key := "m%s|%.2f|%.2f" % [c.to_html(), rough, metal]
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		if metal > 0.0:
			m.metallic_specular = 0.7
		m.set_meta("plain", true)      # B3Rig can merge pieces painted with it
		_mats[key] = m
	return m


## The material of B3Rig's merged pieces: each vertex carries its piece's
## colour and, in UV, its roughness and metalness, so it looks just like
## mat() does on the separate pieces. `look`: "" as built, "ko" greyed out
## like ko() (knocked out), "char" scorched (a wrecked vehicle). `per_mesh`:
## for meshes with pieces in the team or skin colour, which every mesh
## gets as its own values ("team", "skin"), so fighters of every team and
## skin share their merged meshes. Only those meshes use it: every mesh with
## its own values takes room in a buffer the renderer has a limit for (see
## project.godot, rendering/limits/global_shader_variables/buffer_size).
static func rig_mat(look := "", per_mesh := false) -> ShaderMaterial:
	var key := "rig_%s%s" % [look, "_pm" if per_mesh else ""]
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = shader("rig_pm" if per_mesh else "rig")
		match look:
			"ko":
				m.set_shader_parameter("grey", 0.55)
				m.set_shader_parameter("dark", 0.12)
			"char":
				m.set_shader_parameter("grey", 0.6)
				m.set_shader_parameter("dark", 0.35)
		m.set_meta("rig_pm", per_mesh)
		_mats[key] = m
	return m


## Glowing (HDR) material: lava, lasers, muzzle flashes, lights.
static func glow(c: Color, energy := 2.0) -> StandardMaterial3D:
	var key := "g%s|%.2f" % [c.to_html(), energy]
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(c.r * energy, c.g * energy, c.b * energy, c.a)
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return m


## Flat see-through colour (team discs, ghosts, rings).
static func flat(c: Color, depth_test := true) -> StandardMaterial3D:
	var key := "f%s|%s" % [c.to_html(), depth_test]
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.no_depth_test = not depth_test
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[key] = m
	return m


## Shaded material that takes its colour from particle/vertex colours,
## multiplied by `tint` (like a MultiMesh instance colour).
static func vcol(unshaded := false, alpha := false, tint := Color.WHITE) -> StandardMaterial3D:
	var key := "v%s%s" % [unshaded, alpha]
	if tint != Color.WHITE:
		key += tint.to_html()
	var m: StandardMaterial3D = _mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = tint
		m.vertex_color_use_as_albedo = true
		m.vertex_color_is_srgb = true
		m.roughness = 0.9
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		if alpha:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key] = m
	return m


## A greyed-out copy of a material, for knocked-out units.
static func ko(m: Material) -> Material:
	if m == null:
		return null
	var id := m.get_instance_id()
	var k: Material = _ko.get(id)
	if k != null:
		return k
	if m is ShaderMaterial and m.has_meta("rig_pm"):
		k = rig_mat("ko", bool(m.get_meta("rig_pm")))
	elif m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
		var src := m as StandardMaterial3D
		var c := src.albedo_color
		var g := c.get_luminance()
		k = mat(c.lerp(Color(g, g, g), 0.55).darkened(0.12), src.roughness, src.metallic)
	else:
		k = m
	_ko[id] = k
	return k


static func white_flash() -> StandardMaterial3D:
	if flash_mat == null:
		flash_mat = StandardMaterial3D.new()
		flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		flash_mat.albedo_color = Color(1.0, 1.0, 1.0, 0.75)
		flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		flash_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return flash_mat


static func get_font() -> Font:
	if font == null:
		font = load("res://fonts/Nunito.ttf")
	return font


# ------------------------------------------------------------------ meshes
static func sphere(r: float, segs := 14) -> SphereMesh:
	var key := "s%.3f|%d" % [r, segs]
	var m: SphereMesh = _meshes.get(key)
	if m == null:
		m = SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = segs
		m.rings = maxi(4, segs / 2)
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func hemi(r: float) -> SphereMesh:
	var key := "h%.3f" % r
	var m: SphereMesh = _meshes.get(key)
	if m == null:
		m = SphereMesh.new()
		m.radius = r
		m.height = r
		m.is_hemisphere = true
		m.radial_segments = 16
		m.rings = 6
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func capsule(r: float, h: float) -> CapsuleMesh:
	h = maxf(h, r * 2.0 + 0.001)
	var key := "c%.3f|%.3f" % [r, h]
	var m: CapsuleMesh = _meshes.get(key)
	if m == null:
		m = CapsuleMesh.new()
		m.radius = r
		m.height = h
		m.radial_segments = 12
		m.rings = 4
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func box(s: Vector3) -> BoxMesh:
	var key := "b%.3f|%.3f|%.3f" % [s.x, s.y, s.z]
	var m: BoxMesh = _meshes.get(key)
	if m == null:
		m = BoxMesh.new()
		m.size = s
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func cyl(top: float, bottom: float, h: float, segs := 14) -> CylinderMesh:
	var key := "y%.3f|%.3f|%.3f|%d" % [top, bottom, h, segs]
	var m: CylinderMesh = _meshes.get(key)
	if m == null:
		m = CylinderMesh.new()
		m.top_radius = top
		m.bottom_radius = bottom
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func prism(s: Vector3, ltr := 0.5) -> PrismMesh:
	var key := "p%.3f|%.3f|%.3f|%.2f" % [s.x, s.y, s.z, ltr]
	var m: PrismMesh = _meshes.get(key)
	if m == null:
		m = PrismMesh.new()
		m.size = s
		m.left_to_right = ltr
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func torus(inner: float, outer: float) -> TorusMesh:
	var key := "t%.3f|%.3f" % [inner, outer]
	var m: TorusMesh = _meshes.get(key)
	if m == null:
		m = TorusMesh.new()
		m.inner_radius = inner
		m.outer_radius = outer
		m.rings = 24
		m.ring_segments = 8
		m.set_meta("k", key)
		_meshes[key] = m
	return m


static func quad(s: Vector2) -> QuadMesh:
	var key := "q%.3f|%.3f" % [s.x, s.y]
	var m: QuadMesh = _meshes.get(key)
	if m == null:
		m = QuadMesh.new()
		m.size = s
		m.set_meta("k", key)
		_meshes[key] = m
	return m


## Adds a mesh to `parent` at a local position/rotation (degrees) and scale.
static func add(parent: Node3D, mesh: Mesh, m: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	if rot != Vector3.ZERO:
		mi.rotation_degrees = rot
	if scl != Vector3.ONE:
		mi.scale = scl
	if not shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


# ----------------------------------------------------------------- shaders
static func shader(id: String) -> Shader:
	var s: Shader = _shaders.get(id)
	if s != null:
		return s
	s = Shader.new()
	match id:
		"pool":
			s.code = POOL_SHADER
		"fireball":
			s.code = FIREBALL_SHADER
		"hpbar":
			s.code = HPBAR_SHADER
		"ring":
			s.code = RING_SHADER
		"cloud":
			s.code = CLOUD_SHADER
		"rig":
			s.code = RIG_SHADER
		"rig_pm":
			s.code = RIG_SHADER.replace("uniform float dark = 0.0;", "uniform float dark = 0.0;\ninstance uniform vec4 skin = vec4(1.0);\ninstance uniform vec4 team = vec4(1.0);").replace("vec3 c = COLOR.rgb;", "vec3 c = COLOR.a < 0.25 ? skin.rgb : (COLOR.a < 0.75 ? team.rgb * UV2.x + UV2.y : COLOR.rgb);")
	_shaders[id] = s
	return s


static func shader_mat(id: String) -> ShaderMaterial:
	var key := "sh_" + id
	var m: ShaderMaterial = _mats.get(key)
	if m == null:
		m = ShaderMaterial.new()
		m.shader = shader(id)
		_mats[key] = m
	return m


const POOL_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform vec3 col_a : source_color = vec3(1.0, 0.3, 0.0);
uniform vec3 col_b : source_color = vec3(1.0, 0.8, 0.1);
uniform vec3 crust : source_color = vec3(0.2, 0.1, 0.08);
uniform float glow = 2.5;
uniform float speed = 1.0;
uniform float cells = 1.2;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 p = wpos.xz * cells;
	float t = TIME * speed;
	float n = sin(p.x * 1.7 + t * 1.3) * sin(p.y * 1.5 - t * 1.1);
	n += 0.6 * sin((p.x - p.y) * 2.3 + t * 2.1);
	n += 0.35 * sin(length(p + vec2(sin(t * 0.3), cos(t * 0.4)) * 3.0) * 3.0 - t * 2.5);
	float m = smoothstep(-0.9, 1.4, n);
	float cr = smoothstep(0.82, 1.0, m);
	vec3 c = mix(col_a, col_b, m);
	ALBEDO = mix(c * 0.4, crust, cr * 0.7);
	EMISSION = c * glow * (0.55 + 0.6 * m) * (1.0 - cr * 0.8);
	ROUGHNESS = 0.35;
	SPECULAR = 0.6;
}
"""

const FIREBALL_SHADER := """
shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
instance uniform float age = 0.0;
instance uniform float kind = 0.0;
void fragment() {
	vec3 hot = vec3(5.0, 3.6, 1.4);
	vec3 warm = vec3(2.6, 0.75, 0.12);
	vec3 smoke = vec3(0.16, 0.14, 0.13);
	if (kind > 0.5 && kind < 1.5) { hot = vec3(2.0, 5.0, 1.0); warm = vec3(0.3, 2.2, 0.2); smoke = vec3(0.1, 0.25, 0.08); }
	if (kind > 1.5) { hot = vec3(6.0, 6.0, 5.5); warm = vec3(3.5, 1.6, 0.4); smoke = vec3(0.25, 0.22, 0.2); }
	vec3 c = age < 0.35 ? mix(hot, warm, age / 0.35) : mix(warm, smoke, clamp((age - 0.35) / 0.4, 0.0, 1.0));
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	float a = (1.0 - smoothstep(0.55, 1.0, age)) * (1.0 - rim * rim * 0.6);
	if (kind > 2.5) { c = mix(vec3(0.95, 0.93, 0.9), vec3(0.55, 0.53, 0.5), age); a = (1.0 - age) * 0.75 * (1.0 - rim * rim * 0.6); }
	ALBEDO = c * (1.0 - rim * 0.35);
	ALPHA = a;
}
"""

const HPBAR_SHADER := """
shader_type spatial;
render_mode unshaded, depth_test_disabled, cull_disabled, shadows_disabled;
instance uniform float hp = 1.0;
instance uniform vec4 team : source_color = vec4(1.0);
void vertex() {
	// faces the camera, but keeps the bar's own size (big fighters get bigger bars)
	vec3 s = vec3(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[1].xyz), length(MODEL_MATRIX[2].xyz));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0] * s.x, INV_VIEW_MATRIX[1] * s.y, INV_VIEW_MATRIX[2] * s.z, MODEL_MATRIX[3]);
}
void fragment() {
	vec2 uv = UV;
	float border = step(uv.x, 0.03) + step(0.97, uv.x) + step(uv.y, 0.12) + step(0.88, uv.y);
	vec3 fill = mix(vec3(1.0, 0.25, 0.2), vec3(0.35, 1.0, 0.35), clamp(hp * 1.4 - 0.2, 0.0, 1.0));
	vec3 c = uv.x < hp ? fill : vec3(0.12, 0.1, 0.18);
	c = mix(c, team.rgb * 0.6, clamp(border, 0.0, 1.0));
	ALBEDO = c;
}
"""

const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
instance uniform float age = 0.0;
instance uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.7, 1.0);
void fragment() {
	ALBEDO = tint.rgb * 3.0;
	ALPHA = (1.0 - age) * tint.a;
}
"""

## B3Rig's merged pieces (see rig_mat): the same lighting as mat()'s
## StandardMaterial3D, with the colour (sRGB) from the vertex and the
## roughness and metalness from UV. grey/dark: B3Mats.ko()'s greying. (The
## "rig_pm" copy also has the per-mesh skin and team colours.)
const RIG_SHADER := """
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
uniform float grey = 0.0;
uniform float dark = 0.0;
void fragment() {
	vec3 c = COLOR.rgb;
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	c = mix(c, vec3(l), grey) * (1.0 - dark);
	ALBEDO = mix(pow((c + vec3(0.055)) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
	ROUGHNESS = UV.x;
	METALLIC = UV.y;
	SPECULAR = UV.y > 0.0 ? 0.7 : 0.5;
}
"""

const CLOUD_SHADER := """
shader_type spatial;
render_mode cull_back, depth_draw_opaque;
instance uniform float heat = 1.0;
instance uniform float fade = 1.0;
void fragment() {
	vec3 smoke = vec3(0.62, 0.56, 0.52);
	vec3 fire = vec3(3.2, 1.3, 0.35);
	float rim = 1.0 - abs(dot(NORMAL, VIEW));
	ALBEDO = mix(smoke, vec3(1.0, 0.55, 0.2), heat * 0.6);
	EMISSION = fire * heat * (1.0 - rim * 0.5);
	ROUGHNESS = 1.0;
	ALPHA = fade;
}
"""
