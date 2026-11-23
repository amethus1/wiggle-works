class_name B3Chute
extends Node3D
## A pilot (or helicopter crew member) who bailed out of a doomed aircraft
## (B3Aircraft._eject): pops up out of the cockpit, the striped parachute
## opens with a fwump, and they drift down swinging gently. On landing the
## canopy flops over, then they vanish in a little puff. It's only for show
## (an effect, B3Fx.chute, so friends see it too): it doesn't fight or count.

const POP_T := 0.45          # flying up out of the cockpit before the chute opens
const FALL := 2.6            # m/s down under an open chute (normal gravity)
const LIFE := 30.0           # (gone after this, whatever happens)

static var _canopy_mats := {}

var battle = null
var vel := Vector3.ZERO
var col := Color.WHITE
var t := 0.0
var open := 0.0              # 0 folded .. 1 fully open
var landed := -1.0           # seconds since it landed (-1: still in the air)
var _drift := Vector3.ZERO
var _sway := 0.0
var _canopy: Node3D = null
var _pilot: Node3D = null
var _lines: Node3D = null
var _gk := 1.0


## A canopy material: no back faces culled, so it shows from underneath too
## (first person, looking up at it).
static func canopy_mat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	var m: StandardMaterial3D = _canopy_mats.get(key)
	if m == null:
		m = StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = 0.8
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_canopy_mats[key] = m
	return m


func setup(b, at: Vector3, v: Vector3, c: Color, seed_: int) -> void:
	battle = b
	vel = v
	col = c
	position = at
	var r := RandomNumberGenerator.new()
	r.seed = seed_
	_sway = r.randf() * TAU
	_drift = Vector3(r.randf_range(-1.0, 1.0), 0.0, r.randf_range(-1.0, 1.0)) * 0.8
	_gk = clampf(sqrt(B3Rules.gravity_k()), 0.45, 1.6)
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()


