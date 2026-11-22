class_name B3Rig
extends Node3D
## A unit's toy-like model, built from primitive meshes and animated by code.
## Pivots (Node3Ds with meta "pivot") are the joints; `parts` describes how
## to turn the model into a physics ragdoll (see B3Ragdoll). Forward is +Z.

const SKINS := [Color("f7d2b4"), Color("eab68e"), Color("c98d62"), Color("8f5b3c"), Color("ffe0c8"), Color("b07850")]
const BOOT := Color("3a2f2a")
const METAL := Color("b9c2cc")
const WOOD := Color("8a5a32")
const GUN := Color("34383e")
const EYE := Color("1d1b2a")

## Animal and dinosaur shapes (metres before `size`).
const QUAD := {
	"dog": {"bw": 0.34, "bh": 0.34, "bl": 0.78, "leg": 0.42, "lr": 0.07, "col": "c08850", "belly": "f0d2a8", "head": 0.2, "tail": 0.42, "tr": 0.05},
	"wolf": {"bw": 0.4, "bh": 0.4, "bl": 0.95, "leg": 0.5, "lr": 0.08, "col": "8c929c", "belly": "dfe3e8", "head": 0.24, "tail": 0.55, "tr": 0.09},
	"bear": {"bw": 0.85, "bh": 0.8, "bl": 1.45, "leg": 0.55, "lr": 0.18, "col": "6e4529", "belly": "8d5f3e", "head": 0.38, "tail": 0.15, "tr": 0.1},
	"bull": {"bw": 0.8, "bh": 0.82, "bl": 1.6, "leg": 0.72, "lr": 0.13, "col": "4a3226", "belly": "6b4a38", "head": 0.34, "tail": 0.7, "tr": 0.05},
	"elephant": {"bw": 1.55, "bh": 1.5, "bl": 2.4, "leg": 1.15, "lr": 0.32, "col": "8e959f", "belly": "a3aab3", "head": 0.75, "tail": 0.8, "tr": 0.07},
	"trike": {"bw": 1.4, "bh": 1.25, "bl": 2.9, "leg": 0.85, "lr": 0.28, "col": "4e9c8c", "belly": "9fd0b5", "head": 0.62, "tail": 2.1, "tr": 0.42},
	"stego": {"bw": 1.15, "bh": 1.3, "bl": 3.0, "leg": 1.0, "lr": 0.27, "col": "c58c40", "belly": "e8c88f", "head": 0.36, "tail": 2.4, "tr": 0.4},
	"brachio": {"bw": 1.6, "bh": 1.7, "bl": 3.4, "leg": 2.3, "lr": 0.36, "col": "8aa65a", "belly": "c3d79a", "head": 0.42, "tail": 3.6, "tr": 0.5},
	"mammoth": {"bw": 1.65, "bh": 1.6, "bl": 2.5, "leg": 1.1, "lr": 0.34, "col": "7a4f30", "belly": "94643f", "head": 0.74, "tail": 0.6, "tr": 0.08},
}
const H_BRONZE := Color("d39b3e")
const H_GOLD := Color("ffd84a")
const H_HORSES := ["6b4226", "3b2a22", "d8d0c4", "9a5a32", "4a3a34"]
const ROBE := Color("4b3c9e")
const ROBOT := Color("aab4be")
const ROBOT_DARK := Color("4f5761")
const BIPED := {
	"trex": {"bw": 1.1, "bh": 1.3, "bl": 2.5, "leg": 1.9, "lr": 0.34, "col": "4f9a3c", "belly": "b6d47a", "head": Vector3(0.8, 0.8, 1.35), "tail": 3.0, "tr": 0.55},
	"raptor": {"bw": 0.36, "bh": 0.42, "bl": 0.95, "leg": 0.78, "lr": 0.09, "col": "d09a52", "belly": "f2d6a2", "head": Vector3(0.24, 0.26, 0.52), "tail": 1.25, "tr": 0.17},
}

static var _shapes := {}

var kind := ""
var body := ""
var style := ""
var size := 1.0
var team := ""
var team_col := Color.WHITE
var pv := {}
var parts: Array = []
var meshes: Array[MeshInstance3D] = []
var eyes: Array[Node3D] = []
var muzzle: Node3D = null
var held: Node3D = null
var laser: MeshInstance3D = null
var hold := "none"
var radius := 0.32
var height := 1.9
var top := 2.0
var reach_y := 1.3
var phase := 0.0
var t := 0.0
var recoil := 0.0
var punch_side := 0
var _flash := 0.0
var _flash_rest := 0.0
var _base_y := {}
var wing_flap := 0.0
var shield := false
var staff: Node3D = null      # the wizard's staff hand (kept upright)
var size_mult := 1.0          # Toy Box size: tiny 0.5 .. huge 2.5
var thrust := false           # spears and lances stab forward instead of swinging
var spear_hand: Node3D = null # the hand holding a spear or lance (kept level)
var musket_hand: Node3D = null # a musket's hand: shouldered upright when not aiming
var no_collide: Array = []    # [part, part] pairs whose ragdoll bodies don't bump (a rider and its horse)
var _hrng: RandomNumberGenerator = null


func build(unit_kind: String, team_id: String, rng: RandomNumberGenerator) -> void:
	kind = unit_kind
	team = team_id
	_hrng = rng
	var def := B3Defs.unit_def(kind)
	body = String(def.body)
	style = String(def.style)
	size = float(def.size) * size_mult
	team_col = B3Defs.team_col(team)
	match body:
		"human":
			_build_human(def, rng)
		"rider":
			_build_rider(def, rng)
		"robot":
			_build_robot()
		"ape":
			_build_ape(rng)
		"quad":
			_build_quad(rng)
		"biped":
			_build_biped(rng)
		"bird":
			if style == "ptero":
				_build_ptero()
			else:
				_build_chicken()
		"dragon":
			_build_dragon()
	scale = Vector3.ONE * size
	radius *= size
	height *= size
	top *= size
	reach_y *= size
	for k in pv:
		var p: Node3D = pv[k]
		_base_y[k] = p.position