func _build() -> void:
	# the pilot: flight suit in the team colour, leather cap and goggles,
	# hands up on the lines and legs dangling
	_pilot = Node3D.new()
	add_child(_pilot)
	var suit := B3Mats.mat(col.darkened(0.1))
	var skin := B3Mats.mat(Color("eab68e"), 0.6)
	var cap := B3Mats.mat(Color("7a4a2a"), 0.8)
	var boot := B3Mats.mat(Color("3a2a20"))
	B3Mats.add(_pilot, B3Mats.box(Vector3(0.34, 0.42, 0.24)), suit, Vector3(0, 0.62, 0))
	B3Mats.add(_pilot, B3Mats.sphere(0.17, 12), skin, Vector3(0, 1.01, 0))
	B3Mats.add(_pilot, B3Mats.hemi(0.185), cap, Vector3(0, 1.02, -0.01))
	B3Mats.add(_pilot, B3Mats.box(Vector3(0.3, 0.06, 0.06)), B3Mats.mat(Color("bfe6ff"), 0.1), Vector3(0, 1.06, 0.15), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		B3Mats.add(_pilot, B3Mats.capsule(0.05, 0.42), suit, Vector3(0.2 * sx, 1.02, 0), Vector3(0, 0, -18 * sx), Vector3.ONE, false)
		B3Mats.add(_pilot, B3Mats.capsule(0.06, 0.44), suit, Vector3(0.09 * sx, 0.24, 0), Vector3(0, 0, 4 * sx), Vector3.ONE, false)
		B3Mats.add(_pilot, B3Mats.box(Vector3(0.1, 0.08, 0.16)), boot, Vector3(0.09 * sx, 0.02, 0.03), Vector3.ZERO, Vector3.ONE, false)
	# the canopy: team colour and white panels, a white cap on top
	_canopy = Node3D.new()
	_canopy.position = Vector3(0, 2.6, 0)
	add_child(_canopy)
	var white := canopy_mat(Color("f4f1ea"))
	var team := canopy_mat(col)
	B3Mats.add(_canopy, B3Mats.hemi(1.0), team, Vector3.ZERO, Vector3.ZERO, Vector3(1.25, 0.75, 1.25))
	B3Mats.add(_canopy, B3Mats.torus(0.9, 1.04), white, Vector3(0, 0.02, 0), Vector3.ZERO, Vector3(1.25, 1.6, 1.25), false)
	B3Mats.add(_canopy, B3Mats.hemi(0.42), white, Vector3(0, 0.56, 0), Vector3.ZERO, Vector3(1.25, 0.75, 1.25), false)
	# the lines from the rim down to the shoulders
	_lines = Node3D.new()
	add_child(_lines)
	var line := B3Mats.mat(Color("e8e4da"))
	for i in 6:
		var a := TAU * i / 6.0
		var top := Vector3(cos(a) * 1.15, 2.6, sin(a) * 1.15)
		var bot := Vector3(0.0, 1.25, 0.0)
		var mid := (top + bot) * 0.5
		var d := top - bot
		var mi := B3Mats.add(_lines, B3Mats.box(Vector3(0.025, 0.025, 1.0)), line, mid, Vector3.ZERO, Vector3.ONE, false)
		mi.basis = Basis.looking_at(d.normalized(), Vector3.UP if absf(d.normalized().y) < 0.98 else Vector3.RIGHT) * Basis.from_scale(Vector3(1, 1, d.length()))
	_set_open(0.0)


func _set_open(k: float) -> void:
	open = k
	var s := lerpf(0.12, 1.0, k)
	_canopy.scale = Vector3(s, lerpf(0.35, 1.0, k) * s, s)
	_canopy.position.y = lerpf(1.6, 2.6, k)
	_lines.visible = k > 0.5
	_lines.scale = Vector3(lerpf(0.3, 1.0, k), 1.0, lerpf(0.3, 1.0, k))


func _process(dt: float) -> void:
	if dt <= 0.0 or battle == null:
		return
	t += dt
	if t > LIFE:
		queue_free()
		return
	var w: B3World = battle.world
	if landed >= 0.0:
		_land_tick(dt)
		return
	if t < POP_T:
		vel.y -= 14.0 * _gk * _gk * dt       # still going up out of the cockpit
		vel.x = move_toward(vel.x, 0.0, dt * 4.0)
		vel.z = move_toward(vel.z, 0.0, dt * 4.0)
	else:
		if open == 0.0 and battle.has_method("snd"):
			battle.snd("chute_open", position, 0.6)      # fwump! the chute opens
		_set_open(minf(1.0, open + dt * 4.5))
		vel.x = move_toward(vel.x, _drift.x, dt * 3.0)
		vel.z = move_toward(vel.z, _drift.z, dt * 3.0)
		vel.y = move_toward(vel.y, -FALL * _gk, dt * 12.0)
	position += vel * dt
	position.x = clampf(position.x, -B3Defs.BOUNDS, B3Defs.BOUNDS)
	position.z = clampf(position.z, -B3Defs.BOUNDS, B3Defs.BOUNDS)
	# a gentle swing under the canopy
	var sw := sin(t * 1.9 + _sway) * 0.22 * open
	rotation = Vector3(sin(t * 1.3 + _sway) * 0.1 * open, rotation.y + dt * 0.25, sw)
	var floor_y := maxf(w.height_at(position.x, position.z), w.water_level_at(position.x, position.z))
	if position.y <= floor_y and vel.y < 0.0:
		position.y = floor_y
		landed = 0.0
		rotation = Vector3(0, rotation.y, 0)
		if battle.has_method("snd"):
			battle.snd("land_puff", position, 0.5)


## On the ground: the canopy flops over and settles, then the pilot vanishes
## in a puff (back to base!).
func _land_tick(dt: float) -> void:
	landed += dt
	var k := clampf(landed / 0.8, 0.0, 1.0)
	_lines.visible = false
	_canopy.position = Vector3(lerpf(0.0, 1.6, k), lerpf(2.6, 0.15, k), 0.0)
	_canopy.rotation = Vector3(0, 0, lerpf(0.0, -1.2, k))
	_canopy.scale = Vector3(1.0, lerpf(1.0, 0.25, k), 1.0)
	_pilot.position.y = 0.0
	if landed > 1.8:
		if battle.fx and is_instance_valid(battle.fx):
			battle.fx._fx_poof(position + Vector3(0, 0.6, 0), 0.8)     # (each computer its own puff)
		queue_free()