# ------------------------------------------------------------------ helpers
func _pivot(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	p.set_meta("pivot", true)
	parent.add_child(p)
	pv[n] = p
	return p


func _m(parent: Node3D, mesh: Mesh, mt: Material, pos := Vector3.ZERO, rot := Vector3.ZERO, scl := Vector3.ONE, shadow := true) -> MeshInstance3D:
	var mi := B3Mats.add(parent, mesh, mt, pos, rot, scl, shadow)
	meshes.append(mi)
	return mi


func _c(c: Color, rough := 0.75) -> StandardMaterial3D:
	return B3Mats.mat(c, rough)


static func _shape(key: String, make: Callable) -> Shape3D:
	var s: Shape3D = _shapes.get(key)
	if s == null:
		s = make.call()
		_shapes[key] = s
	return s


## Registers a ragdoll body for pivot `n`. Shape sizes are in model metres;
## they get multiplied by `size` here.
func _part(n: String, kind_s: String, dims: Vector3, offset: Vector3, mass: float, parent: int, swing := 60.0, twist := 25.0, axis := "y") -> void:
	var s := size
	var key := "%s|%.3f|%.3f|%.3f|%s" % [kind_s, dims.x * s, dims.y * s, dims.z * s, axis]
	var shape: Shape3D
	match kind_s:
		"box":
			shape = _shape(key, func():
				var b := BoxShape3D.new()
				b.size = dims * s
				return b)
		"sphere":
			shape = _shape(key, func():
				var b := SphereShape3D.new()
				b.radius = dims.x * s
				return b)
		_:
			shape = _shape(key, func():
				var b := CapsuleShape3D.new()
				b.radius = dims.x * s
				b.height = maxf(dims.y * s, dims.x * s * 2.0 + 0.01)
				return b)
	var basis := Basis.IDENTITY
	if axis == "z":
		basis = Basis(Vector3.RIGHT, PI * 0.5)
	elif axis == "x":
		basis = Basis(Vector3.BACK, PI * 0.5)
	parts.append({"node": pv[n], "shape": shape, "offset": Transform3D(basis, offset * s), "mass": mass, "parent": parent, "swing": swing, "twist": twist})


## A tapered cylinder from `a` (radius ra) to `b` (radius rb): tusks, trunks, necks.
func _seg(parent: Node3D, a: Vector3, b: Vector3, ra: float, rb: float, mt: Material, shadow := true) -> MeshInstance3D:
	var d := b - a
	var l := d.length()
	var y := d / maxf(l, 0.0001)
	var ref := Vector3.RIGHT if absf(y.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
	var x := ref.cross(y).normalized()
	var z := x.cross(y).normalized()
	var mi := _m(parent, B3Mats.cyl(rb, ra, l + minf(ra, rb) * 0.6, 10), mt, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, shadow)
	mi.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)
	return mi


func _eye(parent: Node3D, pos: Vector3, r: float, white := false) -> void:
	var e := Node3D.new()
	e.position = pos
	e.name = "Eye"
	parent.add_child(e)
	if white:
		_m(e, B3Mats.sphere(r * 1.7, 10), _c(Color.WHITE, 0.4), Vector3(0, 0, -r * 0.5), Vector3.ZERO, Vector3.ONE, false)
	_m(e, B3Mats.sphere(r, 8), _c(EYE, 0.3), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	eyes.append(e)


# -------------------------------------------------------------------- human
func _build_human(def: Dictionary, rng: RandomNumberGenerator) -> void:
	var tc := team_col
	var skin: Color = SKINS[rng.randi() % SKINS.size()]
	var stick := style == "stick"
	var limb := 0.045 if stick else 0.085
	var leg_rad := 0.05 if stick else 0.1
	var tw := 0.46
	var th := 0.58
	var td := 0.3
	var shirt := tc
	var pants := tc.darkened(0.55)
	var sleeve := tc
	match style:
		"stick":
			skin = Color("fbfbf6")
			shirt = Color("26242e")
			pants = shirt
			sleeve = shirt
		"ninja":
			shirt = Color("2c2b36")
			pants = Color("24232c")
			sleeve = shirt
		"giant":
			tw = 0.62
			td = 0.42
			th = 0.62
			pants = Color("6a4a32")
			skin = skin.lerp(Color("c9a27a"), 0.3)
		"knight":
			pants = Color("5d6470")
			sleeve = Color("8c949e")
		"viking":
			pants = Color("6a4a32")
		"sniper":
			pants = Color("4d5a3a")
		"wizard":
			shirt = ROBE
			pants = ROBE.darkened(0.3)
			sleeve = ROBE
	# 📜 history outfits: a uniform colour (the team colour then goes on a sash,
	# cuffs or hat band), bare legs under a tunic, sandals, white breeches...
	var skirt := Color(0, 0, 0, 0)      # the bit over the hips (clear: same as the trousers)
	var boot := BOOT
	var coat_s := String(def.get("coat", ""))
	if coat_s != "":
		shirt = Color(coat_s)
		sleeve = shirt
		pants = shirt.darkened(0.25)
	match style:
		"hoplite", "legionary":
			sleeve = skin
			skirt = tc.darkened(0.12)
			pants = skin
			boot = Color("7a5230")
		"immortal":
			pants = tc.darkened(0.3)
			boot = Color("c79a3a")
		"gaul":
			pants = Color("8b6b3a")
		"saxon":
			pants = Color("6e5a46")
		"longbow":
			pants = Color("5d4a36")
		"horseknight":
			pants = Color("5d6470")
			sleeve = Color("8c949e")
		"redcoat":
			pants = Color("efeadc")
		"linesman", "cavalry":
			pants = Color("e8e4da")
		"minuteman":
			shirt = Color(String(["7b5a3c", "5e6b4a", "8a7a60", "4f4f58", "6e4a3a"][rng.randi() % 5]))
			sleeve = shirt
			pants = Color("5d4a36")
		"union":
			pants = Color("7f9cc9")
		"confed":
			pants = Color("9a8662")
		"gi":
			pants = Color("5a5838")
			boot = Color("6b4a2e")
	radius = 0.3 if style != "giant" else 0.36
	height = 1.85
	top = 1.95
	reach_y = 1.15
	var hips := _pivot("hips", self, Vector3(0, 0.78, 0))
	var torso := _pivot("torso", hips, Vector3.ZERO)
	var head := _pivot("head", torso, Vector3(0, 0.62, 0))
	var arm_l := _pivot("arm_l", torso, Vector3(tw * 0.5 + 0.08, 0.54, 0))
	var arm_r := _pivot("arm_r", torso, Vector3(-tw * 0.5 - 0.08, 0.54, 0))
	var leg_l := _pivot("leg_l", hips, Vector3(0.12, 0.0, 0))
	var leg_r := _pivot("leg_r", hips, Vector3(-0.12, 0.0, 0))
	# torso
	if stick:
		_m(torso, B3Mats.capsule(0.055, 0.72), _c(shirt), Vector3(0, 0.28, 0))
		_m(torso, B3Mats.cyl(0.11, 0.13, 0.12, 10), _c(tc), Vector3(0, 0.56, 0))
	else:
		_m(torso, B3Mats.box(Vector3(tw, th, td)), _c(shirt), Vector3(0, 0.3, 0))
		_m(torso, B3Mats.box(Vector3(tw * 0.94, 0.2, td * 0.94)), _c(skirt if skirt.a > 0.0 else pants), Vector3(0, -0.04, 0))
		_m(torso, B3Mats.box(Vector3(tw + 0.02, 0.07, td + 0.02)), _c(Color("2e2620")), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)
		_m(torso, B3Mats.cyl(0.09, 0.1, 0.12, 8), _c(skin), Vector3(0, 0.62, 0), Vector3.ZERO, Vector3.ONE, false)
	# head + face
	var hr := 0.3
	_m(head, B3Mats.sphere(hr, 16), _c(skin, 0.6), Vector3(0, 0.2, 0))
	_eye(head, Vector3(0.105, 0.25, hr * 0.86), 0.048)
	_eye(head, Vector3(-0.105, 0.25, hr * 0.86), 0.048)
	if style != "ninja":
		_m(head, B3Mats.box(Vector3(0.11, 0.03, 0.03)), _c(Color("8a3b3b")), Vector3(0, 0.11, hr * 0.9), Vector3.ZERO, Vector3.ONE, false)
	# arms + hands
	for arm in [arm_l, arm_r]:
		var a: Node3D = arm
		_m(a, B3Mats.capsule(limb, 0.62), _c(sleeve), Vector3(0, -0.27, 0))
		_m(a, B3Mats.sphere(limb * 1.25, 8), _c(METAL if style == "knight" or style == "horseknight" else skin, 0.6), Vector3(0, -0.58, 0), Vector3.ZERO, Vector3.ONE, false)
	for leg in [leg_l, leg_r]:
		var l: Node3D = leg
		_m(l, B3Mats.capsule(leg_rad, 0.76), _c(pants), Vector3(0, -0.36, 0))
		_m(l, B3Mats.box(Vector3(0.18, 0.11, 0.29)), _c(boot), Vector3(0, -0.72, 0.05))
	_human_gear(def, head, torso, arm_l, arm_r, tc, skin)
	# ragdoll
	_part("torso", "box", Vector3(tw, 0.86, td), Vector3(0, 0.22, 0), 3.0, -1)
	_part("head", "sphere", Vector3(hr, 0, 0), Vector3(0, 0.2, 0), 1.0, 0, 40.0, 30.0)
	_part("arm_l", "capsule", Vector3(limb + 0.03, 0.68, 0), Vector3(0, -0.3, 0), 0.7, 0, 85.0, 30.0)
	_part("arm_r", "capsule", Vector3(limb + 0.03, 0.68, 0), Vector3(0, -0.3, 0), 0.7, 0, 85.0, 30.0)
	_part("leg_l", "capsule", Vector3(leg_rad + 0.02, 0.78, 0), Vector3(0, -0.38, 0), 1.0, 0, 55.0, 20.0)
	_part("leg_r", "capsule", Vector3(leg_rad + 0.02, 0.78, 0), Vector3(0, -0.38, 0), 1.0, 0, 55.0, 20.0)


func _hand(arm: Node3D, rot_x: float) -> Node3D:
	var h := Node3D.new()
	h.name = "Hand"
	h.position = Vector3(0, -0.6, 0)
	h.rotation_degrees = Vector3(rot_x, 0, 0)
	arm.add_child(h)
	return h


func _human_gear(def: Dictionary, head: Node3D, torso: Node3D, arm_l: Node3D, arm_r: Node3D, tc: Color, skin: Color) -> void:
	var dark := tc.darkened(0.35)
	match style:
		"stick":
			_m(head, B3Mats.cyl(0.302, 0.302, 0.07, 16), _c(tc), Vector3(0, 0.32, 0))
		"soldier", "grenadier", "gunner":
			_m(head, B3Mats.hemi(0.34), _c(dark, 0.6), Vector3(0, 0.27, -0.01))
			_m(head, B3Mats.cyl(0.36, 0.36, 0.035, 16), _c(dark.darkened(0.2), 0.6), Vector3(0, 0.27, -0.01))
			if style == "gunner":
				_m(torso, B3Mats.box(Vector3(0.5, 0.36, 0.34)), _c(Color("5b6340")), Vector3(0, 0.36, 0))
		"rocketeer":
			_m(head, B3Mats.hemi(0.34), _c(dark, 0.6), Vector3(0, 0.26, -0.01))
			for x in [-0.09, 0.09]:
				_m(head, B3Mats.cyl(0.06, 0.06, 0.06, 10), _c(Color("ffb347"), 0.2), Vector3(x, 0.36, 0.22), Vector3(90, 0, 0), Vector3.ONE, false)
			_m(torso, B3Mats.box(Vector3(0.36, 0.42, 0.18)), _c(Color("6b7048")), Vector3(0, 0.32, -0.24))
		"knight", "horseknight":
			_m(head, B3Mats.cyl(0.33, 0.33, 0.38, 16), _c(METAL, 0.35), Vector3(0, 0.2, 0))
			_m(head, B3Mats.hemi(0.33), _c(METAL, 0.35), Vector3(0, 0.39, 0))
			_m(head, B3Mats.box(Vector3(0.36, 0.05, 0.05)), _c(Color("1c1c22")), Vector3(0, 0.25, 0.29), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.capsule(0.07, 0.42), _c(tc), Vector3(0, 0.58, -0.08), Vector3(-50, 0, 0))
			_m(torso, B3Mats.box(Vector3(0.5, 0.5, 0.34)), _c(METAL, 0.35), Vector3(0, 0.33, 0))
			_m(torso, B3Mats.box(Vector3(0.3, 0.42, 0.02)), _c(tc), Vector3(0, 0.3, 0.18))
			for x in [-0.3, 0.3]:
				_m(torso, B3Mats.hemi(0.14), _c(METAL, 0.35), Vector3(x, 0.56, 0))
			for e in eyes:
				e.visible = false
		"viking":
			_m(head, B3Mats.hemi(0.33), _c(METAL, 0.4), Vector3(0, 0.28, 0))
			for sx in [-1.0, 1.0]:
				_m(head, B3Mats.cyl(0.0, 0.07, 0.3, 8), _c(Color("f3ead6")), Vector3(0.3 * sx, 0.42, 0), Vector3(0, 0, -55 * sx))
			_m(head, B3Mats.box(Vector3(0.36, 0.26, 0.12)), _c(Color("d9772b")), Vector3(0, 0.02, 0.22))
			_m(torso, B3Mats.cyl(0.3, 0.32, 0.16, 12), _c(Color("8a6a4a"), 0.95), Vector3(0, 0.57, 0))
		"archer":
			_m(head, B3Mats.cyl(0.02, 0.3, 0.36, 12), _c(tc.darkened(0.15)), Vector3(0, 0.46, -0.04), Vector3(-12, 0, 0))
			_m(head, B3Mats.box(Vector3(0.03, 0.03, 0.3)), _c(Color("ff6b6b")), Vector3(0.12, 0.48, -0.1), Vector3(30, 0, 0), Vector3.ONE, false)
			_m(torso, B3Mats.cyl(0.08, 0.08, 0.6, 8), _c(Color("8a5a32")), Vector3(0.1, 0.35, -0.2), Vector3(-15, 0, -20))
		"sniper":
			_m(head, B3Mats.cyl(0.4, 0.4, 0.03, 16), _c(Color("6b7a4a")), Vector3(0, 0.33, 0))
			_m(head, B3Mats.cyl(0.24, 0.27, 0.14, 14), _c(Color("6b7a4a")), Vector3(0, 0.4, 0))
			_m(torso, B3Mats.box(Vector3(0.5, 0.4, 0.34)), _c(Color("5d6b3c"), 0.95), Vector3(0, 0.36, 0))
			_m(torso, B3Mats.box(Vector3(0.52, 0.08, 0.36)), _c(tc), Vector3(0, 0.42, 0))
		"medic":
			_m(head, B3Mats.hemi(0.33), _c(Color("f5f5f5"), 0.5), Vector3(0, 0.28, 0))
			_m(head, B3Mats.box(Vector3(0.16, 0.05, 0.05)), _c(Color("3bd16f")), Vector3(0, 0.42, 0.18), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.box(Vector3(0.05, 0.16, 0.05)), _c(Color("3bd16f")), Vector3(0, 0.42, 0.18), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.box(Vector3(0.36, 0.4, 0.2)), _c(Color("f5f5f5")), Vector3(0, 0.32, -0.25))
			_m(torso, B3Mats.box(Vector3(0.18, 0.06, 0.02)), _c(Color("3bd16f")), Vector3(0, 0.34, -0.36))
			_m(torso, B3Mats.box(Vector3(0.06, 0.18, 0.02)), _c(Color("3bd16f")), Vector3(0, 0.34, -0.36))
		"ninja":
			_m(head, B3Mats.sphere(0.308, 16), _c(Color("2c2b36")), Vector3(0, 0.2, 0))
			_m(head, B3Mats.box(Vector3(0.4, 0.12, 0.1)), _c(skin), Vector3(0, 0.25, 0.24), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.cyl(0.315, 0.315, 0.06, 16), _c(tc), Vector3(0, 0.36, 0))
			_m(head, B3Mats.box(Vector3(0.05, 0.04, 0.3)), _c(tc), Vector3(0.05, 0.32, -0.38), Vector3(-30, 10, 0))
			_m(torso, B3Mats.box(Vector3(0.5, 0.1, 0.34)), _c(tc), Vector3(0, 0.08, 0))
		"giant":
			_m(head, B3Mats.box(Vector3(0.34, 0.24, 0.14)), _c(Color("6b4226")), Vector3(0, 0.04, 0.2))
			_m(head, B3Mats.box(Vector3(0.3, 0.05, 0.05)), _c(Color("4a2f1c")), Vector3(0, 0.33, 0.24), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.hemi(0.275), _c(Color("6b4226")), Vector3(0, 0.25, -0.03))
			_m(torso, B3Mats.box(Vector3(0.66, 0.12, 0.46)), _c(Color("8a6a4a")), Vector3(0, 0.6, 0))
		"wizard":
			var beard := Color("f4f1ea")
			var gold := Color("ffd84a")
			# tall pointy hat with a team-coloured band and a couple of stars
			_m(head, B3Mats.cyl(0.46, 0.46, 0.045, 18), _c(ROBE), Vector3(0, 0.36, 0))
			_m(head, B3Mats.cyl(0.13, 0.3, 0.5, 14), _c(ROBE), Vector3(0, 0.63, -0.02), Vector3(-6, 0, 0))
			_m(head, B3Mats.cyl(0.0, 0.135, 0.36, 12), _c(ROBE), Vector3(0, 1.0, -0.1), Vector3(-28, 0, 0))
			_m(head, B3Mats.cyl(0.305, 0.305, 0.1, 16), _c(tc), Vector3(0, 0.43, 0))
			for sp in [Vector3(0.12, 0.68, 0.2), Vector3(-0.09, 0.82, 0.13)]:
				var st: Vector3 = sp
				_m(head, B3Mats.prism(Vector3(0.11, 0.1, 0.02)), B3Mats.glow(gold, 1.3), st, Vector3(0, 0, 0), Vector3.ONE, false)
				_m(head, B3Mats.prism(Vector3(0.11, 0.1, 0.02)), B3Mats.glow(gold, 1.3), st + Vector3(0, -0.025, 0), Vector3(0, 0, 180), Vector3.ONE, false)
			# big white beard, moustache and bushy eyebrows
			_m(head, B3Mats.cyl(0.22, 0.03, 0.5, 10), _c(beard, 0.95), Vector3(0, -0.07, 0.19), Vector3(-16, 0, 0))
			_m(head, B3Mats.box(Vector3(0.26, 0.06, 0.07)), _c(beard, 0.95), Vector3(0, 0.13, 0.275), Vector3(0, 0, 0), Vector3.ONE, false)
			for sx in [-1.0, 1.0]:
				_m(head, B3Mats.box(Vector3(0.11, 0.035, 0.05)), _c(beard), Vector3(0.105 * sx, 0.315, 0.255), Vector3(0, 0, -12 * sx), Vector3.ONE, false)
			# the robe flares out over the legs; team-coloured hem, belt and collar
			_m(torso, B3Mats.cyl(0.25, 0.42, 0.66, 14), _c(ROBE), Vector3(0, -0.3, 0))
			_m(torso, B3Mats.cyl(0.43, 0.43, 0.09, 14), _c(tc), Vector3(0, -0.6, 0))
			_m(torso, B3Mats.box(Vector3(0.49, 0.08, 0.33)), _c(tc), Vector3(0, 0.07, 0))
			_m(torso, B3Mats.sphere(0.05, 8), B3Mats.glow(gold, 1.2), Vector3(0, 0.07, 0.17), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.cyl(0.17, 0.2, 0.07, 12), _c(tc), Vector3(0, 0.58, 0))
			for arm in [arm_l, arm_r]:
				_m(arm as Node3D, B3Mats.cyl(0.13, 0.11, 0.12, 10), _c(tc), Vector3(0, -0.52, 0), Vector3.ZERO, Vector3.ONE, false)
		_:
			_history_gear(def, head, torso, arm_l, arm_r, tc, skin)
	# weapon
	var wid := String(def.weapon)
	match wid:
		"rifle", "sniper", "mg", "pistol", "bazooka":
			hold = "gun"
			var h := _hand(arm_r, 90)
			var L := {"rifle": 0.8, "sniper": 1.05, "mg": 0.85, "pistol": 0.26, "bazooka": 1.1}
			var len_: float = L[wid]
			if wid == "bazooka":
				_m(h, B3Mats.cyl(0.1, 0.1, len_, 12), _c(Color("5d6b3c")), Vector3(0, 0.08, 0.25), Vector3(90, 0, 0))
				_m(h, B3Mats.cyl(0.13, 0.1, 0.16, 12), _c(GUN), Vector3(0, 0.08, 0.25 + len_ * 0.5), Vector3(90, 0, 0))
				_m(h, B3Mats.box(Vector3(0.05, 0.16, 0.08)), _c(GUN), Vector3(0, -0.05, 0.1))
				muzzle = _marker(h, Vector3(0, 0.08, 0.3 + len_ * 0.5))
			elif wid == "pistol":
				_m(h, B3Mats.box(Vector3(0.06, 0.1, 0.24)), _c(GUN, 0.4), Vector3(0, 0.03, 0.1))
				_m(h, B3Mats.box(Vector3(0.05, 0.13, 0.06)), _c(GUN, 0.4), Vector3(0, -0.04, 0.0))
				muzzle = _marker(h, Vector3(0, 0.05, 0.24))
			else:
				var w := 0.12 if wid == "mg" else 0.075
				_m(h, B3Mats.box(Vector3(w, 0.12, len_ * 0.7)), _c(GUN, 0.4), Vector3(0, 0.04, len_ * 0.2))
				_m(h, B3Mats.box(Vector3(0.07, 0.13, 0.26)), _c(WOOD), Vector3(0, 0.0, -len_ * 0.22))
				_m(h, B3Mats.cyl(0.025, 0.025, len_ * 0.45, 8), _c(GUN, 0.4), Vector3(0, 0.06, len_ * 0.68), Vector3(90, 0, 0), Vector3.ONE, false)
				if wid == "sniper":
					_m(h, B3Mats.cyl(0.04, 0.04, 0.3, 10), _c(Color("202226"), 0.3), Vector3(0, 0.15, len_ * 0.15), Vector3(90, 0, 0), Vector3.ONE, false)
				if wid == "mg":
					_m(h, B3Mats.box(Vector3(0.14, 0.14, 0.18)), _c(Color("5d6b3c")), Vector3(0, -0.1, len_ * 0.15))
				muzzle = _marker(h, Vector3(0, 0.06, len_ * 0.92))
		"sword", "katana", "axe", "gladius", "longsword", "sabre":
			hold = "melee"
			var h := _hand(arm_r, 0)
			if wid == "axe":
				_m(h, B3Mats.cyl(0.03, 0.03, 0.85, 8), _c(WOOD), Vector3(0, 0, 0.25), Vector3(90, 0, 0))
				_m(h, B3Mats.box(Vector3(0.04, 0.3, 0.22)), _c(METAL, 0.3), Vector3(0, 0.12, 0.6))
			else:
				var BL := {"sword": 0.85, "katana": 0.95, "gladius": 0.52, "longsword": 1.0, "sabre": 0.88}
				var BW := {"sword": 0.09, "katana": 0.06, "gladius": 0.11, "longsword": 0.08, "sabre": 0.065}
				var bl: float = BL[wid]
				var bw: float = BW[wid]
				_m(h, B3Mats.cyl(0.03, 0.03, 0.2, 8), _c(Color("4a3020")), Vector3(0, 0, 0.0), Vector3(90, 0, 0), Vector3.ONE, false)
				_m(h, B3Mats.box(Vector3(0.1 if wid == "katana" else (0.24 if wid != "gladius" else 0.16), 0.05, 0.05)), _c(Color("222222") if wid == "katana" else Color("d4a73a"), 0.4), Vector3(0, 0, 0.1), Vector3.ZERO, Vector3.ONE, false)
				if wid == "sabre":
					# a curved cavalry sabre: two pieces, the tip bent back a little
					_m(h, B3Mats.box(Vector3(0.025, bw, bl * 0.6)), _c(METAL, 0.25), Vector3(0, 0, 0.12 + bl * 0.3))
					_m(h, B3Mats.box(Vector3(0.025, bw, bl * 0.45)), _c(METAL, 0.25), Vector3(0, 0.035, 0.12 + bl * 0.8), Vector3(-9, 0, 0))
				else:
					_m(h, B3Mats.box(Vector3(0.025, bw, bl)), _c(METAL, 0.25), Vector3(0, 0, 0.12 + bl * 0.5))
					if wid == "gladius":
						_m(h, B3Mats.sphere(0.05, 8), _c(Color("d4a73a"), 0.4), Vector3(0, 0, -0.12), Vector3.ZERO, Vector3.ONE, false)
		"spear", "lance":
			# held level and stabbed forward (the hand turns to keep it pointing ahead)
			hold = "melee"
			thrust = true
			var h := _hand(arm_r, 0)
			spear_hand = h
			var L := 2.5 if wid == "spear" else 3.3
			var back := L * 0.3
			var tip_c := H_BRONZE if style == "hoplite" else METAL
			_m(h, B3Mats.cyl(0.032, 0.036, L, 8), _c(WOOD.lightened(0.1) if wid == "spear" else Color("e8dcc0")), Vector3(0, 0, L * 0.5 - back), Vector3(90, 0, 0))
			_m(h, B3Mats.cyl(0.0, 0.07, 0.3, 8), _c(tip_c, 0.3), Vector3(0, 0, L - back + 0.13), Vector3(90, 0, 0))
			if wid == "lance":
				# striped in the team colour, with a little flag and a hand guard
				for i in 3:
					_m(h, B3Mats.cyl(0.04, 0.04, 0.22, 8), _c(tc), Vector3(0, 0, 0.6 + i * 0.6), Vector3(90, 0, 0), Vector3.ONE, false)
				_m(h, B3Mats.cyl(0.03, 0.15, 0.22, 10), _c(METAL, 0.3), Vector3(0, 0, 0.22), Vector3(90, 0, 0), Vector3.ONE, false)
				_m(h, B3Mats.prism(Vector3(0.36, 0.26, 0.02), 0.0), _c(tc), Vector3(0, 0.15, L - back - 0.42), Vector3(0, 90, -90), Vector3.ONE, false)
			elif style == "immortal":
				_m(h, B3Mats.sphere(0.075, 10), _c(Color("ffd84a"), 0.35), Vector3(0, 0, -back - 0.02), Vector3.ZERO, Vector3.ONE, false)
			else:
				_m(h, B3Mats.cyl(0.0, 0.04, 0.18, 6), _c(tip_c, 0.3), Vector3(0, 0, -back - 0.08), Vector3(-90, 0, 0), Vector3.ONE, false)
		"musket":
			# a long musket: wooden stock, iron barrel and (for most) a bayonet on the end
			hold = "gun"
			var h := _hand(arm_r, 90)
			musket_hand = h
			_m(h, B3Mats.box(Vector3(0.07, 0.1, 1.0)), _c(WOOD), Vector3(0, 0.02, 0.22))
			_m(h, B3Mats.box(Vector3(0.08, 0.16, 0.26)), _c(WOOD), Vector3(0, -0.03, -0.38))
			_m(h, B3Mats.cyl(0.024, 0.024, 1.18, 8), _c(GUN, 0.4), Vector3(0, 0.07, 0.5), Vector3(90, 0, 0), Vector3.ONE, false)
			if bool(def.get("bayonet", false)):
				_m(h, B3Mats.box(Vector3(0.018, 0.035, 0.44)), _c(METAL, 0.2), Vector3(0, 0.1, 1.28), Vector3.ZERO, Vector3.ONE, false)
			muzzle = _marker(h, Vector3(0, 0.07, 1.1))
		"longbow":
			hold = "bow"
			var h := _hand(arm_l, 90)
			for i in 3:
				var a := (i - 1) * 22.0
				_m(h, B3Mats.box(Vector3(0.045, 0.62, 0.055)), _c(WOOD.lightened(0.15)), Vector3(0, (i - 1) * 0.58, 0.08 - absf(i - 1) * 0.08), Vector3(-a, 0, 0))
			_m(h, B3Mats.cyl(0.008, 0.008, 1.73, 4), _c(Color("eeeeee")), Vector3(0, 0, -0.11), Vector3.ZERO, Vector3.ONE, false)
			muzzle = _marker(h, Vector3(0, 0, 0.2))
		"hammer":
			hold = "slam"
			var h := _hand(arm_r, 0)
			_m(h, B3Mats.cyl(0.04, 0.04, 1.2, 8), _c(WOOD), Vector3(0, 0, 0.45), Vector3(90, 0, 0))
			_m(h, B3Mats.box(Vector3(0.36, 0.36, 0.42)), _c(Color("6d737b"), 0.5), Vector3(0, 0, 1.08))
		"bow":
			hold = "bow"
			var h := _hand(arm_l, 90)
			for i in 3:
				var a := (i - 1) * 32.0
				var yy := (i - 1) * 0.36
				_m(h, B3Mats.box(Vector3(0.04, 0.4, 0.05)), _c(WOOD), Vector3(0, yy, 0.08 - absf(i - 1) * 0.08), Vector3(-a, 0, 0))
			_m(h, B3Mats.cyl(0.008, 0.008, 1.0, 4), _c(Color("eeeeee")), Vector3(0, 0, -0.06), Vector3.ZERO, Vector3.ONE, false)
			muzzle = _marker(h, Vector3(0, 0, 0.2))
		"grenade":
			hold = "throw"
			var h := _hand(arm_r, 0)
			held = Node3D.new()
			h.add_child(held)
			_m(held, B3Mats.sphere(0.09, 10), _c(Color("4f6b35")), Vector3(0, -0.05, 0.04))
			_m(torso, B3Mats.box(Vector3(0.5, 0.08, 0.34)), _c(Color("4f6b35")), Vector3(0, 0.45, 0))
			for x in [-0.12, 0.0, 0.12]:
				_m(torso, B3Mats.sphere(0.06, 8), _c(Color("4f6b35")), Vector3(x, 0.45, 0.18), Vector3.ZERO, Vector3.ONE, false)
		"fireball":
			# a long wooden staff with a glowing fire orb on top
			hold = "staff"
			staff = _hand(arm_r, 0)
			_m(staff, B3Mats.cyl(0.035, 0.042, 1.75, 8), _c(WOOD), Vector3(0, 0.27, 0))
			_m(staff, B3Mats.torus(0.1, 0.15), _c(Color("d4a73a"), 0.35), Vector3(0, 1.12, 0))
			for a in [0.0, 120.0, 240.0]:
				_m(staff, B3Mats.cyl(0.012, 0.022, 0.22, 6), _c(Color("d4a73a"), 0.35), Vector3(sin(deg_to_rad(a)) * 0.09, 1.2, cos(deg_to_rad(a)) * 0.09), Vector3(cos(deg_to_rad(a)) * -20.0, 0, sin(deg_to_rad(a)) * 20.0), Vector3.ONE, false)
			_m(staff, B3Mats.sphere(0.14, 12), B3Mats.glow(Color(1.0, 0.5, 0.12), 3.2), Vector3(0, 1.25, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(staff, B3Mats.sphere(0.2, 12), B3Mats.glow(Color(1.0, 0.7, 0.2, 0.35), 1.6), Vector3(0, 1.25, 0), Vector3.ZERO, Vector3.ONE, false)
			muzzle = _marker(staff, Vector3(0, 1.25, 0))
		_:
			hold = "fists"
	var sk := shield_kind(def)
	if sk != "" and hold == "melee":
		_shield(sk, arm_l, tc)


func _marker(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = "Muzzle"
	n.position = pos
	parent.add_child(n)
	return n


# ----------------------------------------------------------- 📜 history gear
## Which shield a fighter carries: "round" (knights; Saxons get a bigger
## wooden one), "hoplon", "scutum", "wicker", "oval", "kite" or "" (none).
static func shield_kind(def: Dictionary) -> String:
	var v: Variant = def.get("shield", false)
	if v is String:
		return String(v)
	if v is bool and v:
		return "round"
	return ""


func _shield(kind_s: String, arm_l: Node3D, tc: Color) -> void:
	var sh := Node3D.new()
	sh.name = "Shield"
	shield = true
	sh.position = Vector3(0, -0.42, 0.12)
	sh.rotation_degrees = Vector3(90, 0, 0)
	arm_l.add_child(sh)
	# in shield space +y faces the enemy and -z is up
	var team_m := _c(tc)
	match kind_s:
		"hoplon":
			# the big round Greek shield: bronze rim and a Λ (for Lacedaemon, Sparta)
			sh.position = Vector3(0.03, -0.36, 0.17)
			_m(sh, B3Mats.cyl(0.5, 0.5, 0.08, 20), team_m)
			_m(sh, B3Mats.torus(0.46, 0.55), _c(H_BRONZE, 0.3))
			for sx: float in [-1.0, 1.0]:
				_m(sh, B3Mats.box(Vector3(0.07, 0.02, 0.5)), _c(Color("f6ecd2")), Vector3(0.085 * sx, 0.05, 0.02), Vector3(0, 20.0 * sx, 0), Vector3.ONE, false)
		"scutum":
			# the tall curved Roman shield with a gold boss and spine
			sh.position = Vector3(0.03, -0.36, 0.17)
			_m(sh, B3Mats.box(Vector3(0.38, 0.07, 1.04)), team_m)
			for sx: float in [-1.0, 1.0]:
				_m(sh, B3Mats.box(Vector3(0.19, 0.07, 1.04)), team_m, Vector3(0.265 * sx, -0.04, 0), Vector3(0, 0, -25.0 * sx))
			var gold := _c(H_GOLD, 0.35)
			_m(sh, B3Mats.box(Vector3(0.05, 0.03, 0.96)), gold, Vector3(0, 0.045, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(sh, B3Mats.sphere(0.11, 10), gold, Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1, 0.6, 1), false)
			for sz: float in [-1.0, 1.0]:
				_m(sh, B3Mats.box(Vector3(0.4, 0.03, 0.05)), gold, Vector3(0, 0.045, 0.49 * sz), Vector3.ZERO, Vector3.ONE, false)
		"wicker":
			# a light woven Persian shield with a team border
			sh.position = Vector3(0.03, -0.38, 0.15)
			_m(sh, B3Mats.box(Vector3(0.5, 0.05, 0.86)), _c(Color("c9a86a"), 0.95))
			for i in 4:
				_m(sh, B3Mats.box(Vector3(0.46, 0.02, 0.025)), _c(Color("9a7a44")), Vector3(0, 0.03, -0.27 + i * 0.18), Vector3.ZERO, Vector3.ONE, false)
			for sx: float in [-1.0, 1.0]:
				_m(sh, B3Mats.box(Vector3(0.07, 0.07, 0.88)), team_m, Vector3(0.25 * sx, 0.0, 0))
				_m(sh, B3Mats.box(Vector3(0.56, 0.07, 0.07)), team_m, Vector3(0, 0.0, 0.43 * sx))
		"oval":
			# a tall Gaulish oval with a wooden spine and an iron boss
			sh.position = Vector3(0.03, -0.38, 0.16)
			_m(sh, B3Mats.cyl(0.34, 0.34, 0.06, 18), team_m, Vector3.ZERO, Vector3.ZERO, Vector3(1.0, 1.0, 1.55))
			_m(sh, B3Mats.box(Vector3(0.06, 0.06, 0.96)), _c(WOOD), Vector3(0, 0.035, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(sh, B3Mats.sphere(0.1, 10), _c(METAL, 0.3), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3(1.0, 0.7, 1.5), false)
		"kite":
			# a knight's kite shield: round top, pointed bottom, a light stripe
			sh.position = Vector3(0.03, -0.36, 0.16)
			_m(sh, B3Mats.box(Vector3(0.5, 0.06, 0.42)), team_m, Vector3(0, 0, -0.2))
			_m(sh, B3Mats.cyl(0.25, 0.25, 0.06, 16), team_m, Vector3(0, 0, -0.41))
			_m(sh, B3Mats.prism(Vector3(0.5, 0.62, 0.06)), team_m, Vector3(0, 0, 0.31), Vector3(90, 0, 0))
			_m(sh, B3Mats.box(Vector3(0.08, 0.03, 1.05)), _c(Color("f6ecd2")), Vector3(0, 0.04, 0.04), Vector3.ZERO, Vector3.ONE, false)
			_m(sh, B3Mats.box(Vector3(0.46, 0.03, 0.08)), _c(Color("f6ecd2")), Vector3(0, 0.04, -0.22), Vector3.ZERO, Vector3.ONE, false)
		_:
			var big := style == "saxon"
			var r := 0.43 if big else 0.36
			_m(sh, B3Mats.cyl(r, r, 0.07, 18), team_m)
			_m(sh, B3Mats.torus(r - 0.03, r + 0.03), _c(WOOD if big else METAL, 0.35))
			_m(sh, B3Mats.sphere(0.09, 10), _c(METAL, 0.3), Vector3(0, 0.05, 0), Vector3.ZERO, Vector3.ONE, false)


## Hats, helmets, armour and kit for the 📜 History fighters.
func _history_gear(def: Dictionary, head: Node3D, torso: Node3D, arm_l: Node3D, arm_r: Node3D, tc: Color, _skin: Color) -> void:
	var ll: Node3D = pv.leg_l
	var lr_: Node3D = pv.leg_r
	var legs: Array[Node3D] = [ll, lr_]
	var arms: Array[Node3D] = [arm_l, arm_r]
	var st := _c(METAL, 0.3)
	var black := Color("1d1b22")
	match style:
		"hoplite":
			var br := _c(H_BRONZE, 0.3)
			# Corinthian helmet: bronze dome, cheek and neck guards, a nose guard
			_m(head, B3Mats.hemi(0.335), br, Vector3(0, 0.27, 0))
			_m(head, B3Mats.box(Vector3(0.58, 0.3, 0.24)), br, Vector3(0, 0.15, -0.16))
			for sx: float in [-1.0, 1.0]:
				_m(head, B3Mats.box(Vector3(0.09, 0.24, 0.16)), br, Vector3(0.215 * sx, 0.13, 0.15), Vector3(0, 28.0 * sx, 0))
			_m(head, B3Mats.box(Vector3(0.045, 0.16, 0.05)), br, Vector3(0, 0.21, 0.305), Vector3.ZERO, Vector3.ONE, false)
			# a tall horsehair crest in the team colour, front to back
			_m(head, B3Mats.box(Vector3(0.05, 0.1, 0.34)), br, Vector3(0, 0.64, -0.02), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.box(Vector3(0.11, 0.2, 0.58)), _c(tc), Vector3(0, 0.77, -0.04))
			_m(head, B3Mats.box(Vector3(0.11, 0.34, 0.13)), _c(tc), Vector3(0, 0.6, -0.33), Vector3(-12, 0, 0))
			# bronze breastplate over a team tunic, a cape and shin guards
			_m(torso, B3Mats.box(Vector3(0.52, 0.46, 0.35)), br, Vector3(0, 0.35, 0))
			_m(torso, B3Mats.box(Vector3(0.48, 0.8, 0.04)), _c(tc.darkened(0.2)), Vector3(0, 0.15, -0.2), Vector3(8, 0, 0))
			for l in legs:
				_m(l, B3Mats.capsule(0.115, 0.38), br, Vector3(0, -0.5, 0.01))
		"immortal":
			var cream := Color("f1e6c8")
			# a tall soft cloth hat with a team band, and a curly black beard
			_m(head, B3Mats.cyl(0.27, 0.31, 0.26, 16), _c(cream, 0.9), Vector3(0, 0.42, -0.01))
			_m(head, B3Mats.hemi(0.27), _c(cream, 0.9), Vector3(0, 0.55, -0.01))
			_m(head, B3Mats.cyl(0.318, 0.318, 0.07, 16), _c(tc), Vector3(0, 0.33, -0.01))
			_m(head, B3Mats.box(Vector3(0.3, 0.2, 0.12)), _c(Color("2a1f1a"), 0.9), Vector3(0, 0.03, 0.23))
			# a long robe with a gold hem and sash, and a quiver on the back
			_m(torso, B3Mats.cyl(0.25, 0.4, 0.62, 14), _c(tc), Vector3(0, -0.3, 0))
			_m(torso, B3Mats.cyl(0.41, 0.41, 0.07, 14), _c(H_GOLD, 0.5), Vector3(0, -0.59, 0))
			_m(torso, B3Mats.box(Vector3(0.49, 0.08, 0.33)), _c(H_GOLD, 0.5), Vector3(0, 0.07, 0))
			_m(torso, B3Mats.cyl(0.08, 0.08, 0.6, 8), _c(WOOD), Vector3(-0.1, 0.35, -0.2), Vector3(-15, 0, 20))
		"legionary":
			# galea helmet: steel dome, neck and cheek guards, a little team crest
			_m(head, B3Mats.hemi(0.335), st, Vector3(0, 0.27, 0))
			_m(head, B3Mats.box(Vector3(0.52, 0.05, 0.2)), st, Vector3(0, 0.28, -0.3), Vector3(-25, 0, 0))
			for sx: float in [-1.0, 1.0]:
				_m(head, B3Mats.box(Vector3(0.08, 0.22, 0.15)), st, Vector3(0.22 * sx, 0.15, 0.13), Vector3(0, 25.0 * sx, 0))
			_m(head, B3Mats.box(Vector3(0.09, 0.15, 0.44)), _c(tc), Vector3(0, 0.67, -0.02))
			# segmented armour bands and shoulder plates over a team tunic
			_m(torso, B3Mats.box(Vector3(0.52, 0.44, 0.35)), st, Vector3(0, 0.36, 0))
			for i in 3:
				_m(torso, B3Mats.box(Vector3(0.53, 0.02, 0.36)), _c(METAL.darkened(0.45)), Vector3(0, 0.2 + i * 0.11, 0), Vector3.ZERO, Vector3.ONE, false)
			for sx: float in [-1.0, 1.0]:
				_m(torso, B3Mats.hemi(0.15), st, Vector3(0.29 * sx, 0.54, 0))
			for i in 3:
				_m(torso, B3Mats.box(Vector3(0.035, 0.2, 0.02)), _c(Color("6b4a2e")), Vector3(-0.08 + i * 0.08, -0.07, 0.165), Vector3.ZERO, Vector3.ONE, false)
		"gaul":
			var hair := Color(String(["e0b04a", "c0652a", "d8c070", "8a5a32"][_hrng.randi() % 4]))
			var hm := _c(hair, 0.9)
			# long hair, braids and a big droopy moustache; a gold neck ring
			_m(head, B3Mats.hemi(0.32), hm, Vector3(0, 0.26, -0.02))
			_m(head, B3Mats.box(Vector3(0.52, 0.42, 0.16)), hm, Vector3(0, 0.12, -0.2))
			for sx: float in [-1.0, 1.0]:
				_m(head, B3Mats.capsule(0.06, 0.42), hm, Vector3(0.27 * sx, 0.05, 0.02))
				_m(head, B3Mats.capsule(0.045, 0.3), hm, Vector3(0.09 * sx, 0.06, 0.28), Vector3(0, 0, 55.0 * sx), Vector3.ONE, false)
			_m(torso, B3Mats.torus(0.1, 0.14), _c(H_GOLD, 0.3), Vector3(0, 0.6, 0.02), Vector3.ZERO, Vector3.ONE, false)
			# checked trousers: darker stripes round the legs
			for l in legs:
				for i in 3:
					_m(l, B3Mats.cyl(0.108, 0.108, 0.05, 10), _c(Color("5e4424")), Vector3(0, -0.14 - i * 0.18, 0), Vector3.ZERO, Vector3.ONE, false)
		"saxon":
			# a pointed helmet with a nose guard, a beard and a mail shirt
			_m(head, B3Mats.cyl(0.02, 0.33, 0.36, 16), _c(METAL, 0.35), Vector3(0, 0.45, 0))
			_m(head, B3Mats.cyl(0.338, 0.338, 0.06, 16), _c(METAL.darkened(0.3), 0.4), Vector3(0, 0.29, 0))
			_m(head, B3Mats.box(Vector3(0.05, 0.2, 0.04)), _c(METAL, 0.35), Vector3(0, 0.21, 0.3), Vector3.ZERO, Vector3.ONE, false)
			_m(head, B3Mats.box(Vector3(0.3, 0.2, 0.1)), _c(Color("7a4a2a"), 0.9), Vector3(0, 0.03, 0.235))
			var mail := _c(Color("8c949e"), 0.55)
			_m(torso, B3Mats.box(Vector3(0.5, 0.7, 0.34)), mail, Vector3(0, 0.23, 0))
			for a in arms:
				_m(a, B3Mats.capsule(0.11, 0.32), mail, Vector3(0, -0.12, 0))
		"longbow":
			# a wide-brimmed steel kettle hat, a quilted team jacket, a quiver
			_m(head, B3Mats.hemi(0.31), _c(METAL, 0.4), Vector3(0, 0.3, 0))
			_m(head, B3Mats.cyl(0.47, 0.47, 0.03, 18), _c(METAL, 0.4), Vector3(0, 0.31, 0))
			for i in 3:
				_m(torso, B3Mats.box(Vector3(0.47, 0.02, 0.31)), _c(tc.darkened(0.3)), Vector3(0, 0.2 + i * 0.12, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.cyl(0.08, 0.08, 0.6, 8), _c(WOOD), Vector3(0.1, 0.35, -0.2), Vector3(-15, 0, -20))
			for i in 3:
				_m(torso, B3Mats.box(Vector3(0.03, 0.12, 0.07)), _c(Color("f4f0e6")), Vector3(0.17 + i * 0.035, 0.68, -0.28), Vector3(-15, 0, -20), Vector3.ONE, false)
		"cavalry":
			# steel helmet with a brass comb, black horsehair and a team plume; a breastplate
			_m(head, B3Mats.hemi(0.335), st, Vector3(0, 0.27, 0))
			_m(head, B3Mats.box(Vector3(0.07, 0.16, 0.48)), _c(H_GOLD, 0.35), Vector3(0, 0.62, -0.02))
			_m(head, B3Mats.box(Vector3(0.08, 0.5, 0.1)), _c(black), Vector3(0, 0.42, -0.34), Vector3(-10, 0, 0))
			_m(head, B3Mats.capsule(0.055, 0.36), _c(tc), Vector3(0.24, 0.62, 0.02), Vector3(0, 0, -15))
			_m(torso, B3Mats.box(Vector3(0.52, 0.46, 0.35)), st, Vector3(0, 0.35, 0))
			for l in legs:
				_m(l, B3Mats.capsule(0.115, 0.42), _c(black, 0.4), Vector3(0, -0.52, 0.01))
		"redcoat":
			_tricorn(head, black, Color("f4f0e6"), tc, false)
			_crossbelts(torso)
			_m(torso, B3Mats.box(Vector3(0.42, 0.34, 0.05)), _c(tc.darkened(0.1)), Vector3(0, -0.12, -0.16))
			_m(torso, B3Mats.box(Vector3(0.24, 0.15, 0.09)), _c(black, 0.5), Vector3(0, 0.12, -0.19))
			for l in legs:
				_m(l, B3Mats.capsule(0.112, 0.36), _c(black, 0.6), Vector3(0, -0.53, 0))
		"minuteman":
			# everyday clothes: a hat with a team band, a team sash and neckerchief
			_tricorn(head, Color("3a2e26"), Color(0, 0, 0, 0), tc, true)
			_m(torso, B3Mats.box(Vector3(0.49, 0.09, 0.33)), _c(tc), Vector3(0, 0.08, 0))
			_m(torso, B3Mats.cyl(0.13, 0.15, 0.07, 10), _c(tc), Vector3(0, 0.6, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.cyl(0.02, 0.07, 0.32, 8), _c(Color("efe3c2"), 0.5), Vector3(0.25, 0.2, 0.06), Vector3(0, 0, 70))
		"linesman":
			_shako(head, tc)
			_crossbelts(torso)
			_m(torso, B3Mats.box(Vector3(0.42, 0.32, 0.05)), _c(tc.darkened(0.1)), Vector3(0, -0.11, -0.16))
			_m(torso, B3Mats.box(Vector3(0.24, 0.15, 0.09)), _c(black, 0.5), Vector3(0, 0.12, -0.19))
		"union", "confed":
			# a kepi cap; the team colour shows on its band, the collar, cuffs and belt
			var coat := Color(String(def.get("coat", "2b3a67")))
			_kepi(head, coat, tc if style == "confed" else coat, tc)
			_m(torso, B3Mats.cyl(0.118, 0.128, 0.08, 10), _c(tc), Vector3(0, 0.6, 0), Vector3.ZERO, Vector3.ONE, false)
			for a in arms:
				_m(a, B3Mats.cyl(0.1, 0.1, 0.08, 10), _c(tc), Vector3(0, -0.5, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.box(Vector3(0.49, 0.08, 0.33)), _c(tc), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.box(Vector3(0.09, 0.07, 0.02)), _c(H_GOLD, 0.35), Vector3(0, 0.06, 0.17), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.cyl(0.07, 0.07, 0.5, 10), _c(Color("8a7a5a"), 0.95), Vector3(0, 0.6, -0.12), Vector3(0, 0, 90))
		"gi":
			# a round helmet with a team band, team armbands and a backpack
			var ol := Color("5f6136")
			_m(head, B3Mats.hemi(0.35), _c(ol, 0.7), Vector3(0, 0.26, -0.01))
			_m(head, B3Mats.cyl(0.375, 0.375, 0.035, 18), _c(ol.darkened(0.15), 0.7), Vector3(0, 0.26, -0.01))
			_m(head, B3Mats.cyl(0.352, 0.352, 0.06, 18), _c(tc), Vector3(0, 0.33, -0.01))
			for a in arms:
				_m(a, B3Mats.cyl(0.108, 0.108, 0.1, 10), _c(tc), Vector3(0, -0.14, 0), Vector3.ZERO, Vector3.ONE, false)
			_m(torso, B3Mats.box(Vector3(0.36, 0.34, 0.16)), _c(ol.darkened(0.2)), Vector3(0, 0.34, -0.23))
			_m(torso, B3Mats.box(Vector3(0.49, 0.08, 0.33)), _c(Color("8a8458")), Vector3(0, 0.06, 0), Vector3.ZERO, Vector3.ONE, false)


## A three-cornered hat (one corner to the front) with optional trim and a
## team cockade (or, `band`, a team hat band).
func _tricorn(head: Node3D, c: Color, trim: Color, tc: Color, band: bool) -> void:
	var m := _c(c, 0.8)
	_m(head, B3Mats.cyl(0.22, 0.25, 0.13, 14), m, Vector3(0, 0.42, 0))
	for i in 3:
		var a := deg_to_rad(60.0 + i * 120.0)
		var out := Vector3(sin(a), 0, cos(a))
		var p := out * 0.235 + Vector3(0, 0.4, 0)
		_m(head, B3Mats.box(Vector3(0.64, 0.12, 0.04)), m, p, Vector3(10, rad_to_deg(a), 0))
		if trim.a > 0.0:
			_m(head, B3Mats.box(Vector3(0.65, 0.025, 0.05)), _c(trim), p + out * 0.012 + Vector3(0, 0.058, 0), Vector3(10, rad_to_deg(a), 0), Vector3.ONE, false)
	if band:
		_m(head, B3Mats.cyl(0.255, 0.255, 0.05, 14), _c(tc), Vector3(0, 0.38, 0), Vector3.ZERO, Vector3.ONE, false)
	else:
		var a2 := deg_to_rad(60.0)
		_m(head, B3Mats.cyl(0.065, 0.065, 0.03, 10), _c(tc), Vector3(sin(a2), 0, cos(a2)) * 0.26 + Vector3(0, 0.42, 0), Vector3(80, rad_to_deg(a2), 0), Vector3.ONE, false)


## A tall black shako with a brass plate, a peak and a team plume.
func _shako(head: Node3D, tc: Color) -> void:
	var blk := _c(Color("1d1b22"), 0.6)
	_m(head, B3Mats.cyl(0.255, 0.235, 0.42, 16), blk, Vector3(0, 0.5, 0))
	_m(head, B3Mats.box(Vector3(0.34, 0.025, 0.17)), blk, Vector3(0, 0.31, 0.3), Vector3(12, 0, 0))
	_m(head, B3Mats.box(Vector3(0.17, 0.19, 0.03)), _c(H_GOLD, 0.35), Vector3(0, 0.48, 0.245), Vector3.ZERO, Vector3.ONE, false)
	_m(head, B3Mats.cyl(0.258, 0.258, 0.035, 16), _c(Color("f4f0e6")), Vector3(0, 0.68, 0), Vector3.ZERO, Vector3.ONE, false)
	_m(head, B3Mats.capsule(0.065, 0.32), _c(tc), Vector3(0, 0.84, 0.16))


## A kepi: a soft cap whose top tips forward, with a black peak and a team band.
func _kepi(head: Node3D, c: Color, top_c: Color, tc: Color) -> void:
	var m := _c(c, 0.8)
	_m(head, B3Mats.cyl(0.29, 0.315, 0.12, 16), m, Vector3(0, 0.35, 0))
	_m(head, B3Mats.cyl(0.235, 0.28, 0.13, 16), m, Vector3(0, 0.45, 0.06), Vector3(24, 0, 0))
	_m(head, B3Mats.cyl(0.24, 0.24, 0.03, 16), _c(top_c), Vector3(0, 0.51, 0.09), Vector3(24, 0, 0), Vector3.ONE, false)
	_m(head, B3Mats.cyl(0.32, 0.32, 0.05, 16), _c(tc), Vector3(0, 0.33, 0), Vector3.ZERO, Vector3.ONE, false)
	_m(head, B3Mats.box(Vector3(0.3, 0.025, 0.15)), _c(Color("1d1b22"), 0.4), Vector3(0, 0.29, 0.31), Vector3(18, 0, 0))


## White belts crossed over the chest (and back).
func _crossbelts(torso: Node3D) -> void:
	var w := _c(Color("f4f0e6"), 0.6)
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			_m(torso, B3Mats.box(Vector3(0.075, 0.66, 0.02)), w, Vector3(0, 0.31, 0.165 * sz), Vector3(0, 0, 36.0 * sx), Vector3.ONE, false)


# -------------------------------------------------------------------- rider
## A person on a horse (cavalry, mounted knights). The person is built like
## any other fighter, then sat in the saddle. In the ragdoll the rider and the
## horse are two separate floppy bodies, so the rider tumbles off.
func _build_rider(def: Dictionary, rng: RandomNumberGenerator) -> void:
	_build_human(def, rng)
	var n_rider := parts.size()
	var tc := team_col
	var col := Color(String(H_HORSES[rng.randi() % H_HORSES.size()]))
	var mane := col.darkened(0.55) if col.v < 0.75 else Color("8a8580")
	var skin := _c(col, 0.8)
	var bw := 0.56
	var bh := 0.66
	var bl := 1.5
	var leg := 0.98
	var lr := 0.075
	var knight := style == "horseknight"
	var hb := _pivot("horse", self, Vector3(0, leg + bh * 0.25, 0))
	# body: a long barrel with a deep chest and a round rump
	_m(hb, B3Mats.capsule(bh * 0.5, bl), skin, Vector3.ZERO, Vector3(90, 0, 0), Vector3(bw / bh, 1, 1))
	_m(hb, B3Mats.sphere(bh * 0.53, 12), skin, Vector3(0, 0.03, bl * 0.28), Vector3.ZERO, Vector3(bw / bh * 1.02, 1.0, 1.0))
	_m(hb, B3Mats.sphere(bh * 0.52, 12), skin, Vector3(0, 0.05, -bl * 0.3), Vector3.ZERO, Vector3(bw / bh * 1.04, 1.0, 1.0))
	# saddle with a team saddle cloth; knights' horses wear a long team coat
	if knight:
		# a long cloth coat draped over the horse, hanging to its knees
		_m(hb, B3Mats.capsule(bh * 0.5, bl), _c(tc), Vector3(0, 0.03, 0), Vector3(90, 0, 0), Vector3((bw + 0.1) / bh, 1.06, 1.05))
		_m(hb, B3Mats.cyl(0.5, 0.53, 0.5, 18), _c(tc), Vector3(0, -0.3, 0), Vector3.ZERO, Vector3(bw + 0.14, 1.0, bl * 0.9))
		_m(hb, B3Mats.cyl(0.535, 0.535, 0.06, 18), _c(Color("f6ecd2")), Vector3(0, -0.54, 0), Vector3.ZERO, Vector3(bw + 0.15, 1.0, bl * 0.91), false)
	else:
		_m(hb, B3Mats.box(Vector3(bw + 0.1, 0.42, 0.66)), _c(tc), Vector3(0, 0.16, -0.06))
		_m(hb, B3Mats.box(Vector3(bw + 0.12, 0.05, 0.68)), _c(Color("f6ecd2")), Vector3(0, -0.06, -0.06), Vector3.ZERO, Vector3.ONE, false)
	_m(hb, B3Mats.box(Vector3(0.4, 0.1, 0.5)), _c(Color("5a3a22"), 0.6), Vector3(0, bh * 0.5 + 0.02, -0.06))
	# legs
	var names := ["hleg_fl", "hleg_fr", "hleg_bl", "hleg_br"]
	var lx := bw * 0.3
	var lz := bl * 0.36
	var lpos := [Vector3(lx, -bh * 0.25, lz), Vector3(-lx, -bh * 0.25, lz), Vector3(lx, -bh * 0.25, -lz), Vector3(-lx, -bh * 0.25, -lz)]
	for i in 4:
		var p := _pivot(names[i], hb, lpos[i])
		_m(p, B3Mats.capsule(lr * 1.45, leg * 0.58), skin, Vector3(0, -leg * 0.25, 0))
		_m(p, B3Mats.capsule(lr, leg * 0.6), skin, Vector3(0, -leg * 0.68, 0))
		_m(p, B3Mats.cyl(lr * 1.2, lr * 1.45, 0.11, 10), _c(Color("2e2622")), Vector3(0, -leg + 0.055, 0.01), Vector3.ZERO, Vector3.ONE, false)
	# neck, mane and head
	var hp := _pivot("hhead", hb, Vector3(0, bh * 0.18, bl * 0.4))
	_seg(hp, Vector3(0, -0.05, -0.08), Vector3(0, 0.62, 0.26), 0.22, 0.14, skin)
	_seg(hp, Vector3(0, 0.12, -0.2), Vector3(0, 0.74, 0.17), 0.075, 0.05, _c(mane, 0.95))
	var hn := Node3D.new()
	hn.position = Vector3(0, 0.66, 0.32)
	hp.add_child(hn)
	_m(hn, B3Mats.sphere(0.17, 12), skin, Vector3.ZERO, Vector3.ZERO, Vector3(0.9, 1.0, 1.1))
	_m(hn, B3Mats.capsule(0.12, 0.52), skin, Vector3(0, -0.12, 0.2), Vector3(62, 0, 0))
	_m(hn, B3Mats.sphere(0.115, 10), _c(col.lightened(0.15), 0.8), Vector3(0, -0.24, 0.38), Vector3.ZERO, Vector3(1.0, 0.8, 1.0), false)
	for sx: float in [-1.0, 1.0]:
		_m(hn, B3Mats.sphere(0.022, 6), _c(Color("1d1b22")), Vector3(0.045 * sx, -0.26, 0.48), Vector3.ZERO, Vector3.ONE, false)
		_m(hn, B3Mats.prism(Vector3(0.07, 0.14, 0.04)), skin, Vector3(0.07 * sx, 0.18, -0.04), Vector3(0, 0, -12.0 * sx), Vector3.ONE, false)
		# the bridle's cheek strap in the team colour
		_m(hn, B3Mats.box(Vector3(0.02, 0.04, 0.4)), _c(tc), Vector3(0.11 * sx, -0.1, 0.18), Vector3(-55, 0, 0), Vector3.ONE, false)
	_eye(hn, Vector3(0.13, 0.04, 0.07), 0.035, true)
	_eye(hn, Vector3(-0.13, 0.04, 0.07), 0.035, true)
	if knight:
		_m(hn, B3Mats.box(Vector3(0.16, 0.05, 0.42)), _c(METAL, 0.3), Vector3(0, 0.0, 0.24), Vector3(-60, 0, 0), Vector3.ONE, false)
	# tail (a plain node, so it stays on the horse's body in the ragdoll)
	var tl := Node3D.new()
	tl.position = Vector3(0, bh * 0.28, -bl * 0.5)
	hb.add_child(tl)
	pv["htail"] = tl
	_m(tl, B3Mats.cyl(0.05, 0.13, 0.75, 8), _c(mane, 0.95), Vector3(0, -0.3, -0.1), Vector3(-22, 0, 0))
	# sit the person in the saddle
	var hips: Node3D = pv.hips
	remove_child(hips)
	hb.add_child(hips)
	hips.position = Vector3(0, bh * 0.5 + 0.12, -0.08)
	radius = 0.62
	height = 2.5
	top = 2.65
	reach_y = 1.45
	# ragdoll: the horse is a second body with its own joints
	_part("horse", "box", Vector3(bw, bh, bl), Vector3.ZERO, 8.0, -1)
	var hi := parts.size() - 1
	_part("hhead", "capsule", Vector3(0.17, 0.95, 0), Vector3(0, 0.42, 0.22), 1.4, hi, 30.0, 20.0)
	for n in names:
		_part(String(n), "capsule", Vector3(lr * 1.3, leg, 0), Vector3(0, -leg * 0.5, 0), 0.9, hi, 40.0, 15.0)
	# the rider starts inside the horse (legs round its belly): no shoving,
	# and a little hop so they come off
	for i in n_rider:
		var pd: Dictionary = parts[i]
		pd["kick"] = Vector3(0, 3.0, 0)
		if i == 1:
			continue
		for j in range(hi, parts.size()):
			if j != hi + 1:
				no_collide.append([i, j])


# --------------------------------------------------------------------- quad
func _build_quad(rng: RandomNumberGenerator) -> void:
	var q: Dictionary = QUAD[style]
	var bw: float = q.bw
	var bh: float = q.bh
	var bl: float = q.bl
	var leg: float = q.leg
	var lr: float = q.lr
	var hr: float = q.head
	var col := Color(String(q.col)).lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.06)
	var belly := Color(String(q.belly))
	var tc := team_col
	var wild := team == "wild"
	radius = clampf(maxf(bw * 0.6, bl * 0.32), 0.25, 1.6)
	height = leg + bh
	reach_y = leg + bh * 0.5
	var by := leg + bh * 0.3
	var b := _pivot("body", self, Vector3(0, by, 0))
	# body: a capsule lying along z, squashed to the body's width
	_m(b, B3Mats.capsule(bh * 0.5, bl), _c(col, 0.85), Vector3.ZERO, Vector3(90, 0, 0), Vector3(bw / bh, 1, 1))
	_m(b, B3Mats.capsule(bh * 0.42, bl * 0.86), _c(belly, 0.9), Vector3(0, -bh * 0.1, 0), Vector3(90, 0, 0), Vector3(bw / bh * 0.9, 1, 1), false)
	if not wild:
		_m(b, B3Mats.box(Vector3(bw * 0.85, 0.07 * maxf(1.0, bh), bl * 0.36)), _c(tc), Vector3(0, bh * 0.47, -bl * 0.02))
		_m(b, B3Mats.box(Vector3(bw * 0.9, 0.04, bl * 0.4)), _c(tc.lightened(0.3)), Vector3(0, bh * 0.44, -bl * 0.02), Vector3.ZERO, Vector3.ONE, false)
	# legs
	var lx := bw * 0.3
	var lz := bl * 0.33
	var names := ["leg_fl", "leg_fr", "leg_bl", "leg_br"]
	var lpos := [Vector3(lx, -bh * 0.3, lz), Vector3(-lx, -bh * 0.3, lz), Vector3(lx, -bh * 0.3, -lz), Vector3(-lx, -bh * 0.3, -lz)]
	for i in 4:
		var p := _pivot(names[i], b, lpos[i])
		_m(p, B3Mats.capsule(lr, leg + lr), _c(col, 0.85), Vector3(0, -leg * 0.5 + lr * 0.3, 0))
		var foot := Color("3a3330") if style != "elephant" and style != "brachio" else col.lightened(0.25)
		_m(p, B3Mats.cyl(lr * 1.1, lr * 1.25, lr * 0.8, 10), _c(foot), Vector3(0, -leg + lr * 0.4, 0.02), Vector3.ZERO, Vector3.ONE, false)
	# neck + head
	var neck_up := 0.0
	var neck_fwd := 0.0
	if style == "brachio":
		neck_up = 3.6
		neck_fwd = 1.4
	elif style == "bull" or style == "bear" or style == "elephant" or style == "trike" or style == "mammoth":
		neck_up = bh * 0.05
		neck_fwd = hr * 0.5
	else:
		neck_up = bh * 0.35
		neck_fwd = hr * 0.6
	var hp := _pivot("head", b, Vector3(0, bh * 0.2, bl * 0.45))
	if neck_up > 1.0:
		var nl := Vector2(neck_fwd, neck_up).length()
		var ang := rad_to_deg(atan2(neck_fwd, neck_up))
		_m(hp, B3Mats.cyl(0.24, 0.42, nl, 12), _c(col, 0.85), Vector3(0, neck_up * 0.5, neck_fwd * 0.5), Vector3(ang, 0, 0))
	var hc := Vector3(0, neck_up, neck_fwd + hr * 0.5)
	var head_node := Node3D.new()
	head_node.position = hc
	hp.add_child(head_node)
	_m(head_node, B3Mats.sphere(hr, 14), _c(col, 0.85), Vector3.ZERO, Vector3.ZERO, Vector3(1, 0.92, 1.1))
	var eye_r := clampf(hr * 0.16, 0.035, 0.11)
	_eye(head_node, Vector3(hr * 0.5, hr * 0.32, hr * 0.62), eye_r, true)
	_eye(head_node, Vector3(-hr * 0.5, hr * 0.32, hr * 0.62), eye_r, true)
	if not wild:
		_m(hp, B3Mats.torus(hr * 0.55, hr * 0.78), _c(tc), Vector3(0, neck_up * 0.15, 0.0 + neck_fwd * 0.1), Vector3(70, 0, 0))
	var jaw := Node3D.new()
	jaw.position = Vector3(0, -hr * 0.3, hr * 0.4)
	jaw.set_meta("pivot", true)
	head_node.add_child(jaw)
	pv["jaw"] = jaw
	match style:
		"dog", "wolf":
			_m(head_node, B3Mats.box(Vector3(hr * 0.75, hr * 0.6, hr * 1.1)), _c(col.lightened(0.1)), Vector3(0, -hr * 0.15, hr * 0.9))
			_m(head_node, B3Mats.sphere(hr * 0.2, 8), _c(Color("1d1b22")), Vector3(0, hr * 0.1, hr * 1.45), Vector3.ZERO, Vector3.ONE, false)
			_m(jaw, B3Mats.box(Vector3(hr * 0.6, hr * 0.2, hr * 0.8)), _c(belly), Vector3(0, -0.02, hr * 0.5))
			for sx in [-1.0, 1.0]:
				if style == "wolf":
					_m(head_node, B3Mats.prism(Vector3(hr * 0.5, hr * 0.7, hr * 0.2)), _c(col.darkened(0.15)), Vector3(hr * 0.55 * sx, hr * 0.85, -hr * 0.1))
				else:
					_m(head_node, B3Mats.box(Vector3(hr * 0.3, hr * 0.8, hr * 0.14)), _c(col.darkened(0.3)), Vector3(hr * 0.85 * sx, hr * 0.1, -hr * 0.1), Vector3(0, 0, 25 * sx))
		"bear":
			_m(head_node, B3Mats.sphere(hr * 0.45, 10), _c(belly), Vector3(0, -hr * 0.2, hr * 0.85))
			_m(head_node, B3Mats.sphere(hr * 0.14, 8), _c(Color("1d1b22")), Vector3(0, -hr * 0.05, hr * 1.25), Vector3.ZERO, Vector3.ONE, false)
			_m(jaw, B3Mats.box(Vector3(hr * 0.5, hr * 0.15, hr * 0.5)), _c(belly), Vector3(0, -0.02, hr * 0.4))
			for sx in [-1.0, 1.0]:
				_m(head_node, B3Mats.sphere(hr * 0.28, 8), _c(col.darkened(0.15)), Vector3(hr * 0.7 * sx, hr * 0.8, -hr * 0.1))
		"bull":
			_m(head_node, B3Mats.box(Vector3(hr * 1.2, hr * 0.8, hr * 0.7)), _c(Color("d9b8a0")), Vector3(0, -hr * 0.35, hr * 0.75))
			_m(jaw, B3Mats.box(Vector3(hr * 0.9, hr * 0.2, hr * 0.5)), _c(Color("d9b8a0")), Vector3(0, -0.05, hr * 0.4))
			_m(head_node, B3Mats.torus(hr * 0.12, hr * 0.2), _c(Color("e8c14a"), 0.3), Vector3(0, -hr * 0.55, hr * 1.12), Vector3(90, 0, 0), Vector3.ONE, false)
			for sx in [-1.0, 1.0]:
				_m(head_node, B3Mats.cyl(0.02, 0.07, hr * 1.3, 8), _c(Color("f3ead6"), 0.4), Vector3(hr * 1.05 * sx, hr * 0.55, hr * 0.1), Vector3(-30, 0, -70 * sx))
		"elephant":
			_m(head_node, B3Mats.cyl(0.1, 0.28, 1.5, 10), _c(col, 0.85), Vector3(0, -0.75, hr * 0.85), Vector3(-12, 0, 0))
			_m(jaw, B3Mats.box(Vector3(0.3, 0.14, 0.3)), _c(col.darkened(0.15)), Vector3(0, -0.1, 0.1))
			for sx in [-1.0, 1.0]:
				_m(head_node, B3Mats.cyl(0.62, 0.62, 0.08, 16), _c(col.darkened(0.08), 0.85), Vector3(hr * 0.95 * sx, 0.05, -hr * 0.1), Vector3(0, -25 * sx, 90))
				_m(head_node, B3Mats.cyl(0.02, 0.07, 0.75, 8), _c(Color("fbf6e8"), 0.35), Vector3(hr * 0.35 * sx, -0.45, hr * 0.85), Vector3(-60, 0, 0))
		"trike":
			_m(head_node, B3Mats.box(Vector3(hr * 1.0, hr * 0.8, hr * 1.2)), _c(col.lightened(0.05)), Vector3(0, -hr * 0.2, hr * 0.7))
			_m(head_node, B3Mats.cyl(0.02, 0.1, 0.35, 8), _c(Color("f3ead6"), 0.4), Vector3(0, hr * 0.15, hr * 1.35), Vector3(60, 0, 0))
			_m(head_node, B3Mats.prism(Vector3(hr * 0.3, hr * 0.4, hr * 0.4)), _c(Color("e0a040")), Vector3(0, -hr * 0.3, hr * 1.4), Vector3(90, 0, 0))
			for sx in [-1.0, 1.0]:
				_m(head_node, B3Mats.cyl(0.02, 0.12, 0.9, 8), _c(Color("f3ead6"), 0.4), Vector3(hr * 0.45 * sx, hr * 0.7, hr * 0.7), Vector3(55, 0, 8 * sx))
			_m(head_node, B3Mats.cyl(hr * 1.45, hr * 1.45, 0.12, 18), _c(Color("e0a040")), Vector3(0, hr * 0.5, -hr * 0.35), Vector3(-65, 0, 0))
			_m(head_node, B3Mats.cyl(hr * 1.2, hr * 1.2, 0.13, 18), _c(Color("4b8ba8") if wild else tc), Vector3(0, hr * 0.5, -hr * 0.32), Vector3(-65, 0, 0), Vector3.ONE, false)
			_m(jaw, B3Mats.box(Vector3(hr * 0.8, hr * 0.25, hr * 0.8)), _c(belly), Vector3(0, -0.05, hr * 0.45))
		"stego":
			_m(head_node, B3Mats.box(Vector3(hr * 0.9, hr * 0.7, hr * 1.4)), _c(col), Vector3(0, -hr * 0.1, hr * 0.6))
			_m(jaw, B3Mats.box(Vector3(hr * 0.7, hr * 0.2, hr * 1.0)), _c(belly), Vector3(0, -0.04, hr * 0.5))
			var plate := Color("d6553a") if wild else tc
			for i in 6:
				var z := lerpf(bl * 0.38, -bl * 0.42, i / 5.0)
				var s := 0.55 + 0.45 * sin(PI * (i + 0.5) / 6.0)
				_m(b, B3Mats.prism(Vector3(0.12, 0.85 * s, 0.75 * s)), _c(plate), Vector3(0.12 if i % 2 == 0 else -0.12, bh * 0.45 + 0.3 * s, z), Vector3(0, 90, 0))
		"brachio":
			_m(head_node, B3Mats.box(Vector3(hr * 0.9, hr * 0.7, hr * 1.5)), _c(col), Vector3(0, -hr * 0.05, hr * 0.7))
			_m(jaw, B3Mats.box(Vector3(hr * 0.7, hr * 0.2, hr * 1.0)), _c(belly), Vector3(0, -0.04, hr * 0.55))
			for i in 7:
				_m(b, B3Mats.sphere(0.12, 8), _c(col.darkened(0.25)), Vector3(0, bh * 0.48, lerpf(bl * 0.4, -bl * 0.4, i / 6.0)), Vector3.ZERO, Vector3.ONE, false)
		"mammoth":
			var fur := col.darkened(0.2)
			var ivory := _c(Color("f6eedb"), 0.35)
			# domed head and a big shoulder hump
			_m(head_node, B3Mats.sphere(hr * 0.72, 12), _c(col, 0.95), Vector3(0, hr * 0.5, -hr * 0.12))
			_m(b, B3Mats.sphere(bh * 0.5, 12), _c(col, 0.95), Vector3(0, bh * 0.36, bl * 0.2), Vector3.ZERO, Vector3(bw / bh * 0.78, 0.72, 0.95))
			# a shaggy coat: a long skirt of wool with ragged tufts along its hem
			_m(b, B3Mats.capsule(bh * 0.42, bl * 0.95), _c(fur, 0.95), Vector3(0, -bh * 0.16, 0.0), Vector3(90, 0, 0), Vector3(bw / bh * 1.12, 1.0, 1.0))
			for i in 7:
				var z: float = lerpf(bl * 0.4, -bl * 0.36, i / 6.0)
				for sx: float in [-1.0, 1.0]:
					_m(b, B3Mats.prism(Vector3(0.24, 0.32, 0.12)), _c(fur, 0.95), Vector3(bw * 0.5 * sx, -bh * 0.5, z + 0.08 * sx), Vector3(0, 90, 180), Vector3.ONE, false)
			_m(b, B3Mats.sphere(0.5, 10), _c(fur, 0.95), Vector3(0, -bh * 0.18, bl * 0.4), Vector3.ZERO, Vector3(1.4, 1.1, 0.6), false)
			for sx: float in [-1.0, 0.0, 1.0]:
				_m(b, B3Mats.prism(Vector3(0.26, 0.34, 0.12)), _c(fur, 0.95), Vector3(0.28 * sx, -bh * 0.52, bl * 0.47), Vector3(0, 0, 180), Vector3.ONE, false)
			_m(head_node, B3Mats.sphere(0.38, 10), _c(fur, 0.95), Vector3(0, -hr * 0.45, hr * 0.15), Vector3.ZERO, Vector3(1.5, 0.8, 0.9), false)
			# little furry ears
			for sx in [-1.0, 1.0]:
				_m(head_node, B3Mats.sphere(0.24, 10), _c(fur), Vector3(hr * 0.88 * sx, 0.05, -hr * 0.15), Vector3.ZERO, Vector3(0.42, 1.0, 0.85))
			# trunk that curls at the tip
			var tr_pts := [Vector3(0, -0.15, hr * 0.8), Vector3(0, -0.65, hr * 1.0), Vector3(0, -1.1, hr * 1.08), Vector3(0, -1.38, hr * 1.25), Vector3(0, -1.42, hr * 1.5)]
			var tr_r := [0.25, 0.2, 0.16, 0.13, 0.11]
			for i in 4:
				_seg(head_node, tr_pts[i], tr_pts[i + 1], tr_r[i], tr_r[i + 1], _c(col, 0.9))
			# big curvy tusks
			for sx in [-1.0, 1.0]:
				var tk := [Vector3(0.28 * sx, -0.35, 0.6), Vector3(0.36 * sx, -0.85, 0.85), Vector3(0.4 * sx, -1.08, 1.3), Vector3(0.32 * sx, -0.95, 1.75), Vector3(0.1 * sx, -0.58, 1.95)]
				var tkr := [0.11, 0.095, 0.08, 0.06, 0.025]
				for i in 4:
					_seg(head_node, tk[i], tk[i + 1], tkr[i], tkr[i + 1], ivory)
			_m(jaw, B3Mats.box(Vector3(0.32, 0.14, 0.3)), _c(col.darkened(0.15)), Vector3(0, -0.1, 0.1))
	# tail
	var tl: float = q.tail
	var tr: float = q.tr
	var tp := _pivot("tail", b, Vector3(0, bh * 0.15, -bl * 0.45))
	var tail_tip := 0.02 if style != "wolf" else tr * 0.5
	_m(tp, B3Mats.cyl(tail_tip, tr, tl, 10), _c(col, 0.85), Vector3(0, 0, -tl * 0.5), Vector3(-90, 0, 0))
	if style == "stego":
		for sx in [-1.0, 1.0]:
			for k in 2:
				_m(tp, B3Mats.cyl(0.0, 0.08, 0.6, 8), _c(Color("f3ead6"), 0.4), Vector3(0.12 * sx, 0.12, -tl * (0.75 + 0.12 * k)), Vector3(0, 0, -60 * sx))
	if style == "bull" or style == "elephant" or style == "mammoth":
		_m(tp, B3Mats.sphere(0.08 if style != "mammoth" else 0.14, 8), _c(col.darkened(0.4)), Vector3(0, 0, -tl), Vector3.ZERO, Vector3.ONE, false)
	tp.rotation.x = -0.35 if style == "dog" else (-0.9 if style == "mammoth" else 0.2)
	# ragdoll
	_part("body", "box", Vector3(bw, bh, bl), Vector3.ZERO, 6.0, -1)
	var head_c := hc
	if neck_up > 1.0:
		_part("head", "capsule", Vector3(0.35, Vector2(neck_fwd, neck_up).length() + hr, 0), Vector3(0, neck_up * 0.5, neck_fwd * 0.5), 1.4, 0, 30.0, 20.0)
	else:
		_part("head", "sphere", Vector3(hr * 1.05, 0, 0), head_c, 1.2, 0, 35.0, 20.0)
	_part("tail", "capsule", Vector3(maxf(tr * 0.8, 0.05), tl, 0), Vector3(0, 0, -tl * 0.5), 0.6, 0, 45.0, 15.0, "z")
	for i in 4:
		_part(names[i], "capsule", Vector3(lr * 1.1, leg + lr, 0), Vector3(0, -leg * 0.5, 0), 0.8, 0, 45.0, 15.0)


# -------------------------------------------------------------------- biped
func _build_biped(rng: RandomNumberGenerator) -> void:
	var q: Dictionary = BIPED[style]
	var bw: float = q.bw
	var bh: float = q.bh
	var bl: float = q.bl
	var leg: float = q.leg
	var lr: float = q.lr
	var hd: Vector3 = q.head
	var col := Color(String(q.col)).lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.06)
	var belly := Color(String(q.belly))
	var tc := team_col
	var wild := team == "wild"
	radius = clampf(bl * 0.38, 0.3, 1.3)
	height = leg + bh + hd.y
	reach_y = leg + bh * 0.6
	var b := _pivot("body", self, Vector3(0, leg + bh * 0.25, 0))
	b.rotation.x = -0.18
	_m(b, B3Mats.capsule(bh * 0.5, bl), _c(col, 0.85), Vector3.ZERO, Vector3(90, 0, 0), Vector3(bw / bh, 1, 1))
	_m(b, B3Mats.capsule(bh * 0.4, bl * 0.8), _c(belly, 0.9), Vector3(0, -bh * 0.13, bl * 0.04), Vector3(90, 0, 0), Vector3(bw / bh * 0.9, 1, 1), false)
	if not wild:
		_m(b, B3Mats.box(Vector3(bw * 0.9, 0.08 * maxf(1.0, bh), bl * 0.3)), _c(tc), Vector3(0, bh * 0.47, -bl * 0.05))
	if style == "raptor":
		for i in 4:
			_m(b, B3Mats.box(Vector3(bw * 1.02, 0.06, 0.08)), _c(col.darkened(0.35)), Vector3(0, bh * 0.36, lerpf(bl * 0.3, -bl * 0.35, i / 3.0)), Vector3(0, 0, 0), Vector3.ONE, false)
	# legs
	for sx in [1.0, -1.0]:
		var p := _pivot("leg_l" if sx > 0 else "leg_r", b, Vector3(bw * 0.42 * sx, -bh * 0.15, -bl * 0.05))
		_m(p, B3Mats.capsule(lr * 1.35, leg * 0.62), _c(col, 0.85), Vector3(0, -leg * 0.25, 0.06 * leg), Vector3(-15, 0, 0))
		_m(p, B3Mats.capsule(lr * 0.85, leg * 0.62), _c(col, 0.85), Vector3(0, -leg * 0.65, -0.02 * leg), Vector3(12, 0, 0))
		_m(p, B3Mats.box(Vector3(lr * 2.2, lr * 0.7, lr * 3.2)), _c(col.darkened(0.2)), Vector3(0, -leg * 0.95, lr * 0.9), Vector3.ZERO, Vector3.ONE, false)
	# head with jaw
	var hp := _pivot("head", b, Vector3(0, bh * 0.3, bl * 0.48))
	hp.rotation.x = 0.18
	_m(hp, B3Mats.cyl(bh * 0.28, bh * 0.36, bh * 0.6, 10), _c(col, 0.85), Vector3(0, bh * 0.15, bh * 0.1), Vector3(60, 0, 0))
	var hn := Node3D.new()
	hn.position = Vector3(0, bh * 0.35, hd.z * 0.35)
	hp.add_child(hn)
	_m(hn, B3Mats.box(hd * Vector3(1, 0.62, 1)), _c(col, 0.85), Vector3(0, hd.y * 0.1, hd.z * 0.1))
	_m(hn, B3Mats.box(hd * Vector3(0.9, 0.3, 0.9)), _c(col.darkened(0.12)), Vector3(0, hd.y * 0.38, hd.z * 0.05))
	var er := hd.x * 0.13
	_eye(hn, Vector3(hd.x * 0.48, hd.y * 0.33, hd.z * 0.05), er, true)
	_eye(hn, Vector3(-hd.x * 0.48, hd.y * 0.33, hd.z * 0.05), er, true)
	for sx in [-1.0, 1.0]:
		for k in 3:
			_m(hn, B3Mats.cyl(0.0, hd.x * 0.07, hd.y * 0.16, 6), _c(Color("fbf8ee"), 0.4), Vector3(hd.x * 0.38 * sx, -hd.y * 0.24, hd.z * (0.55 - 0.15 * k)), Vector3(180, 0, 0), Vector3.ONE, false)
	var jaw := Node3D.new()
	jaw.position = Vector3(0, -hd.y * 0.25, -hd.z * 0.25)
	jaw.set_meta("pivot", true)
	hn.add_child(jaw)
	pv["jaw"] = jaw
	_m(jaw, B3Mats.box(hd * Vector3(0.85, 0.22, 0.85)), _c(belly, 0.85), Vector3(0, -hd.y * 0.05, hd.z * 0.38))
	# tiny arms
	for sx in [1.0, -1.0]:
		_m(b, B3Mats.capsule(lr * 0.4, bh * 0.45), _c(col, 0.85), Vector3(bw * 0.42 * sx, -bh * 0.15, bl * 0.38), Vector3(-60, 0, 0), Vector3.ONE, false)
	# tail
	var tl: float = q.tail
	var tr: float = q.tr
	var tp := _pivot("tail", b, Vector3(0, bh * 0.05, -bl * 0.42))
	tp.rotation.x = 0.12
	_m(tp, B3Mats.cyl(0.03, tr, tl, 10), _c(col, 0.85), Vector3(0, 0, -tl * 0.5), Vector3(-90, 0, 0))
	_part("body", "box", Vector3(bw, bh, bl), Vector3.ZERO, 5.0, -1)
	_part("head", "box", Vector3(hd.x, hd.y, hd.z), hn.position + Vector3(0, 0, hd.z * 0.1), 1.3, 0, 35.0, 20.0)
	_part("tail", "capsule", Vector3(tr * 0.75, tl, 0), Vector3(0, 0, -tl * 0.5), 0.9, 0, 40.0, 15.0, "z")
	_part("leg_l", "capsule", Vector3(lr * 1.2, leg, 0), Vector3(0, -leg * 0.5, 0), 1.1, 0, 50.0, 15.0)
	_part("leg_r", "capsule", Vector3(lr * 1.2, leg, 0), Vector3(0, -leg * 0.5, 0), 1.1, 0, 50.0, 15.0)


# -------------------------------------------------------------------- birds
func _build_chicken() -> void:
	var tc := team_col
	radius = 0.22
	height = 0.75
	reach_y = 0.4
	var b := _pivot("body", self, Vector3(0, 0.42, 0))
	_m(b, B3Mats.sphere(0.24, 14), _c(Color("fbfaf4"), 0.9), Vector3.ZERO, Vector3.ZERO, Vector3(0.95, 0.9, 1.15))
	_m(b, B3Mats.prism(Vector3(0.22, 0.3, 0.1)), _c(Color("f2efe4")), Vector3(0, 0.15, -0.26), Vector3(-30, 0, 0))
	if team != "wild":
		_m(b, B3Mats.torus(0.08, 0.13), _c(tc), Vector3(0, 0.13, 0.15), Vector3(60, 0, 0))
	var wl := _pivot("wing_l", b, Vector3(0.21, 0.03, 0.0))
	var wr := _pivot("wing_r", b, Vector3(-0.21, 0.03, 0.0))
	_m(wl, B3Mats.sphere(0.13, 8), _c(Color("eeebe0")), Vector3(0.0, -0.02, -0.02), Vector3.ZERO, Vector3(0.4, 0.8, 1.2))
	_m(wr, B3Mats.sphere(0.13, 8), _c(Color("eeebe0")), Vector3(0.0, -0.02, -0.02), Vector3.ZERO, Vector3(0.4, 0.8, 1.2))
	var hp := _pivot("head", b, Vector3(0, 0.2, 0.17))
	_m(hp, B3Mats.sphere(0.12, 12), _c(Color("fbfaf4"), 0.9), Vector3(0, 0.08, 0.02))
	_m(hp, B3Mats.cyl(0.0, 0.045, 0.1, 6), _c(Color("ffb02e"), 0.5), Vector3(0, 0.06, 0.15), Vector3(90, 0, 0), Vector3.ONE, false)
	for i in 3:
		_m(hp, B3Mats.sphere(0.04, 6), _c(Color("e63b3b")), Vector3(0, 0.2 + (0.02 if i == 1 else 0.0), 0.06 - i * 0.05), Vector3.ZERO, Vector3.ONE, false)
	_m(hp, B3Mats.sphere(0.03, 6), _c(Color("e63b3b")), Vector3(0, -0.01, 0.12), Vector3.ZERO, Vector3.ONE, false)
	_eye(hp, Vector3(0.07, 0.11, 0.08), 0.022)
	_eye(hp, Vector3(-0.07, 0.11, 0.08), 0.022)
	for sx in [1.0, -1.0]:
		var p := _pivot("leg_l" if sx > 0 else "leg_r", b, Vector3(0.08 * sx, -0.15, 0.0))
		_m(p, B3Mats.cyl(0.018, 0.018, 0.3, 6), _c(Color("ffb02e")), Vector3(0, -0.13, 0))
		_m(p, B3Mats.box(Vector3(0.1, 0.02, 0.12)), _c(Color("ffb02e")), Vector3(0, -0.27, 0.03), Vector3.ZERO, Vector3.ONE, false)
	_part("body", "sphere", Vector3(0.24, 0, 0), Vector3.ZERO, 1.5, -1)
	_part("head", "sphere", Vector3(0.12, 0, 0), Vector3(0, 0.08, 0.02), 0.4, 0, 40.0, 20.0)
	_part("leg_l", "capsule", Vector3(0.03, 0.3, 0), Vector3(0, -0.13, 0), 0.2, 0, 40.0, 10.0)
	_part("leg_r", "capsule", Vector3(0.03, 0.3, 0), Vector3(0, -0.13, 0), 0.2, 0, 40.0, 10.0)


func _build_ptero() -> void:
	var tc := team_col
	var col := Color("c0603a")
	radius = 0.5
	height = 0.9
	reach_y = 0.3
	var b := _pivot("body", self, Vector3(0, 0.5, 0))
	_m(b, B3Mats.capsule(0.2, 0.95), _c(col, 0.85), Vector3.ZERO, Vector3(90, 0, 0))
	_m(b, B3Mats.capsule(0.15, 0.7), _c(Color("f0c890")), Vector3(0, -0.06, 0.03), Vector3(90, 0, 0), Vector3.ONE, false)
	if team != "wild":
		_m(b, B3Mats.box(Vector3(0.3, 0.06, 0.4)), _c(tc), Vector3(0, 0.19, 0))
	for sx in [1.0, -1.0]:
		var w := _pivot("wing_l" if sx > 0 else "wing_r", b, Vector3(0.16 * sx, 0.06, 0.12))
		_m(w, B3Mats.box(Vector3(1.0, 0.04, 0.62)), _c(col.lightened(0.15), 0.9), Vector3(0.55 * sx, 0, -0.12))
		_m(w, B3Mats.box(Vector3(0.9, 0.035, 0.4)), _c(col.lightened(0.25), 0.9), Vector3(1.4 * sx, 0, -0.05), Vector3(0, 15 * sx, 0))
		_m(w, B3Mats.box(Vector3(1.9, 0.07, 0.06)), _c(col.darkened(0.1)), Vector3(0.95 * sx, 0.02, 0.17), Vector3.ZERO, Vector3.ONE, false)
	var hp := _pivot("head", b, Vector3(0, 0.12, 0.5))
	_m(hp, B3Mats.sphere(0.16, 10), _c(col, 0.85), Vector3(0, 0.05, 0.08))
	_m(hp, B3Mats.cyl(0.0, 0.07, 0.75, 8), _c(Color("e8c070"), 0.5), Vector3(0, 0.0, 0.5), Vector3(90, 0, 0))
	_m(hp, B3Mats.prism(Vector3(0.06, 0.25, 0.5)), _c(Color("d94c3a") if team == "wild" else tc), Vector3(0, 0.16, -0.18), Vector3(-90, 0, 0))
	_eye(hp, Vector3(0.11, 0.1, 0.12), 0.03, true)
	_eye(hp, Vector3(-0.11, 0.1, 0.12), 0.03, true)
	for sx in [1.0, -1.0]:
		var p := _pivot("leg_l" if sx > 0 else "leg_r", b, Vector3(0.1 * sx, -0.12, -0.25))
		_m(p, B3Mats.cyl(0.025, 0.025, 0.3, 6), _c(col.darkened(0.2)), Vector3(0, -0.13, 0), Vector3.ZERO, Vector3.ONE, false)
	_part("body", "capsule", Vector3(0.22, 0.95, 0), Vector3.ZERO, 1.5, -1, 60.0, 20.0, "z")
	_part("head", "sphere", Vector3(0.18, 0, 0), Vector3(0, 0.05, 0.12), 0.4, 0, 40.0, 20.0)
	_part("wing_l", "box", Vector3(1.9, 0.06, 0.6), Vector3(0.95, 0, -0.1), 0.35, 0, 70.0, 30.0)
	_part("wing_r", "box", Vector3(1.9, 0.06, 0.6), Vector3(-0.95, 0, -0.1), 0.35, 0, 70.0, 30.0)


# -------------------------------------------------------------------- robot
## A chunky tin robot with a laser cannon for a right hand. Same joints as a
## person, so it walks and aims with the human animations.
func _build_robot() -> void:
	var tc := team_col
	var mt := _c(ROBOT, 0.35)
	var dk := _c(ROBOT_DARK, 0.45)
	var glow_eye := B3Mats.glow(Color(0.45, 0.95, 1.0), 2.6)
	radius = 0.36
	height = 1.95
	top = 2.0
	reach_y = 1.15
	hold = "gun"
	var hips := _pivot("hips", self, Vector3(0, 0.78, 0))
	var torso := _pivot("torso", hips, Vector3.ZERO)
	var head := _pivot("head", torso, Vector3(0, 0.68, 0))
	var arm_l := _pivot("arm_l", torso, Vector3(0.42, 0.5, 0))
	var arm_r := _pivot("arm_r", torso, Vector3(-0.42, 0.5, 0))
	var leg_l := _pivot("leg_l", hips, Vector3(0.15, 0.0, 0))
	var leg_r := _pivot("leg_r", hips, Vector3(-0.15, 0.0, 0))
	# body: a big tin box with a team chest plate and a glowing power core
	_m(torso, B3Mats.box(Vector3(0.64, 0.6, 0.44)), mt, Vector3(0, 0.32, 0))
	_m(torso, B3Mats.box(Vector3(0.44, 0.16, 0.36)), dk, Vector3(0, -0.02, 0))
	_m(torso, B3Mats.box(Vector3(0.42, 0.3, 0.04)), _c(tc, 0.5), Vector3(0, 0.36, 0.23))
	_m(torso, B3Mats.cyl(0.075, 0.075, 0.05, 12), glow_eye, Vector3(0, 0.36, 0.26), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(torso, B3Mats.box(Vector3(0.3, 0.34, 0.12)), dk, Vector3(0, 0.34, -0.27))
	for sx in [-1.0, 1.0]:
		_m(torso, B3Mats.box(Vector3(0.26, 0.13, 0.32)), _c(tc, 0.5), Vector3(0.38 * sx, 0.6, 0))
		_m(torso, B3Mats.sphere(0.035, 6), dk, Vector3(0.24 * sx, 0.56, 0.22), Vector3.ZERO, Vector3.ONE, false)
		_m(torso, B3Mats.sphere(0.035, 6), dk, Vector3(0.24 * sx, 0.1, 0.22), Vector3.ZERO, Vector3.ONE, false)
		_m(torso, B3Mats.cyl(0.04, 0.04, 0.22, 8), dk, Vector3(0.09 * sx, 0.52, -0.36), Vector3(-20, 0, 0), Vector3.ONE, false)
	_m(torso, B3Mats.cyl(0.08, 0.09, 0.14, 10), dk, Vector3(0, 0.64, 0), Vector3.ZERO, Vector3.ONE, false)
	# head: box with a visor, two glowing eyes, ear bolts and an antenna
	_m(head, B3Mats.box(Vector3(0.44, 0.36, 0.4)), mt, Vector3(0, 0.2, 0))
	_m(head, B3Mats.box(Vector3(0.38, 0.13, 0.03)), _c(Color("1d2026"), 0.3), Vector3(0, 0.24, 0.2), Vector3.ZERO, Vector3.ONE, false)
	for sx in [-1.0, 1.0]:
		var e := Node3D.new()
		e.name = "Eye"
		e.position = Vector3(0.09 * sx, 0.24, 0.215)
		head.add_child(e)
		_m(e, B3Mats.sphere(0.045, 8), glow_eye, Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
		eyes.append(e)
		_m(head, B3Mats.cyl(0.07, 0.07, 0.06, 10), dk, Vector3(0.24 * sx, 0.2, 0), Vector3(0, 0, 90), Vector3.ONE, false)
	for i in 3:
		_m(head, B3Mats.box(Vector3(0.2, 0.018, 0.02)), dk, Vector3(0, 0.1 - i * 0.035, 0.205), Vector3.ZERO, Vector3.ONE, false)
	_m(head, B3Mats.cyl(0.015, 0.015, 0.26, 6), dk, Vector3(0.12, 0.5, 0), Vector3.ZERO, Vector3.ONE, false)
	_m(head, B3Mats.sphere(0.055, 8), B3Mats.glow(Color(1.0, 0.25, 0.2), 2.2), Vector3(0.12, 0.64, 0), Vector3.ZERO, Vector3.ONE, false)
	# arms: shoulder ball, upper arm, elbow, chunky forearm; claw + laser cannon
	for arm in [arm_l, arm_r]:
		var a: Node3D = arm
		_m(a, B3Mats.sphere(0.11, 10), dk, Vector3(0, -0.02, 0))
		_m(a, B3Mats.cyl(0.08, 0.08, 0.32, 10), mt, Vector3(0, -0.2, 0))
		_m(a, B3Mats.sphere(0.085, 8), dk, Vector3(0, -0.38, 0), Vector3.ZERO, Vector3.ONE, false)
		_m(a, B3Mats.box(Vector3(0.17, 0.3, 0.17)), mt, Vector3(0, -0.54, 0))
	for sx in [-1.0, 1.0]:
		_m(arm_l, B3Mats.prism(Vector3(0.07, 0.16, 0.08)), dk, Vector3(0.045 * sx, -0.76, 0), Vector3(0, 0, 180), Vector3.ONE, false)
	_m(arm_r, B3Mats.cyl(0.1, 0.12, 0.26, 12), dk, Vector3(0, -0.8, 0))
	_m(arm_r, B3Mats.torus(0.07, 0.11), B3Mats.glow(Color(1.0, 0.3, 0.25), 2.4), Vector3(0, -0.93, 0), Vector3.ZERO, Vector3.ONE, false)
	muzzle = _marker(arm_r, Vector3(0, -0.97, 0))
	# legs: boxy thighs and shins, knee balls, big flat feet
	for leg in [leg_l, leg_r]:
		var l: Node3D = leg
		_m(l, B3Mats.box(Vector3(0.2, 0.36, 0.22)), mt, Vector3(0, -0.2, 0))
		_m(l, B3Mats.sphere(0.095, 8), dk, Vector3(0, -0.4, 0), Vector3.ZERO, Vector3.ONE, false)
		_m(l, B3Mats.box(Vector3(0.22, 0.28, 0.24)), mt, Vector3(0, -0.56, 0))
		_m(l, B3Mats.box(Vector3(0.27, 0.11, 0.4)), dk, Vector3(0, -0.725, 0.06))
	_part("torso", "box", Vector3(0.64, 0.86, 0.44), Vector3(0, 0.22, 0), 4.0, -1)
	_part("head", "box", Vector3(0.44, 0.36, 0.4), Vector3(0, 0.2, 0), 1.2, 0, 40.0, 30.0)
	_part("arm_l", "capsule", Vector3(0.1, 0.8, 0), Vector3(0, -0.42, 0), 0.9, 0, 85.0, 30.0)
	_part("arm_r", "capsule", Vector3(0.11, 0.9, 0), Vector3(0, -0.45, 0), 0.9, 0, 85.0, 30.0)
	_part("leg_l", "capsule", Vector3(0.13, 0.78, 0), Vector3(0, -0.38, 0), 1.2, 0, 55.0, 20.0)
	_part("leg_r", "capsule", Vector3(0.13, 0.78, 0), Vector3(0, -0.38, 0), 1.2, 0, 55.0, 20.0)


# ---------------------------------------------------------------------- ape
## A big silverback gorilla: huge chest, long arms it walks on, short legs.
func _build_ape(rng: RandomNumberGenerator) -> void:
	var tc := team_col
	var wild := team == "wild"
	var fur := Color("34302f").lerp(Color(rng.randf(), rng.randf(), rng.randf()), 0.04)
	var chest := Color("5d5354")
	var face := Color("5a4842")
	var silver := Color("a3a0a6")
	var hand := Color("3e3434")
	radius = 0.44
	height = 1.75
	top = 1.8
	reach_y = 1.0
	hold = "fists"
	var hips := _pivot("hips", self, Vector3(0, 0.55, 0))
	var torso := _pivot("torso", hips, Vector3.ZERO)
	var head := _pivot("head", torso, Vector3(0, 0.8, 0.2))
	var arm_l := _pivot("arm_l", torso, Vector3(0.47, 0.64, 0.06))
	var arm_r := _pivot("arm_r", torso, Vector3(-0.47, 0.64, 0.06))
	var leg_l := _pivot("leg_l", hips, Vector3(0.18, 0.0, -0.03))
	var leg_r := _pivot("leg_r", hips, Vector3(-0.18, 0.0, -0.03))
	# body: barrel chest, silver back, big shoulders
	_m(torso, B3Mats.sphere(0.5, 14), _c(fur, 0.95), Vector3(0, 0.42, 0), Vector3.ZERO, Vector3(1.0, 0.98, 0.78))
	_m(torso, B3Mats.sphere(0.36, 12), _c(chest, 0.9), Vector3(0, 0.4, 0.2), Vector3.ZERO, Vector3(1.0, 1.1, 0.55), false)
	_m(torso, B3Mats.sphere(0.42, 12), _c(silver, 0.95), Vector3(0, 0.48, -0.16), Vector3.ZERO, Vector3(1.0, 0.75, 0.55), false)
	_m(torso, B3Mats.sphere(0.34, 12), _c(fur, 0.95), Vector3(0, 0.06, -0.04))
	for sx in [-1.0, 1.0]:
		_m(torso, B3Mats.sphere(0.23, 10), _c(fur, 0.95), Vector3(0.38 * sx, 0.64, 0.04))
	# head: small skull with a crest, big brow, flat face and muzzle
	_m(head, B3Mats.sphere(0.24, 12), _c(fur, 0.95), Vector3(0, 0.1, 0))
	_m(head, B3Mats.sphere(0.15, 10), _c(fur, 0.95), Vector3(0, 0.3, -0.05), Vector3.ZERO, Vector3(0.7, 1.0, 1.1))
	_m(head, B3Mats.sphere(0.18, 12), _c(face, 0.8), Vector3(0, 0.05, 0.14), Vector3.ZERO, Vector3(1.15, 1.0, 0.75))
	_m(head, B3Mats.sphere(0.13, 10), _c(face, 0.8), Vector3(0, -0.05, 0.24), Vector3.ZERO, Vector3(1.35, 0.8, 0.85))
	_m(head, B3Mats.box(Vector3(0.36, 0.07, 0.11)), _c(fur), Vector3(0, 0.16, 0.2), Vector3(-10, 0, 0))
	for sx in [-1.0, 1.0]:
		_m(head, B3Mats.sphere(0.028, 6), _c(Color("1d1b22")), Vector3(0.045 * sx, 0.0, 0.345), Vector3.ZERO, Vector3.ONE, false)
		_m(head, B3Mats.sphere(0.06, 8), _c(face), Vector3(0.235 * sx, 0.08, 0.0), Vector3.ZERO, Vector3(0.6, 1.0, 1.0), false)
	_eye(head, Vector3(0.085, 0.09, 0.25), 0.035, true)
	_eye(head, Vector3(-0.085, 0.09, 0.25), 0.035, true)
	_m(head, B3Mats.box(Vector3(0.14, 0.02, 0.02)), _c(Color("2a1f1f")), Vector3(0, -0.11, 0.33), Vector3.ZERO, Vector3.ONE, false)
	# long arms with big knuckly fists
	for arm in [arm_l, arm_r]:
		var a: Node3D = arm
		_m(a, B3Mats.capsule(0.15, 0.9), _c(fur, 0.95), Vector3(0, -0.4, 0))
		_m(a, B3Mats.sphere(0.17, 10), _c(hand, 0.8), Vector3(0, -0.86, 0.02), Vector3.ZERO, Vector3(1.0, 0.9, 1.1))
		if not wild:
			_m(a, B3Mats.cyl(0.165, 0.165, 0.1, 12), _c(tc), Vector3(0, -0.68, 0), Vector3.ZERO, Vector3.ONE, false)
	for leg in [leg_l, leg_r]:
		var l: Node3D = leg
		_m(l, B3Mats.capsule(0.16, 0.52), _c(fur, 0.95), Vector3(0, -0.22, 0))
		_m(l, B3Mats.box(Vector3(0.22, 0.1, 0.32)), _c(hand), Vector3(0, -0.5, 0.06))
	if not wild:
		_m(head, B3Mats.cyl(0.245, 0.245, 0.07, 14), _c(tc), Vector3(0, 0.2, 0))
		_m(head, B3Mats.box(Vector3(0.04, 0.03, 0.22)), _c(tc), Vector3(0.05, 0.18, -0.3), Vector3(-30, 10, 0))
	# the rock it throws (shown only while throwing)
	held = Node3D.new()
	held.position = Vector3(0, 1.25, 0.25)
	held.visible = false
	torso.add_child(held)
	var rock := _c(Color("8a8580"), 0.95)
	_m(held, B3Mats.sphere(0.34, 8), rock, Vector3.ZERO, Vector3(20, 30, 0), Vector3(1.0, 0.8, 0.9))
	_m(held, B3Mats.sphere(0.22, 7), _c(Color("77726d"), 0.95), Vector3(0.18, 0.1, 0.05), Vector3.ZERO, Vector3.ONE, false)
	_part("torso", "box", Vector3(0.9, 0.9, 0.72), Vector3(0, 0.35, 0), 4.0, -1)
	_part("head", "sphere", Vector3(0.26, 0, 0), Vector3(0, 0.08, 0.05), 1.0, 0, 35.0, 25.0)
	_part("arm_l", "capsule", Vector3(0.17, 0.98, 0), Vector3(0, -0.45, 0), 0.9, 0, 85.0, 30.0)
	_part("arm_r", "capsule", Vector3(0.17, 0.98, 0), Vector3(0, -0.45, 0), 0.9, 0, 85.0, 30.0)
	_part("leg_l", "capsule", Vector3(0.16, 0.56, 0), Vector3(0, -0.25, 0), 0.9, 0, 55.0, 20.0)
	_part("leg_r", "capsule", Vector3(0.16, 0.56, 0), Vector3(0, -0.25, 0), 0.9, 0, 55.0, 20.0)


# ------------------------------------------------------------------- dragon
## A big flying dragon in its team's colour (wild ones are purple): bat
## wings, horns, a spiky back and a spade on its tail. Built at half size.
func _build_dragon() -> void:
	var tc := team_col
	var wild := team == "wild"
	var col := tc.darkened(0.38) if not wild else Color("6a3fb8")
	if team == "yellow":
		col = Color("d29a12")
	var belly := Color("f2d48a")
	var wing := tc.lightened(0.28) if not wild else Color("c2a0ff")
	if team == "yellow":
		wing = Color("ff9a3c")
	var horn := _c(Color("f6eedb"), 0.4)
	var skin := _c(col, 0.7)
	radius = 0.6
	height = 1.0
	top = 1.15
	reach_y = 0.45
	var b := _pivot("body", self, Vector3(0, 0.55, 0))
	_m(b, B3Mats.capsule(0.3, 1.2), skin, Vector3.ZERO, Vector3(90, 0, 0), Vector3(1.05, 0.95, 1.0))
	_m(b, B3Mats.capsule(0.24, 0.95), _c(belly, 0.8), Vector3(0, -0.09, 0.04), Vector3(90, 0, 0), Vector3(1.0, 0.9, 1.0), false)
	for i in 4:
		_m(b, B3Mats.box(Vector3(0.36, 0.02, 0.03)), _c(belly.darkened(0.2)), Vector3(0, -0.29, 0.3 - i * 0.18), Vector3.ZERO, Vector3.ONE, false)
	_m(b, B3Mats.sphere(0.3, 12), skin, Vector3(0, 0.03, 0.36))
	for i in 5:
		var s := 1.0 - absf(i - 1.5) * 0.18
		_m(b, B3Mats.prism(Vector3(0.05, 0.16 * s, 0.18 * s)), horn, Vector3(0, 0.3 + 0.06 * s, 0.38 - i * 0.19), Vector3(0, 90, 0), Vector3.ONE, false)
	# neck + head (the head pivot nods; the jaw opens for fire)
	var hp := _pivot("head", b, Vector3(0, 0.12, 0.52))
	_seg(hp, Vector3(0, -0.05, -0.05), Vector3(0, 0.36, 0.34), 0.17, 0.12, skin)
	var hn := Node3D.new()
	hn.position = Vector3(0, 0.42, 0.42)
	hp.add_child(hn)
	_m(hn, B3Mats.box(Vector3(0.3, 0.24, 0.34)), skin)
	_m(hn, B3Mats.box(Vector3(0.22, 0.15, 0.3)), skin, Vector3(0, -0.03, 0.28))
	_m(hn, B3Mats.box(Vector3(0.34, 0.06, 0.12)), _c(col.darkened(0.2)), Vector3(0, 0.13, 0.08), Vector3(-12, 0, 0), Vector3.ONE, false)
	for sx in [-1.0, 1.0]:
		_m(hn, B3Mats.sphere(0.025, 6), _c(Color("1d1b22")), Vector3(0.05 * sx, 0.04, 0.43), Vector3.ZERO, Vector3.ONE, false)
		_m(hn, B3Mats.cyl(0.0, 0.055, 0.36, 8), horn, Vector3(0.1 * sx, 0.2, -0.14), Vector3(-62, 0, 14 * sx))
		_m(hn, B3Mats.prism(Vector3(0.03, 0.2, 0.16)), _c(wing, 0.8), Vector3(0.16 * sx, 0.05, -0.12), Vector3(0, 90, -40 * sx), Vector3.ONE, false)
		_m(hn, B3Mats.cyl(0.0, 0.018, 0.07, 6), horn, Vector3(0.07 * sx, -0.12, 0.38), Vector3(180, 0, 0), Vector3.ONE, false)
	_eye(hn, Vector3(0.12, 0.07, 0.12), 0.04, true)
	_eye(hn, Vector3(-0.12, 0.07, 0.12), 0.04, true)
	var jaw := Node3D.new()
	jaw.position = Vector3(0, -0.1, 0.02)
	jaw.set_meta("pivot", true)
	hn.add_child(jaw)
	pv["jaw"] = jaw
	_m(jaw, B3Mats.box(Vector3(0.2, 0.07, 0.38)), _c(belly, 0.8), Vector3(0, -0.02, 0.2))
	muzzle = _marker(hn, Vector3(0, -0.08, 0.5))
	# bat wings: a bone along the front edge, membrane triangles behind it
	for sx in [1.0, -1.0]:
		var w := _pivot("wing_l" if sx > 0 else "wing_r", b, Vector3(0.22 * sx, 0.2, 0.12))
		var bone := _c(col.darkened(0.1), 0.7)
		_seg(w, Vector3(0, 0, 0), Vector3(1.0 * sx, 0.12, 0.05), 0.07, 0.05, bone)
		_seg(w, Vector3(1.0 * sx, 0.12, 0.05), Vector3(1.9 * sx, 0.05, -0.15), 0.05, 0.025, bone)
		_m(w, B3Mats.cyl(0.0, 0.035, 0.14, 6), horn, Vector3(1.0 * sx, 0.2, 0.06), Vector3.ZERO, Vector3.ONE, false)
		var mem := _c(wing, 0.8)
		var tris := [[0.5, 0.9, 0.82, 0.3], [1.15, 0.8, 0.95, 0.5], [1.65, 0.6, 0.62, 0.75]]
		for tri in tris:
			var cx: float = tri[0]
			var wd: float = tri[1]
			var dp: float = tri[2]
			var ltr: float = tri[3]
			_m(w, B3Mats.prism(Vector3(wd, dp, 0.025), ltr if sx > 0 else 1.0 - ltr), mem, Vector3(cx * sx, 0.06, -dp * 0.5 + 0.02), Vector3(-90, 0, 0))
		_m(w, B3Mats.box(Vector3(0.9, 0.025, 0.55)), mem, Vector3(0.75 * sx, 0.07, -0.3), Vector3(0, 6 * sx, 0))
	# legs tucked under
	for sx in [1.0, -1.0]:
		for fz in [0.32, -0.3]:
			var n: String = ("leg_f" if fz > 0 else "leg_b") + ("l" if sx > 0 else "r")
			var lp: Node3D
			if fz < 0.0:
				lp = _pivot(n, b, Vector3(0.18 * sx, -0.16, fz))
			else:
				# front legs aren't ragdoll parts: a plain node rides along with the body
				lp = Node3D.new()
				lp.position = Vector3(0.18 * sx, -0.16, fz)
				b.add_child(lp)
				pv[n] = lp
			_m(lp, B3Mats.capsule(0.075, 0.36), skin, Vector3(0, -0.14, 0))
			for c in 3:
				_m(lp, B3Mats.cyl(0.0, 0.02, 0.08, 5), horn, Vector3((c - 1) * 0.035, -0.32, 0.05), Vector3(80, 0, 0), Vector3.ONE, false)
	# long tail with spikes and a team-coloured spade
	var tp := _pivot("tail", b, Vector3(0, 0.02, -0.55))
	tp.rotation.x = 0.12
	_m(tp, B3Mats.cyl(0.04, 0.2, 1.5, 10), skin, Vector3(0, 0, -0.75), Vector3(-90, 0, 0))
	for i in 3:
		_m(tp, B3Mats.prism(Vector3(0.04, 0.12, 0.13)), horn, Vector3(0, 0.15 - i * 0.03, -0.25 - i * 0.38), Vector3(0, 90, 0), Vector3.ONE, false)
	_m(tp, B3Mats.prism(Vector3(0.34, 0.34, 0.05)), _c(wing, 0.7), Vector3(0, 0, -1.62), Vector3(-90, 0, 0))
	_part("body", "capsule", Vector3(0.32, 1.3, 0), Vector3.ZERO, 3.0, -1, 60.0, 20.0, "z")
	_part("head", "sphere", Vector3(0.22, 0, 0), Vector3(0, 0.4, 0.45), 0.8, 0, 40.0, 25.0)
	_part("wing_l", "box", Vector3(1.9, 0.06, 0.8), Vector3(0.95, 0.05, -0.3), 0.6, 0, 70.0, 30.0)
	_part("wing_r", "box", Vector3(1.9, 0.06, 0.8), Vector3(-0.95, 0.05, -0.3), 0.6, 0, 70.0, 30.0)
	_part("tail", "capsule", Vector3(0.12, 1.5, 0), Vector3(0, 0, -0.75), 0.8, 0, 45.0, 15.0, "z")
	_part("leg_bl", "capsule", Vector3(0.08, 0.4, 0), Vector3(0, -0.15, 0), 0.3, 0, 45.0, 15.0)
	_part("leg_br", "capsule", Vector3(0.08, 0.4, 0), Vector3(0, -0.15, 0), 0.3, 0, 45.0, 15.0)


# ---------------------------------------------------------------- animation
## spd: ground speed (m/s). act: current action, k: its progress 0..1.
func animate(dt: float, spd: float, act: String, k: float, aiming: bool, mood: String) -> void:
	t += dt
	recoil = maxf(0.0, recoil - dt * 6.0)
	if _flash > 0.0:
		_flash -= dt
		if _flash <= 0.0:
			for m in meshes:
				m.material_overlay = null
			_flash_rest = 0.22     # a short gap, so things hit nonstop don't stay white
	elif _flash_rest > 0.0:
		_flash_rest -= dt
	match body:
		"human", "robot":
			_anim_human(dt, spd, act, k, aiming, mood)
		"rider":
			_anim_rider(dt, spd, act, k, mood)
		"ape":
			_anim_ape(dt, spd, act, k, mood)
		"quad":
			_anim_quad(dt, spd, act, k, mood)
		"biped":
			_anim_biped(dt, spd, act, k, mood)
		"bird":
			_anim_bird(dt, spd, act, k, mood)
		"dragon":
			_anim_dragon(dt, spd, act, k, mood)


func flash() -> void:
	if _flash > 0.0 or _flash_rest > 0.0:
		return
	var f := B3Mats.white_flash()
	for m in meshes:
		m.material_overlay = f
	_flash = 0.09


func _p(n: String) -> Node3D:
	return pv.get(n)


func _anim_human(dt: float, spd: float, act: String, k: float, aiming: bool, mood: String) -> void:
	var hips: Node3D = pv.hips
	var torso: Node3D = pv.torso
	var head: Node3D = pv.head
	var al: Node3D = pv.arm_l
	var ar: Node3D = pv.arm_r
	var ll: Node3D = pv.leg_l
	var lr_: Node3D = pv.leg_r
	var run := clampf(spd / 3.5, 0.0, 1.4)
	phase += dt * spd * 2.6 / size
	var s := sin(phase)
	var swing := 0.8 * minf(run, 1.0)
	ll.rotation = Vector3(s * swing, 0, 0)
	lr_.rotation = Vector3(-s * swing, 0, 0)
	var breathe := sin(t * 2.2) * 0.012
	hips.position.y = 0.78 + absf(cos(phase)) * 0.06 * minf(run, 1.0) + breathe
	torso.rotation = Vector3(0.12 * minf(run, 1.0), 0, 0)
	head.rotation = Vector3(0, sin(t * 0.7) * 0.15 * (1.0 - minf(run, 1.0)), 0)
	var arm_out := 0.12 + sin(t * 2.2) * 0.02
	al.rotation = Vector3(-s * swing * 0.85, 0, arm_out)
	ar.rotation = Vector3(s * swing * 0.85, 0, -arm_out)
	if held:
		held.visible = true
	match mood:
		"cheer":
			var j := sin(t * 9.0)
			al.rotation = Vector3(-2.9, 0, 0.35 + j * 0.15)
			ar.rotation = Vector3(-2.9, 0, -0.35 - j * 0.15)
			return
		"cower":
			hips.position.y = 0.45
			ll.rotation = Vector3(-1.3, 0, 0.1)
			lr_.rotation = Vector3(-1.3, 0, -0.1)
			torso.rotation = Vector3(0.5 + sin(t * 30.0) * 0.04, 0, 0)
			al.rotation = Vector3(-2.6, -0.5, 0.2)
			ar.rotation = Vector3(-2.6, 0.5, -0.2)
			return
		"flail":
			al.rotation = Vector3(-2.2 + sin(t * 18.0) * 0.9, 0, 0.5)
			ar.rotation = Vector3(-2.2 + cos(t * 17.0) * 0.9, 0, -0.5)
			return
	match hold:
		"gun":
			if musket_hand:
				musket_hand.rotation.x = PI * 0.5
			if act == "attack":
				# a stab with the bayonet (or a shove with the gun)
				var jab := sin(clampf(k, 0.0, 1.0) * PI)
				ar.rotation = Vector3(-1.35 + 0.15 * jab, 0, 0)
				al.rotation = Vector3(-1.25 + 0.1 * jab, -0.55, 0)
				torso.rotation.x += 0.4 * jab
			elif aiming or act == "shoot" or act == "aim":
				ar.rotation = Vector3(-1.5 + recoil * 0.5, 0, 0)
				al.rotation = Vector3(-1.4 + recoil * 0.4, -0.55, 0)
				torso.rotation.x -= recoil * 0.15
			elif musket_hand:
				# a long musket stands upright at the shoulder
				ar.rotation = Vector3(-0.2 + s * swing * 0.12, 0, -0.06)
				musket_hand.rotation.x = -1.68 - ar.rotation.x - torso.rotation.x
			else:
				ar.rotation = Vector3(-0.75 + s * swing * 0.15, 0.25, 0)
				al.rotation = Vector3(-0.95 + s * swing * 0.15, -0.6, 0)
		"melee":
			ar.rotation.x = minf(ar.rotation.x, -0.3)
			if thrust:
				var a2 := -0.45 + s * swing * 0.1 - 0.9 * _thrust_k(act, k)
				ar.rotation = Vector3(a2, 0.0, -0.1)
				torso.rotation.y = -0.25 * _thrust_k(act, k)
				if spear_hand:
					spear_hand.rotation.x = -(a2 + torso.rotation.x) + 0.08
			elif act == "attack":
				var a := 0.0
				if k < 0.4:
					a = lerpf(-0.3, -2.7, k / 0.4)
				elif k < 0.6:
					a = lerpf(-2.7, -0.2, (k - 0.4) / 0.2)
				else:
					a = lerpf(-0.2, -0.3, (k - 0.6) / 0.4)
				ar.rotation = Vector3(a, 0.2, -0.2)
				torso.rotation.y = lerpf(0.3, -0.35, smoothstep(0.35, 0.6, k))
			if shield:
				al.rotation = Vector3(-0.9, -0.5, 0.2)
		"slam":
			var a := -0.6
			if act == "attack":
				if k < 0.5:
					a = lerpf(-0.6, -3.0, k / 0.5)
				elif k < 0.65:
					a = lerpf(-3.0, -0.7, (k - 0.5) / 0.15)
				else:
					a = -0.7
				torso.rotation.x = lerpf(-0.25, 0.4, smoothstep(0.45, 0.65, k))
			ar.rotation = Vector3(a, 0.3, -0.1)
			al.rotation = Vector3(a, -0.3, 0.1)
		"bow":
			if not (aiming or act == "bow"):
				al.rotation = Vector3(-0.5 - s * swing * 0.4, 0, 0.1)
			if aiming or act == "bow":
				al.rotation = Vector3(-1.55, 0, 0)
				var draw := 0.0
				if act == "bow":
					draw = smoothstep(0.0, 0.8, k)
				ar.rotation = Vector3(-1.55, -0.3 - draw * 0.9, 0)
		"throw":
			if act == "throw":
				var a := 0.0
				if k < 0.45:
					a = lerpf(0.0, 1.0, k / 0.45)
				elif k < 0.7:
					a = lerpf(1.0, -2.6, (k - 0.45) / 0.25)
				else:
					a = lerpf(-2.6, -1.2, (k - 0.7) / 0.3)
				ar.rotation = Vector3(a, 0, -0.15)
				if held:
					held.visible = k < 0.62
		"fists":
			if act == "attack":
				var side := ar if punch_side == 0 else al
				var a := -1.55 * sin(clampf(k, 0.0, 1.0) * PI)
				side.rotation = Vector3(a, 0.0, 0.0)
				torso.rotation.y = (0.3 if punch_side == 0 else -0.3) * sin(k * PI)
		"staff":
			# the staff stays upright; casting raises it and points the orb forward
			var lift := 0.0
			if act == "cast":
				lift = smoothstep(0.0, 0.45, k)
				if k > 0.8:
					lift += (k - 0.8) * 2.0
			elif aiming or act == "aim":
				lift = 0.35
			ar.rotation = Vector3(-0.35 - 1.25 * lift + s * swing * 0.15 * (1.0 - lift), 0.0, -0.12)
			if lift > 0.0:
				al.rotation = Vector3(-0.3 - 1.1 * lift, -0.35 * lift, 0.15)
			if staff:
				staff.rotation.x = -(ar.rotation.x + torso.rotation.x) + 0.75 * lift
	if act == "heal":
		al.rotation = Vector3(-1.1, -0.3, 0)
		ar.rotation = Vector3(-1.1, 0.3, 0)


## How far a spear or lance stab is pushed out (0 held, 1 at full reach).
func _thrust_k(act: String, k: float) -> float:
	if act != "attack":
		return 0.0
	if k < 0.35:
		return -0.25 * k / 0.35
	if k < 0.55:
		return lerpf(-0.25, 1.0, (k - 0.35) / 0.2)
	return lerpf(1.0, 0.0, clampf((k - 0.55) / 0.45, 0.0, 1.0))


func _anim_rider(dt: float, spd: float, act: String, k: float, mood: String) -> void:
	var hb: Node3D = pv.horse
	var hp: Node3D = pv.hhead
	var tl: Node3D = pv.htail
	var hips: Node3D = pv.hips
	var torso: Node3D = pv.torso
	var head: Node3D = pv.head
	var al: Node3D = pv.arm_l
	var ar: Node3D = pv.arm_r
	var ll: Node3D = pv.leg_l
	var lr_: Node3D = pv.leg_r
	var r1 := clampf(spd / 4.0, 0.0, 1.0)
	phase += dt * spd * 1.7
	var s := sin(phase)
	# the horse gallops (front legs, then back legs) and its body rocks
	var amp := 0.75 * r1
	(pv.hleg_fl as Node3D).rotation.x = s * amp
	(pv.hleg_fr as Node3D).rotation.x = sin(phase + 0.6) * amp
	(pv.hleg_bl as Node3D).rotation.x = sin(phase + PI) * amp
	(pv.hleg_br as Node3D).rotation.x = sin(phase + PI + 0.6) * amp
	var hbase: Vector3 = _base_y.horse
	hb.position = hbase + Vector3(0, absf(s) * 0.1 * r1 + sin(t * 2.0) * 0.008, 0)
	hb.rotation = Vector3(cos(phase) * 0.07 * r1, 0, 0)
	hp.rotation = Vector3(-cos(phase) * 0.16 * r1 + sin(t * 1.1) * 0.05 + (0.25 if act == "charge" else 0.0), sin(t * 0.5) * 0.2 * (1.0 - r1), 0)
	tl.rotation = Vector3(0.35 * r1 + sin(t * 3.0) * 0.1, sin(t * 2.3) * 0.25, 0)
	# the rider bounces in the saddle and leans into the gallop
	var base: Vector3 = _base_y.hips
	hips.position = base + Vector3(0, absf(cos(phase)) * 0.05 * r1, 0)
	torso.rotation = Vector3(0.08 + 0.22 * r1, 0, 0)
	head.rotation = Vector3(-0.15 * r1, sin(t * 0.7) * 0.15 * (1.0 - r1), 0)
	ll.rotation = Vector3(-0.6, 0, 0.42)
	lr_.rotation = Vector3(-0.6, 0, -0.42)
	al.rotation = Vector3(-0.75, 0, 0.12)
	ar.rotation = Vector3(-0.75, 0, -0.12)
	match mood:
		"cheer":
			var j := sin(t * 9.0)
			al.rotation = Vector3(-2.9, 0, 0.35 + j * 0.15)
			ar.rotation = Vector3(-2.9, 0, -0.35 - j * 0.15)
			hb.rotation.x = -0.3 - absf(j) * 0.1     # the horse rears up
			return
		"flail", "cower":
			al.rotation = Vector3(-2.2 + sin(t * 18.0) * 0.9, 0, 0.5)
			ar.rotation = Vector3(-2.2 + cos(t * 17.0) * 0.9, 0, -0.5)
			return
	if thrust:
		# a lance held level under the arm; it shoves forward on a hit
		var a := -0.3 - 0.8 * _thrust_k(act, k)
		ar.rotation = Vector3(a, 0.0, -0.08)
		if spear_hand:
			spear_hand.rotation.x = -(a + torso.rotation.x + hb.rotation.x) + 0.06
	else:
		var a3 := -0.7
		if act == "charge":
			a3 = -1.75      # sabre pointed at the enemy
		elif act == "attack":
			if k < 0.4:
				a3 = lerpf(-0.7, -2.8, k / 0.4)
			elif k < 0.6:
				a3 = lerpf(-2.8, -0.3, (k - 0.4) / 0.2)
			else:
				a3 = lerpf(-0.3, -0.7, (k - 0.6) / 0.4)
			torso.rotation.y = lerpf(0.3, -0.35, smoothstep(0.35, 0.6, k))
		ar.rotation = Vector3(a3, 0.15, -0.15)
	if shield:
		al.rotation = Vector3(-0.75, -0.45, 0.2)


func _anim_quad(dt: float, spd: float, act: String, k: float, mood: String) -> void:
	var b: Node3D = pv.body
	var hp: Node3D = pv.head
	var tl: Node3D = pv.tail
	var q: Dictionary = QUAD[style]
	var leg: float = q.leg
	var run := clampf(spd / 3.0, 0.0, 1.5)
	phase += dt * spd * 3.2 / (leg * 2.0 + 0.4)
	var s := sin(phase)
	var amp := 0.55 * minf(run, 1.0)
	(pv.leg_fl as Node3D).rotation.x = s * amp
	(pv.leg_br as Node3D).rotation.x = s * amp
	(pv.leg_fr as Node3D).rotation.x = -s * amp
	(pv.leg_bl as Node3D).rotation.x = -s * amp
	var base: Vector3 = _base_y.body
	b.position = base + Vector3(0, absf(cos(phase)) * 0.05 * leg * minf(run, 1.0) + sin(t * 2.0) * 0.01, 0)
	b.rotation = Vector3.ZERO
	hp.rotation = Vector3(sin(phase * 2.0) * 0.05 * run + sin(t * 1.3) * 0.04, sin(t * 0.6) * 0.15 * (1.0 - minf(run, 1.0)), 0)
	var hb: Vector3 = _base_y.head
	hp.position = hb
	var wag := 3.0 if style == "dog" else 1.5
	tl.rotation.y = sin(t * wag * (2.0 if style == "dog" else 1.0)) * (0.5 if style == "dog" else 0.2)
	var jaw: Node3D = pv.get("jaw")
	if jaw:
		jaw.rotation.x = 0.0
	if mood == "cheer":
		hp.rotation.x = -0.4 + sin(t * 8.0) * 0.15
		if jaw:
			jaw.rotation.x = 0.4
	match act:
		"attack":
			var w := sin(clampf(k, 0.0, 1.0) * PI)
			match style:
				"elephant", "brachio":
					b.rotation.x = -0.35 * w if k < 0.6 else lerpf(-0.35, 0.05, (k - 0.6) / 0.4)
					hp.rotation.x -= 0.5 * w
					if jaw:
						jaw.rotation.x = 0.5 * w
				"stego":
					tl.rotation.y = sin(k * TAU) * 1.3
					b.rotation.y = -sin(k * TAU) * 0.25
				_:
					hp.position = hb + Vector3(0, -0.05, 0.25 * w * leg)
					hp.rotation.x += 0.35 * w
					if jaw:
						jaw.rotation.x = 0.55 * (1.0 - absf(k * 2.0 - 1.0))
		"charge":
			hp.rotation.x += 0.35
		"roar":
			hp.rotation.x -= 0.5
			if jaw:
				jaw.rotation.x = 0.6


func _anim_biped(dt: float, spd: float, act: String, k: float, mood: String) -> void:
	var b: Node3D = pv.body
	var hp: Node3D = pv.head
	var tl: Node3D = pv.tail
	var q: Dictionary = BIPED[style]
	var leg: float = q.leg
	var run := clampf(spd / 3.0, 0.0, 1.5)
	phase += dt * spd * 3.0 / (leg * 1.6 + 0.3)
	var s := sin(phase)
	var amp := 0.6 * minf(run, 1.0)
	(pv.leg_l as Node3D).rotation.x = s * amp
	(pv.leg_r as Node3D).rotation.x = -s * amp
	var base: Vector3 = _base_y.body
	b.position = base + Vector3(0, absf(cos(phase)) * 0.06 * leg * minf(run, 1.0) + sin(t * 1.8) * 0.015 * leg, 0)
	b.rotation = Vector3(-0.18 + 0.12 * minf(run, 1.0), sin(phase) * 0.05 * run, 0)
	tl.rotation = Vector3(0.12 + sin(t * 1.4) * 0.05, sin(t * 1.6 + phase * 0.5) * 0.25, 0)
	hp.rotation = Vector3(0.18 + sin(t * 1.2) * 0.05, sin(t * 0.5) * 0.2 * (1.0 - minf(run, 1.0)), 0)
	var hb: Vector3 = _base_y.head
	hp.position = hb
	var jaw: Node3D = pv.jaw
	jaw.rotation.x = 0.05 + sin(t * 0.9) * 0.03
	if mood == "cheer":
		hp.rotation.x = -0.5
		jaw.rotation.x = 0.7
	match act:
		"attack":
			var w := sin(clampf(k, 0.0, 1.0) * PI)
			hp.position = hb + Vector3(0, -0.2 * w * leg * 0.3, 0.4 * w * leg * 0.4)
			hp.rotation.x = 0.18 + 0.45 * w
			b.rotation.x += 0.15 * w
			jaw.rotation.x = 0.75 * clampf(1.0 - absf(k * 2.2 - 0.9), 0.0, 1.0)
		"roar":
			var w := sin(clampf(k, 0.0, 1.0) * PI)
			hp.rotation.x = 0.18 - 0.7 * w
			jaw.rotation.x = 0.85 * w
			b.rotation.x -= 0.12 * w
			hp.rotation.y = sin(t * 30.0) * 0.04 * w
		"pounce":
			(pv.leg_l as Node3D).rotation.x = 0.9
			(pv.leg_r as Node3D).rotation.x = 0.7
			jaw.rotation.x = 0.6


func _anim_bird(dt: float, spd: float, act: String, k: float, mood: String) -> void:
	var b: Node3D = pv.body
	var hp: Node3D = pv.head
	var run := clampf(spd / 2.5, 0.0, 1.5)
	if style == "ptero":
		var flap_speed := 7.0 if act != "swoop" else 2.0
		wing_flap += dt * flap_speed
		var f := sin(wing_flap)
		var fold := 0.0 if act != "swoop" else 0.6
		(pv.wing_l as Node3D).rotation = Vector3(0, -fold, f * 0.55)
		(pv.wing_r as Node3D).rotation = Vector3(0, fold, -f * 0.55)
		var base: Vector3 = _base_y.body
		b.position = base + Vector3(0, -f * 0.08, 0)
		b.rotation.x = 0.3 if act == "swoop" else -0.05
		hp.rotation.x = sin(t * 1.5) * 0.1 + (0.4 if act == "attack" else 0.0)
		for n in ["leg_l", "leg_r"]:
			(pv[n] as Node3D).rotation.x = 0.8 + sin(t * 2.0) * 0.1
		return
	phase += dt * spd * 7.0
	var s := sin(phase)
	(pv.leg_l as Node3D).rotation.x = s * 0.8 * minf(run, 1.0)
	(pv.leg_r as Node3D).rotation.x = -s * 0.8 * minf(run, 1.0)
	var base2: Vector3 = _base_y.body
	b.position = base2 + Vector3(0, absf(cos(phase)) * 0.04 * minf(run, 1.0), 0)
	var peck := 0.0
	if act == "attack":
		peck = sin(clampf(k, 0.0, 1.0) * PI)
	elif spd < 0.3:
		peck = maxf(0.0, sin(t * 2.3) * 3.0 - 2.4)
	var hb: Vector3 = _base_y.head
	hp.position = hb + Vector3(0, -0.12 * peck, 0.1 * peck + sin(phase * 2.0) * 0.03 * run)
	hp.rotation.x = 0.8 * peck
	var flap := 0.0
	if run > 0.9 or mood == "flail" or mood == "cheer":
		flap = absf(sin(t * 22.0)) * 0.9
	(pv.wing_l as Node3D).rotation.z = flap
	(pv.wing_r as Node3D).rotation.z = -flap


func _anim_ape(dt: float, spd: float, act: String, k: float, mood: String) -> void:
	var hips: Node3D = pv.hips
	var torso: Node3D = pv.torso
	var head: Node3D = pv.head
	var al: Node3D = pv.arm_l
	var ar: Node3D = pv.arm_r
	var ll: Node3D = pv.leg_l
	var lr_: Node3D = pv.leg_r
	var run := clampf(spd / 4.0, 0.0, 1.4)
	var r1 := minf(run, 1.0)
	phase += dt * spd * 2.1
	var s := sin(phase)
	# knuckle-walk: arms and legs swing like a four-legged gallop
	ll.rotation = Vector3(s * 0.75 * r1, 0, 0)
	lr_.rotation = Vector3(-s * 0.75 * r1, 0, 0)
	al.rotation = Vector3(-0.42 + s * 0.65 * r1, 0, 0.12)
	ar.rotation = Vector3(-0.42 - s * 0.65 * r1, 0, -0.12)
	var lean := 0.42 + 0.22 * r1
	hips.position.y = 0.55 + absf(cos(phase)) * 0.07 * r1 + sin(t * 2.0) * 0.012
	torso.rotation = Vector3(lean, sin(phase) * 0.06 * r1, 0)
	head.rotation = Vector3(-lean * 0.75 + sin(t * 1.1) * 0.05, sin(t * 0.6) * 0.25 * (1.0 - r1), 0)
	if held:
		held.visible = false
	match mood:
		"cheer":
			_chest_beat(torso, head, al, ar)
			return
		"cower":
			hips.position.y = 0.42
			torso.rotation = Vector3(0.9, 0, 0)
			al.rotation = Vector3(-2.4, -0.4, 0.3)
			ar.rotation = Vector3(-2.4, 0.4, -0.3)
			return
		"flail":
			al.rotation = Vector3(-2.6 + sin(t * 17.0) * 0.8, 0, 0.6)
			ar.rotation = Vector3(-2.6 + cos(t * 16.0) * 0.8, 0, -0.6)
			torso.rotation.x = 0.1
			return
	match act:
		"attack":
			var side := ar if punch_side == 0 else al
			side.rotation = Vector3(-0.42 - 1.35 * sin(clampf(k, 0.0, 1.0) * PI), 0, 0.0)
			torso.rotation.y = (0.35 if punch_side == 0 else -0.35) * sin(k * PI)
			torso.rotation.x = lean - 0.15 * sin(k * PI)
		"pound":
			var a := -0.42
			var tx := lean
			if k < 0.45:
				var f := smoothstep(0.0, 0.45, k)
				a = lerpf(-0.42, -3.0, f)
				tx = lerpf(lean, -0.15, f)
			elif k < 0.6:
				var f2 := (k - 0.45) / 0.15
				a = lerpf(-3.0, -0.35, f2)
				tx = lerpf(-0.15, 0.95, f2)
			else:
				a = -0.35
				tx = lerpf(0.95, lean, smoothstep(0.75, 1.0, k))
			al.rotation = Vector3(a, 0, 0.18)
			ar.rotation = Vector3(a, 0, -0.18)
			torso.rotation.x = tx
			head.rotation.x = -tx * 0.6
		"hurl":
			var a2 := -0.42
			var tx2 := lean
			if k < 0.28:
				a2 = lerpf(-0.42, -0.25, k / 0.28)
				tx2 = lerpf(lean, 1.0, k / 0.28)
			elif k < 0.55:
				var f3 := smoothstep(0.28, 0.55, k)
				a2 = lerpf(-0.25, -3.0, f3)
				tx2 = lerpf(1.0, -0.2, f3)
			elif k < 0.68:
				var f4 := (k - 0.55) / 0.13
				a2 = lerpf(-3.0, -1.1, f4)
				tx2 = lerpf(-0.2, 0.55, f4)
			else:
				a2 = -1.1
				tx2 = 0.55
			al.rotation = Vector3(a2, 0, 0.1)
			ar.rotation = Vector3(a2, 0, -0.1)
			torso.rotation.x = tx2
			head.rotation.x = -tx2 * 0.6
			if held:
				held.visible = k > 0.25 and k < 0.62
		"beat":
			_chest_beat(torso, head, al, ar)


func _chest_beat(torso: Node3D, head: Node3D, al: Node3D, ar: Node3D) -> void:
	torso.rotation = Vector3(-0.08, 0, 0)
	head.rotation = Vector3(-0.35, 0, 0)
	var j := sin(t * 24.0)
	al.rotation = Vector3(-1.15, 0, -0.75 + j * 0.35)
	ar.rotation = Vector3(-1.15, 0, 0.75 + j * 0.35)


func _anim_dragon(dt: float, _spd: float, act: String, k: float, mood: String) -> void:
	var b: Node3D = pv.body
	var hp: Node3D = pv.head
	var tl: Node3D = pv.tail
	var jaw: Node3D = pv.jaw
	var breath := act == "breath"
	wing_flap += dt * (2.6 if breath else 4.4)
	var f := sin(wing_flap)
	(pv.wing_l as Node3D).rotation = Vector3(0, 0, f * 0.62 + 0.08)
	(pv.wing_r as Node3D).rotation = Vector3(0, 0, -f * 0.62 - 0.08)
	var base: Vector3 = _base_y.body
	b.position = base + Vector3(0, -f * 0.06, 0)
	b.rotation = Vector3(-0.06 + (0.25 if act == "swoop" else 0.0), 0, 0)
	tl.rotation = Vector3(0.12 + sin(t * 1.7) * 0.1, sin(t * 1.3) * 0.3, 0)
	hp.rotation = Vector3(sin(t * 1.4) * 0.08, sin(t * 0.7) * 0.12, 0)
	jaw.rotation.x = 0.05 + sin(t * 1.1) * 0.04
	var legs := ["leg_fl", "leg_fr", "leg_bl", "leg_br"]
	for i in legs.size():
		# each leg sways a little out of step with the others
		(pv[legs[i]] as Node3D).rotation.x = 0.7 + sin(t * 2.0 + i * 1.7) * 0.08
	if breath:
		var w := smoothstep(0.0, 0.15, k) * (1.0 - smoothstep(0.9, 1.0, k))
		hp.rotation.x = 0.4 * w + sin(t * 40.0) * 0.02
		jaw.rotation.x = 0.05 + 0.6 * w
		b.rotation.x -= 0.15 * w
	elif act == "attack":
		var w2 := sin(clampf(k, 0.0, 1.0) * PI)
		jaw.rotation.x = 0.6 * w2
		hp.rotation.x = 0.5 * w2
		for n in ["leg_fl", "leg_fr"]:
			(pv[n] as Node3D).rotation.x = 0.7 - 1.4 * w2
	elif act == "roar" or mood == "cheer":
		hp.rotation.x = -0.45
		jaw.rotation.x = 0.65
