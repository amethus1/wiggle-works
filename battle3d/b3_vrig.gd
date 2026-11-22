class_name B3VRig
extends B3Rig
## Vehicle models (tank, jeep, cannon, MG turret, race car, helicopter and
## fighter plane) built from primitives in the same chunky toy style as the
## fighters, painted in the team colour (wild ones are army green). Forward
## is +Z, the origin is on the ground (for aircraft: under the landing gear).
##   turret: turns left/right, gun: tilts up/down, wheels: roll.
##   rotors: spin (helicopter rotors, propellers); blurs: their motion discs.
##   eye: where the first-person camera sits (driver seat, hatch, cockpit).
##     Meshes with the meta "fp_keep" (or under a node with it) stay visible
##     in first person: bonnets, gun barrels, cockpit frames, propellers.
##   shapes: the collision shapes for the vehicle body (B3Vehicle).
##   wreck: the pieces it breaks into when destroyed (break_apart()).

const OLIVE := Color("6f7a3c")
const RUBBER := Color("2c2d31")
const SAND := Color("c9b27c")
const GLASS := Color(0.75, 0.92, 1.0, 0.35)
const BLUR := Color(0.16, 0.16, 0.18, 0.2)
const CREAM := Color("f4f1ea")
const VGOLD := Color("ffcf4a")

var turret: Node3D = null
var gun: Node3D = null
var mg_muzzle: Node3D = null
var eye: Node3D = null              # first-person camera seat
var wheels: Array[Node3D] = []
var steer: Array[Node3D] = []
var cleats: Array = []          # [node, base_z, dir] tank tread cleats
var shapes: Array = []          # [{shape, xf}]
var wreck: Array = []           # [{node, size, offset, mass, up, main}]
var crew: Array[Node3D] = []
var _crew_y := PackedFloat32Array()     # where each crew member sits (cheering bobs about it)
var rotors: Array = []          # [node, axis (0 x, 1 y, 2 z), turns per second at full speed]
var blurs: Array[Node3D] = []   # see-through discs shown while rotors spin fast
var gun_muzzles: Array[Node3D] = []     # plane wing guns
var rocket_muzzles: Array[Node3D] = []  # helicopter rocket pods
var bomb_node: Node3D = null    # the plane's bomb (hidden while reloading)
var gear: Node3D = null         # the plane's landing gear (only when parked)
var wheel_r := 0.4
var drive_speed := 0.0          # signed ground speed, set by B3Vehicle
var rotor_speed := 0.0          # 0..1, set by B3Aircraft
var steer_angle := 0.0          # front wheels, radians
var no_flash := false           # someone's looking out of it: no white hit flash
var _roll := 0.0
var _spin := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]


func build(unit_kind: String, team_id: String, _rng: RandomNumberGenerator) -> void:
	kind = unit_kind
	team = team_id
	var def := B3Defs.unit_def(kind)
	body = "vehicle"
	style = String(def.style)
	size = 1.0
	team_col = B3Defs.team_col(team)
	match style:
		"tank":
			_build_tank()
		"jeep":
			_build_jeep()
		"cannon":
			_build_cannon()
		"car":
			_build_car()
		"heli":
			_build_heli()
		"plane":
			_build_plane()
		_:
			_build_nest()
	for k in pv:
		var p: Node3D = pv[k]
		_base_y[k] = p.position


# ------------------------------------------------------------------ helpers
func _paint() -> Color:
	return OLIVE if team == "wild" else team_col.darkened(0.12)


## The bright team stripe colour (wild: olive).
func _light() -> Color:
	return team_col.lightened(0.25) if team != "wild" else OLIVE.lightened(0.2)


func _piece(n: Node3D, sz: Vector3, off: Vector3, m: float, up := 4.0, main := false) -> void:
	wreck.append({"node": n, "size": sz, "offset": off, "mass": m, "up": up, "main": main})


func _shape_box(sz: Vector3, pos: Vector3) -> void:
	var b := BoxShape3D.new()
	b.size = sz
	shapes.append({"shape": b, "xf": Transform3D(Basis.IDENTITY, pos)})


## A capsule lying along z (axis "z") or x (axis "x").
func _shape_cap(r: float, h: float, pos: Vector3, axis := "z") -> void:
	var c := CapsuleShape3D.new()
	c.radius = r
	c.height = h
	var bs := Basis(Vector3.RIGHT, PI * 0.5) if axis == "z" else Basis(Vector3.BACK, PI * 0.5)
	shapes.append({"shape": c, "xf": Transform3D(bs, pos)})


func _node(n: String, parent: Node3D, pos: Vector3) -> Node3D:
	var p := Node3D.new()
	p.name = n
	p.position = pos
	parent.add_child(p)
	return p


## Marks `n` to stay visible in the first-person view.
func _k(n: Node3D) -> Node3D:
	n.set_meta("fp_keep", true)
	return n


## A see-through spinning disc (rotors, propellers): `axis` is the spin axis.
func _blur(parent: Node3D, pos: Vector3, r: float, axis := "y") -> MeshInstance3D:
	var rot := Vector3.ZERO
	if axis == "x":
		rot = Vector3(0, 0, 90)
	elif axis == "z":
		rot = Vector3(90, 0, 0)
	var mi := _m(parent, B3Mats.cyl(r, r, 0.02, 32), B3Mats.flat(BLUR), pos, rot, Vector3.ONE, false)
	mi.visible = false
	blurs.append(mi)
	return mi


## A little crew member (driver, gunner, pilot): team shirt, hat, eyes.
## hat: "army" (round helmet), "race" (white crash helmet with a team
## stripe) or "pilot" (leather cap and goggles).
func _person(parent: Node3D, pos: Vector3, arms_fwd := true, hat := "army") -> Node3D:
	var p := _node("Crew", parent, pos)
	var shirt := team_col if team != "wild" else Color("8a7a52")
	var skin := Color("eab68e")
	_m(p, B3Mats.box(Vector3(0.36, 0.42, 0.24)), _c(shirt), Vector3(0, 0.21, 0))
	_m(p, B3Mats.sphere(0.17, 12), _c(skin, 0.6), Vector3(0, 0.6, 0))
	match hat:
		"race":
			_m(p, B3Mats.hemi(0.205), _c(CREAM, 0.35), Vector3(0, 0.6, -0.015))
			_m(p, B3Mats.box(Vector3(0.07, 0.03, 0.41)), _c(_light()), Vector3(0, 0.805, -0.015), Vector3.ZERO, Vector3.ONE, false)
			_m(p, B3Mats.box(Vector3(0.3, 0.05, 0.06)), _c(Color("1d1e22"), 0.2), Vector3(0, 0.7, 0.16), Vector3.ZERO, Vector3.ONE, false)
		"pilot":
			_m(p, B3Mats.hemi(0.185), _c(Color("7a4a2a"), 0.8), Vector3(0, 0.61, -0.01))
			for sx: float in [-1.0, 1.0]:
				_m(p, B3Mats.sphere(0.05, 8), B3Mats.mat(Color("bfe6ff"), 0.1), Vector3(0.07 * sx, 0.73, 0.13), Vector3.ZERO, Vector3.ONE, false)
			_m(p, B3Mats.box(Vector3(0.34, 0.03, 0.03)), _c(Color("4a2e1c")), Vector3(0, 0.73, 0.12), Vector3.ZERO, Vector3.ONE, false)
			_m(p, B3Mats.box(Vector3(0.2, 0.1, 0.05)), _c(CREAM), Vector3(0, 0.42, 0.12), Vector3(-10, 0, 0), Vector3.ONE, false)
		_:
			_m(p, B3Mats.hemi(0.19), _c(OLIVE.darkened(0.2), 0.6), Vector3(0, 0.63, -0.01))
			_m(p, B3Mats.cyl(0.205, 0.205, 0.025, 14), _c(OLIVE.darkened(0.35), 0.6), Vector3(0, 0.63, -0.01), Vector3.ZERO, Vector3.ONE, false)
	_eye(p, Vector3(0.06, 0.62, 0.15), 0.028)
	_eye(p, Vector3(-0.06, 0.62, 0.15), 0.028)
	_m(p, B3Mats.box(Vector3(0.07, 0.02, 0.02)), _c(Color("8a3b3b")), Vector3(0, 0.53, 0.165), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		var rot := Vector3(-65, 0, 0) if arms_fwd else Vector3(0, 0, 10 * sx)
		var at := Vector3(0.22 * sx, 0.24, 0.12) if arms_fwd else Vector3(0.22 * sx, 0.2, 0)
		_m(p, B3Mats.capsule(0.055, 0.4), _c(shirt), at, rot)
	crew.append(p)
	_crew_y.append(pos.y)
	return p


func _wheel(parent: Node3D, pos: Vector3, r: float, w: float, hub: Color) -> Node3D:
	var n := _node("Wheel", parent, pos)
	_m(n, B3Mats.cyl(r, r, w, 16), _c(RUBBER, 0.9), Vector3.ZERO, Vector3(0, 0, 90))
	_m(n, B3Mats.cyl(r * 0.55, r * 0.55, w + 0.02, 12), _c(hub, 0.5), Vector3.ZERO, Vector3(0, 0, 90), Vector3.ONE, false)
	_m(n, B3Mats.box(Vector3(w + 0.04, r * 0.9, r * 0.18)), _c(hub.darkened(0.3), 0.5), Vector3.ZERO, Vector3.ZERO, Vector3.ONE, false)
	_m(n, B3Mats.cyl(r * 0.18, r * 0.18, w + 0.06, 8), _c(METAL, 0.4), Vector3.ZERO, Vector3(0, 0, 90), Vector3.ONE, false)
	wheels.append(n)
	return n


# --------------------------------------------------------------------- tank
func _build_tank() -> void:
	var paint := _paint()
	var dark := paint.darkened(0.35)
	var trackc := Color("37393e")
	radius = 1.65
	height = 2.35
	top = 2.4
	reach_y = 1.0
	wheel_r = 0.26
	var hull := _pivot("hull", self, Vector3.ZERO)
	# tracks with road wheels and moving cleats (each side can fly off)
	for sx: float in [-1.0, 1.0]:
		var x := 1.0 * sx
		var tr := _node("Track", hull, Vector3(x, 0, 0))
		_m(tr, B3Mats.box(Vector3(0.6, 0.62, 3.3)), _c(trackc, 0.9), Vector3(0, 0.42, 0))
		for z: float in [1.65, -1.65]:
			_m(tr, B3Mats.cyl(0.31, 0.31, 0.6, 16), _c(trackc, 0.9), Vector3(0, 0.42, z), Vector3(0, 0, 90))
			_m(tr, B3Mats.cyl(0.2, 0.2, 0.64, 10), _c(Color("55585e"), 0.5), Vector3(0, 0.42, z), Vector3(0, 0, 90), Vector3.ONE, false)
		for i in 5:
			_wheel(tr, Vector3(0.31 * sx, 0.38, lerpf(-1.25, 1.25, i / 4.0)), 0.25, 0.06, Color("70747a"))
		for i in 9:
			var z := -1.6 + i * 0.4
			var top_c := _m(tr, B3Mats.box(Vector3(0.62, 0.06, 0.14)), _c(Color("26272b"), 0.9), Vector3(0, 0.75, z), Vector3.ZERO, Vector3.ONE, false)
			cleats.append([top_c, z, 1.0])
			var bot_c := _m(tr, B3Mats.box(Vector3(0.62, 0.06, 0.14)), _c(Color("26272b"), 0.9), Vector3(0, 0.1, z), Vector3.ZERO, Vector3.ONE, false)
			cleats.append([bot_c, z, -1.0])
		_k(_m(tr, B3Mats.box(Vector3(0.72, 0.07, 3.85)), _c(dark), Vector3(0, 0.79, 0)))
		_piece(tr, Vector3(0.6, 0.75, 3.9), Vector3(0, 0.42, 0), 18.0, 5.0)
	# hull: body, sloped front plate, engine deck, headlights, exhausts
	_k(_m(hull, B3Mats.box(Vector3(1.5, 0.6, 3.3)), _c(paint, 0.6), Vector3(0, 0.98, -0.1)))
	_k(_m(hull, B3Mats.box(Vector3(1.5, 0.12, 0.9)), _c(paint, 0.6), Vector3(0, 0.98, 1.72), Vector3(28, 0, 0)))
	_k(_m(hull, B3Mats.box(Vector3(1.54, 0.08, 3.34)), _c(_light()), Vector3(0, 1.0, -0.1), Vector3.ZERO, Vector3.ONE, false))
	for i in 4:
		_m(hull, B3Mats.box(Vector3(1.1, 0.03, 0.1)), _c(dark.darkened(0.3)), Vector3(0, 1.29, -1.1 - i * 0.18), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		_k(_m(hull, B3Mats.sphere(0.09, 8), B3Mats.glow(Color(1.0, 0.95, 0.7), 1.6), Vector3(0.58 * sx, 1.18, 1.62), Vector3.ZERO, Vector3.ONE, false))
		_m(hull, B3Mats.cyl(0.08, 0.08, 0.3, 8), _c(GUN, 0.5), Vector3(0.45 * sx, 1.0, -1.85), Vector3(90, 0, 0), Vector3.ONE, false)
		_m(hull, B3Mats.box(Vector3(0.2, 0.2, 0.42)), _c(OLIVE.darkened(0.15)), Vector3(0.62 * sx, 1.38, -1.2), Vector3.ZERO, Vector3.ONE, false)
	# turret: round base, boxy front, hatch with the commander, antenna flag
	turret = _pivot("turret", hull, Vector3(0, 1.26, -0.3))
	_k(_m(turret, B3Mats.cyl(0.78, 0.86, 0.5, 20), _c(paint, 0.6), Vector3(0, 0.25, 0)))
	_k(_m(turret, B3Mats.box(Vector3(1.22, 0.5, 1.2)), _c(paint, 0.6), Vector3(0, 0.27, 0.22)))
	_k(_m(turret, B3Mats.box(Vector3(0.6, 0.4, 0.3)), _c(dark), Vector3(0, 0.27, 0.86)))
	for sx: float in [-1.0, 1.0]:
		_m(turret, B3Mats.cyl(0.17, 0.17, 0.02, 5), _c(CREAM, 0.6), Vector3(0.62 * sx, 0.3, 0.2), Vector3(0, 0, 90), Vector3.ONE, false)
	_k(_m(turret, B3Mats.cyl(0.3, 0.32, 0.1, 14), _c(dark), Vector3(0.28, 0.55, -0.2)))
	_person(turret, Vector3(0.28, 0.32, -0.2), false)
	_k(_m(turret, B3Mats.cyl(0.012, 0.012, 1.4, 4), _c(GUN), Vector3(-0.5, 1.15, -0.55), Vector3.ZERO, Vector3.ONE, false))
	_k(_m(turret, B3Mats.box(Vector3(0.02, 0.2, 0.32)), _c(team_col if team != "wild" else Color("d9c25a")), Vector3(-0.5, 1.72, -0.72), Vector3.ZERO, Vector3.ONE, false))
	gun = _k(_pivot("gun", turret, Vector3(0, 0.3, 0.95)))
	_m(gun, B3Mats.cyl(0.1, 0.12, 2.1, 12), _c(paint.darkened(0.15), 0.5), Vector3(0, 0, 1.05), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.16, 0.16, 0.32, 12), _c(dark.darkened(0.2)), Vector3(0, 0, 2.05), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.035, 0.035, 0.5, 6), _c(GUN), Vector3(0.24, 0.02, 0.3), Vector3(90, 0, 0), Vector3.ONE, false)
	muzzle = _marker(gun, Vector3(0, 0, 2.25))
	mg_muzzle = _marker(gun, Vector3(0.24, 0.02, 0.58))
	eye = _marker(turret, Vector3(0.28, 1.3, -0.25))      # the commander standing in the hatch
	_piece(hull, Vector3(1.6, 0.7, 3.6), Vector3(0, 0.98, 0), 60.0, 4.0, true)
	_piece(turret, Vector3(1.3, 0.55, 1.4), Vector3(0, 0.27, 0.15), 25.0, 9.0)
	_shape_box(Vector3(2.5, 0.9, 3.95), Vector3(0, 0.9, 0))
	_shape_cap(0.36, 4.0, Vector3(0.95, 0.38, 0))
	_shape_cap(0.36, 4.0, Vector3(-0.95, 0.38, 0))
	_shape_box(Vector3(1.4, 0.55, 1.5), Vector3(0, 1.55, -0.15))


# --------------------------------------------------------------------- jeep
func _build_jeep() -> void:
	var paint := _paint()
	var dark := paint.darkened(0.35)
	radius = 1.3
	height = 2.3
	top = 2.4
	reach_y = 0.95
	wheel_r = 0.42
	var hull := _pivot("hull", self, Vector3.ZERO)
	var front := _k(_node("Front", hull, Vector3.ZERO))     # stays in view from the driver's seat
	# body tub, hood, grille, lights, bumpers, fenders
	_m(hull, B3Mats.box(Vector3(1.6, 0.55, 2.4)), _c(paint, 0.6), Vector3(0, 0.85, -0.3))
	_m(front, B3Mats.box(Vector3(1.5, 0.36, 1.05)), _c(paint, 0.6), Vector3(0, 0.96, 1.2))
	_m(front, B3Mats.box(Vector3(1.3, 0.42, 0.07)), _c(dark.darkened(0.3)), Vector3(0, 0.9, 1.73))
	for i in 5:
		_m(front, B3Mats.box(Vector3(0.06, 0.32, 0.03)), _c(Color("1d1e22")), Vector3(-0.3 + i * 0.15, 0.92, 1.77), Vector3.ZERO, Vector3.ONE, false)
	_m(front, B3Mats.box(Vector3(1.75, 0.12, 0.14)), _c(GUN, 0.5), Vector3(0, 0.66, 1.82))
	_m(hull, B3Mats.box(Vector3(1.75, 0.12, 0.14)), _c(GUN, 0.5), Vector3(0, 0.66, -1.55))
	for sx: float in [-1.0, 1.0]:
		_m(front, B3Mats.sphere(0.11, 10), B3Mats.glow(Color(1.0, 0.95, 0.7), 1.8), Vector3(0.5 * sx, 1.0, 1.76), Vector3.ZERO, Vector3.ONE, false)
		_m(front, B3Mats.box(Vector3(0.42, 0.07, 1.0)), _c(dark), Vector3(0.82 * sx, 1.12, 1.1))
		_m(hull, B3Mats.box(Vector3(0.42, 0.07, 1.0)), _c(dark), Vector3(0.82 * sx, 1.12, -1.05))
	_m(front, B3Mats.box(Vector3(1.62, 0.08, 0.5)), _c(_light()), Vector3(0, 1.15, 1.25), Vector3.ZERO, Vector3.ONE, false)
	_m(front, B3Mats.cyl(0.18, 0.18, 0.02, 5), _c(CREAM, 0.6), Vector3(0, 1.15, 1.25), Vector3.ZERO, Vector3.ONE, false)
	# windscreen, seats, steering wheel, driver
	_m(front, B3Mats.box(Vector3(1.5, 0.06, 0.06)), _c(GUN), Vector3(0, 1.62, 0.66), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		_m(front, B3Mats.box(Vector3(0.06, 0.52, 0.06)), _c(GUN), Vector3(0.72 * sx, 1.36, 0.66), Vector3.ZERO, Vector3.ONE, false)
	_m(hull, B3Mats.box(Vector3(1.38, 0.46, 0.03)), B3Mats.flat(GLASS), Vector3(0, 1.37, 0.66), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		_m(hull, B3Mats.box(Vector3(0.5, 0.14, 0.5)), _c(Color("4a3a2a")), Vector3(0.38 * sx, 1.15, -0.05))
		_m(hull, B3Mats.box(Vector3(0.5, 0.5, 0.12)), _c(Color("4a3a2a")), Vector3(0.38 * sx, 1.4, -0.3))
	_m(front, B3Mats.torus(0.13, 0.17), _c(GUN), Vector3(0.38, 1.42, 0.32), Vector3(60, 0, 0), Vector3.ONE, false)
	_person(hull, Vector3(0.38, 1.0, -0.05), true)
	eye = _marker(hull, Vector3(0.38, 1.9, -0.02))
	_m(hull, B3Mats.cyl(0.33, 0.33, 0.2, 14), _c(RUBBER, 0.9), Vector3(0, 1.0, -1.66), Vector3(90, 0, 0))
	_m(hull, B3Mats.cyl(0.012, 0.012, 1.5, 4), _c(GUN), Vector3(-0.72, 1.85, -1.4), Vector3.ZERO, Vector3.ONE, false)
	_m(hull, B3Mats.box(Vector3(0.02, 0.2, 0.32)), _c(team_col if team != "wild" else Color("d9c25a")), Vector3(-0.72, 2.45, -1.57), Vector3.ZERO, Vector3.ONE, false)
	# wheels: the front pair steers
	for sx: float in [-1.0, 1.0]:
		for z: float in [1.1, -1.05]:
			var st := _node("Steer", hull, Vector3(0.82 * sx, 0.42, z))
			var w := _wheel(st, Vector3.ZERO, 0.42, 0.32, Color("8a8f96"))
			if z > 0.0:
				steer.append(st)
				_k(st)
			_piece(w, Vector3(0.32, 0.84, 0.84), Vector3.ZERO, 5.0, 6.0)
	# machine gun on a post in the back, with its gunner
	turret = _pivot("turret", hull, Vector3(0, 1.12, -0.95))
	_m(turret, B3Mats.cyl(0.07, 0.09, 0.55, 8), _c(GUN), Vector3(0, 0.27, 0.15))
	_person(turret, Vector3(0, 0.0, -0.45), true)
	gun = _pivot("gun", turret, Vector3(0, 0.6, 0.18))
	_m(gun, B3Mats.box(Vector3(0.16, 0.18, 0.62)), _c(GUN, 0.4), Vector3(0, 0, 0.18))
	_m(gun, B3Mats.cyl(0.06, 0.06, 0.4, 10), _c(GUN.lightened(0.1), 0.4), Vector3(0, 0.02, 0.62), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.03, 0.03, 0.3, 6), _c(GUN, 0.4), Vector3(0, 0.02, 0.94), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(gun, B3Mats.box(Vector3(0.18, 0.16, 0.22)), _c(OLIVE), Vector3(-0.17, -0.04, 0.12))
	_m(gun, B3Mats.box(Vector3(0.62, 0.38, 0.04)), _c(dark), Vector3(0, 0.08, 0.42))
	muzzle = _marker(gun, Vector3(0, 0.02, 1.1))
	_piece(hull, Vector3(1.6, 0.8, 3.3), Vector3(0, 0.95, 0.1), 30.0, 4.0, true)
	_piece(turret, Vector3(0.7, 1.2, 1.0), Vector3(0, 0.6, 0), 8.0, 8.0)
	_shape_box(Vector3(1.7, 0.75, 3.4), Vector3(0, 0.95, 0.1))
	_shape_cap(0.42, 3.0, Vector3(0.8, 0.42, 0.02))
	_shape_cap(0.42, 3.0, Vector3(-0.8, 0.42, 0.02))
	_shape_box(Vector3(0.8, 0.9, 0.9), Vector3(0, 1.75, -1.0))


# ------------------------------------------------------------------- cannon
func _build_cannon() -> void:
	var bronze := Color("2f3236")
	var wood := WOOD
	radius = 1.05
	height = 1.7
	top = 1.8
	reach_y = 0.8
	wheel_r = 0.62
	var base := _pivot("hull", self, Vector3.ZERO)
	# wooden carriage resting on its trail, team-coloured stripe, axle
	_k(_m(base, B3Mats.box(Vector3(0.52, 0.24, 2.0)), _c(wood), Vector3(0, 0.42, -0.8), Vector3(-17, 0, 0)))
	_k(_m(base, B3Mats.box(Vector3(0.54, 0.07, 1.2)), _c(team_col if team != "wild" else Color("c9a04a")), Vector3(0, 0.56, -0.65), Vector3(-17, 0, 0), Vector3.ONE, false))
	_k(_m(base, B3Mats.box(Vector3(0.7, 0.36, 0.6)), _c(wood.darkened(0.1)), Vector3(0, 0.78, 0.05)))
	_k(_m(base, B3Mats.cyl(0.07, 0.07, 1.3, 8), _c(GUN), Vector3(0, 0.62, 0.05), Vector3(0, 0, 90)))
	for i in 3:
		_m(base, B3Mats.sphere(0.17, 10), B3Mats.mat(Color("26282c"), 0.35, 0.4), Vector3(0.62 + (i % 2) * 0.32, 0.17 + (0.27 if i == 2 else 0.0), -1.2 + (0.16 if i == 2 else 0.0)))
	# big spoked wooden wheels
	for sx: float in [-1.0, 1.0]:
		var w := _k(_node("Wheel", base, Vector3(0.62 * sx, 0.62, 0.05)))
		_m(w, B3Mats.torus(0.5, 0.62), _c(wood.darkened(0.15)), Vector3.ZERO, Vector3(0, 0, 90))
		_m(w, B3Mats.torus(0.58, 0.64), _c(GUN, 0.4), Vector3.ZERO, Vector3(0, 0, 90), Vector3.ONE, false)
		_m(w, B3Mats.cyl(0.13, 0.13, 0.16, 10), _c(wood.darkened(0.25)), Vector3.ZERO, Vector3(0, 0, 90), Vector3.ONE, false)
		for k in 6:
			_m(w, B3Mats.box(Vector3(0.05, 1.04, 0.06)), _c(wood), Vector3.ZERO, Vector3(k * 30.0, 0, 0), Vector3.ONE, false)
		wheels.append(w)
		_piece(w, Vector3(0.18, 1.25, 1.25), Vector3.ZERO, 6.0, 6.0)
	# the barrel tilts up for long lobs
	gun = _k(_pivot("gun", base, Vector3(0, 0.98, 0.05)))
	_m(gun, B3Mats.cyl(0.17, 0.27, 1.9, 18), B3Mats.mat(bronze, 0.35, 0.4), Vector3(0, 0, 0.55), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.215, 0.215, 0.12, 18), B3Mats.mat(bronze.darkened(0.2), 0.35, 0.4), Vector3(0, 0, 1.48), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.25, 0.25, 0.1, 18), _c(team_col if team != "wild" else Color("c9a04a"), 0.5), Vector3(0, 0, 0.25), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(gun, B3Mats.cyl(0.29, 0.29, 0.08, 18), B3Mats.mat(bronze.darkened(0.2), 0.35, 0.4), Vector3(0, 0, -0.3), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(gun, B3Mats.sphere(0.15, 10), B3Mats.mat(bronze, 0.35, 0.4), Vector3(0, 0, -0.5))
	_m(gun, B3Mats.cyl(0.11, 0.11, 0.04, 14), _c(Color("0c0c0e")), Vector3(0, 0, 1.55), Vector3(90, 0, 0), Vector3.ONE, false)
	muzzle = _marker(gun, Vector3(0, 0, 1.6))
	eye = _marker(base, Vector3(0.0, 1.55, -1.35))      # the gunner, crouched behind the barrel
	_piece(base, Vector3(0.7, 0.6, 2.2), Vector3(0, 0.55, -0.5), 20.0, 4.0, true)
	_piece(gun, Vector3(0.5, 0.5, 2.0), Vector3(0, 0, 0.55), 15.0, 7.0)
	_shape_cap(0.6, 1.4, Vector3(0, 0.62, 0.05), "x")
	_shape_box(Vector3(0.6, 0.45, 2.3), Vector3(0, 0.75, 0.2))
	var s := SphereShape3D.new()
	s.radius = 0.22
	shapes.append({"shape": s, "xf": Transform3D(Basis.IDENTITY, Vector3(0, 0.22, -1.55))})


# -------------------------------------------------------------------- nest
func _build_nest() -> void:
	radius = 1.45
	height = 1.75
	top = 1.8
	reach_y = 0.85
	var base := _pivot("hull", self, Vector3.ZERO)
	# a ring of sandbags (front and back halves fly apart separately)
	var halves := [_k(_node("Front", base, Vector3.ZERO)), _node("Back", base, Vector3.ZERO)]
	for layer in 2:
		var n := 11 if layer == 0 else 10
		for i in n:
			var a := TAU * (i + 0.5 * layer) / n
			var half: Node3D = halves[0] if cos(a) > 0.0 else halves[1]
			var c := SAND if (i + layer) % 3 != 0 else SAND.darkened(0.12)
			var r := 1.15 - layer * 0.06
			_m(half, B3Mats.capsule(0.17, 0.68), _c(c, 0.95), Vector3(sin(a) * r, 0.17 + layer * 0.29, cos(a) * r), Vector3(0, rad_to_deg(a), 90), Vector3(1.0, 1.0, 0.75))
	_m(base, B3Mats.cyl(1.0, 1.0, 0.05, 20), _c(Color("8a7a52"), 0.95), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3.ONE, false)
	_m(halves[1], B3Mats.cyl(0.015, 0.015, 1.5, 4), _c(GUN), Vector3(-0.8, 1.0, -0.8), Vector3.ZERO, Vector3.ONE, false)
	_m(halves[1], B3Mats.box(Vector3(0.02, 0.24, 0.38)), _c(team_col if team != "wild" else Color("d9c25a")), Vector3(-0.8, 1.62, -0.99), Vector3.ZERO, Vector3.ONE, false)
	# swivelling machine gun on a tripod, with a gunner behind it
	turret = _pivot("turret", base, Vector3(0, 0, 0.1))
	for k in 3:
		var a2 := TAU * k / 3.0
		_m(turret, B3Mats.cyl(0.025, 0.03, 0.85, 6), _c(GUN), Vector3(sin(a2) * 0.2, 0.38, cos(a2) * 0.2 + 0.2), Vector3(cos(a2) * 18.0, 0, -sin(a2) * 18.0), Vector3.ONE, false)
	_m(turret, B3Mats.cyl(0.06, 0.06, 0.3, 8), _c(GUN), Vector3(0, 0.82, 0.2))
	_person(turret, Vector3(0, 0.2, -0.45), true)
	gun = _k(_pivot("gun", turret, Vector3(0, 1.0, 0.2)))
	_m(gun, B3Mats.box(Vector3(0.2, 0.22, 0.66)), _c(GUN, 0.4), Vector3(0, 0, 0.05))
	_m(gun, B3Mats.cyl(0.075, 0.075, 0.6, 10), _c(GUN.lightened(0.12), 0.4), Vector3(0, 0.02, 0.66), Vector3(90, 0, 0))
	for k in 4:
		_m(gun, B3Mats.torus(0.07, 0.085), _c(GUN.darkened(0.3)), Vector3(0, 0.02, 0.45 + k * 0.12), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(gun, B3Mats.cyl(0.035, 0.035, 0.32, 6), _c(GUN, 0.4), Vector3(0, 0.02, 1.08), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(gun, B3Mats.box(Vector3(0.22, 0.2, 0.26)), _c(OLIVE), Vector3(-0.23, -0.05, 0.0))
	_m(gun, B3Mats.box(Vector3(0.9, 0.5, 0.05)), _c(_paint(), 0.6), Vector3(0, 0.08, 0.42))
	muzzle = _marker(gun, Vector3(0, 0.02, 1.26))
	eye = _marker(turret, Vector3(0, 1.38, -0.45))
	_piece(halves[0], Vector3(2.4, 0.65, 1.2), Vector3(0, 0.32, 0.6), 30.0, 4.0, true)
	_piece(halves[1], Vector3(2.4, 0.65, 1.2), Vector3(0, 0.32, -0.6), 30.0, 4.0)
	_piece(turret, Vector3(0.9, 1.3, 1.4), Vector3(0, 0.65, 0.2), 10.0, 8.0)
	var cy := CylinderShape3D.new()
	cy.radius = 1.33
	cy.height = 0.92
	shapes.append({"shape": cy, "xf": Transform3D(Basis.IDENTITY, Vector3(0, 0.48, 0))})
	_shape_box(Vector3(0.8, 0.9, 0.8), Vector3(0, 1.35, -0.2))


# ----------------------------------------------------------------- race car
## A bubbly open-wheel race car: big back wheels, a front wing and a rear
## spoiler, number roundels and a driver in a crash helmet.
func _build_car() -> void:
	var paint := team_col if team != "wild" else Color("e8a33a")
	var light := paint.lightened(0.35)
	var dark := paint.darkened(0.4)
	var chrome := Color("d8dde3")
	radius = 1.25
	height = 1.45
	top = 1.6
	reach_y = 0.65
	wheel_r = 0.42
	var hull := _pivot("hull", self, Vector3.ZERO)
	var shell := _k(_node("Shell", hull, Vector3.ZERO))      # everything but the driver stays in view
	# the rounded body, side pods and engine hump
	_m(shell, B3Mats.capsule(0.42, 3.1), _c(paint, 0.35), Vector3(0, 0.6, 0.0), Vector3(90, 0, 0), Vector3(1.25, 1.0, 0.85))
	for sx: float in [-1.0, 1.0]:
		_m(shell, B3Mats.capsule(0.19, 1.4), _c(light, 0.35), Vector3(0.52 * sx, 0.48, -0.25), Vector3(90, 0, 0), Vector3(1.0, 1.0, 0.9))
		_m(shell, B3Mats.cyl(0.21, 0.21, 0.02, 18), _c(CREAM, 0.5), Vector3(0.56 * sx, 0.62, 0.42), Vector3(0, 0, 90), Vector3.ONE, false)
		_m(shell, B3Mats.cyl(0.12, 0.12, 0.022, 14), _c(dark, 0.5), Vector3(0.565 * sx, 0.62, 0.42), Vector3(0, 0, 90), Vector3.ONE, false)
	_m(shell, B3Mats.capsule(0.2, 0.9), _c(dark, 0.4), Vector3(0, 1.0, -0.95), Vector3(90, 0, 0), Vector3(1.1, 1.0, 1.0))
	_m(shell, B3Mats.box(Vector3(0.12, 0.03, 2.6)), _c(CREAM, 0.4), Vector3(0, 0.97, 0.15), Vector3.ZERO, Vector3.ONE, false)
	# cockpit opening, little windscreen, steering wheel
	_m(shell, B3Mats.box(Vector3(0.62, 0.05, 0.85)), _c(Color("1d1e22")), Vector3(0, 0.95, -0.2), Vector3.ZERO, Vector3.ONE, false)
	_m(hull, B3Mats.box(Vector3(0.6, 0.16, 0.03)), B3Mats.flat(GLASS), Vector3(0, 1.06, 0.3), Vector3(-25, 0, 0), Vector3.ONE, false)
	_m(shell, B3Mats.torus(0.09, 0.12), _c(Color("1d1e22")), Vector3(0, 0.98, 0.14), Vector3(65, 0, 0), Vector3.ONE, false)
	# front wing and rear spoiler
	_m(shell, B3Mats.box(Vector3(1.9, 0.06, 0.4)), _c(dark), Vector3(0, 0.2, 1.75))
	for sx: float in [-1.0, 1.0]:
		_m(shell, B3Mats.box(Vector3(0.05, 0.24, 0.46)), _c(light), Vector3(0.95 * sx, 0.28, 1.74), Vector3.ZERO, Vector3.ONE, false)
		_m(shell, B3Mats.box(Vector3(0.06, 0.42, 0.12)), _c(dark), Vector3(0.32 * sx, 1.0, -1.45), Vector3.ZERO, Vector3.ONE, false)
		_m(shell, B3Mats.box(Vector3(0.05, 0.32, 0.52)), _c(light), Vector3(0.82 * sx, 1.2, -1.5), Vector3.ZERO, Vector3.ONE, false)
		_m(shell, B3Mats.cyl(0.07, 0.09, 0.34, 10), _c(chrome, 0.25), Vector3(0.22 * sx, 0.58, -1.62), Vector3(90, 0, 0), Vector3.ONE, false)
		# suspension arms out to the wheels
		_m(shell, B3Mats.box(Vector3(0.42, 0.05, 0.07)), _c(GUN), Vector3(0.66 * sx, 0.36, 1.0), Vector3.ZERO, Vector3.ONE, false)
		_m(shell, B3Mats.box(Vector3(0.42, 0.05, 0.07)), _c(GUN), Vector3(0.66 * sx, 0.46, -1.0), Vector3.ZERO, Vector3.ONE, false)
	_m(shell, B3Mats.box(Vector3(1.68, 0.07, 0.46)), _c(dark), Vector3(0, 1.24, -1.5))
	_m(shell, B3Mats.box(Vector3(1.6, 0.075, 0.1)), _c(light), Vector3(0, 1.26, -1.3), Vector3.ZERO, Vector3.ONE, false)
	# the driver, in a big white crash helmet
	_person(hull, Vector3(0, 0.42, -0.25), true, "race")
	eye = _marker(hull, Vector3(0, 1.32, -0.2))
	# wheels: small steering ones in front, fat ones at the back
	for sx: float in [-1.0, 1.0]:
		var st := _k(_node("Steer", hull, Vector3(0.86 * sx, 0.36, 1.0)))
		var fw := _wheel(st, Vector3.ZERO, 0.36, 0.3, light)
		steer.append(st)
		_piece(fw, Vector3(0.3, 0.72, 0.72), Vector3.ZERO, 4.0, 6.0)
		var rw := _wheel(_k(_node("Axle", hull, Vector3(0.9 * sx, 0.46, -1.0))), Vector3.ZERO, 0.46, 0.42, light)
		_piece(rw, Vector3(0.42, 0.92, 0.92), Vector3.ZERO, 6.0, 6.0)
	_piece(hull, Vector3(1.2, 0.7, 3.4), Vector3(0, 0.62, 0.1), 25.0, 5.0, true)
	_shape_box(Vector3(1.2, 0.62, 3.4), Vector3(0, 0.65, 0.1))
	_shape_cap(0.4, 2.7, Vector3(0.86, 0.4, 0.0))
	_shape_cap(0.4, 2.7, Vector3(-0.86, 0.4, 0.0))


# --------------------------------------------------------------- helicopter
## A chunky toy helicopter: round cabin with a glass bubble and a pilot,
## tail boom, spinning main and tail rotors, skids, stub wings with rocket
## pods and a swivelling chin gun (turret + gun).
func _build_heli() -> void:
	var paint := _paint()
	var dark := paint.darkened(0.35)
	radius = 2.2
	height = 3.3
	top = 3.4
	reach_y = 1.5
	var hull := _pivot("hull", self, Vector3.ZERO)
	var frame := _k(_node("Frame", hull, Vector3.ZERO))       # what the pilot sees around them
	# cabin, chin and the glass bubble with the pilot inside
	_m(hull, B3Mats.sphere(1.0, 18), _c(paint, 0.45), Vector3(0, 1.45, -0.55), Vector3.ZERO, Vector3(0.95, 0.85, 1.15))
	_m(frame, B3Mats.sphere(0.6, 16), _c(paint, 0.45), Vector3(0, 0.98, 0.85), Vector3.ZERO, Vector3(1.15, 0.62, 1.15))
	_m(hull, B3Mats.box(Vector3(1.94, 0.12, 1.6)), _c(_light()), Vector3(0, 1.42, -0.55), Vector3.ZERO, Vector3(1.0, 1.0, 1.0), false)
	_person(hull, Vector3(0, 0.98, 0.78), true, "race")
	_m(hull, B3Mats.sphere(0.72, 16), B3Mats.flat(GLASS), Vector3(0, 1.5, 0.85), Vector3.ZERO, Vector3(0.92, 0.88, 1.0), false)
	_m(hull, B3Mats.torus(0.68, 0.74), _c(GUN, 0.5), Vector3(0, 1.5, 0.85), Vector3(0, 0, 90), Vector3(1.0, 0.88, 1.0), false)
	_m(hull, B3Mats.box(Vector3(0.4, 0.09, 0.05)), _c(Color("2a2c31")), Vector3(0, 1.4, 1.36), Vector3(-35, 0, 0), Vector3.ONE, false)
	for i in 3:
		var dc: Color = [Color(0.3, 1.0, 0.4), Color(1.0, 0.85, 0.2), Color(1.0, 0.35, 0.3)][i]
		_m(hull, B3Mats.sphere(0.022, 6), B3Mats.glow(dc, 1.6), Vector3(-0.11 + i * 0.11, 1.43, 1.39), Vector3.ZERO, Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		_m(hull, B3Mats.cyl(0.24, 0.24, 0.02, 5), _c(CREAM, 0.6), Vector3(0.92 * sx, 1.55, -0.75), Vector3(0, 0, 90), Vector3.ONE, false)
	# engine on top, the rotor mast and the main rotor
	_m(hull, B3Mats.capsule(0.36, 1.6), _c(dark, 0.5), Vector3(0, 2.2, -0.75), Vector3(90, 0, 0), Vector3(1.15, 1.0, 1.0))
	for sx: float in [-1.0, 1.0]:
		_m(hull, B3Mats.cyl(0.1, 0.12, 0.3, 10), _c(GUN), Vector3(0.36 * sx, 2.25, -1.55), Vector3(90, 0, 0), Vector3.ONE, false)
	_m(hull, B3Mats.cyl(0.08, 0.1, 0.55, 10), _c(METAL, 0.4), Vector3(0, 2.62, -0.55))
	var rotor := _k(_node("Rotor", hull, Vector3(0, 2.88, -0.55)))
	_m(rotor, B3Mats.cyl(0.2, 0.2, 0.16, 12), _c(GUN, 0.4), Vector3.ZERO)
	for k in 4:
		var a := TAU * k / 4.0
		var deg := rad_to_deg(a)
		_m(rotor, B3Mats.box(Vector3(0.3, 0.05, 2.9)), _c(Color("3a3d44"), 0.5), Vector3(sin(a) * 1.6, 0.04, cos(a) * 1.6), Vector3(0, deg, 0))
		_m(rotor, B3Mats.box(Vector3(0.31, 0.06, 0.3)), _c(VGOLD, 0.5), Vector3(sin(a) * 2.95, 0.04, cos(a) * 2.95), Vector3(0, deg, 0), Vector3.ONE, false)
	rotors.append([rotor, 1, 2.6])
	_k(_blur(hull, Vector3(0, 2.92, -0.55), 3.1, "y"))
	# tail boom, fins and the tail rotor
	var tail := _node("Tail", hull, Vector3.ZERO)
	_seg(tail, Vector3(0, 1.6, -1.4), Vector3(0, 2.05, -4.5), 0.36, 0.13, _c(paint, 0.45))
	_m(tail, B3Mats.box(Vector3(0.09, 1.0, 0.7)), _c(dark), Vector3(0, 2.5, -4.45), Vector3(-20, 0, 0))
	_m(tail, B3Mats.box(Vector3(0.1, 0.35, 0.5)), _c(_light()), Vector3(0, 2.75, -4.55), Vector3(-20, 0, 0), Vector3.ONE, false)
	_m(tail, B3Mats.box(Vector3(1.35, 0.06, 0.45)), _c(paint), Vector3(0, 1.98, -3.75))
	var trot := _node("TailRotor", tail, Vector3(0.14, 2.42, -4.5))
	_m(trot, B3Mats.cyl(0.07, 0.07, 0.1, 8), _c(GUN), Vector3.ZERO, Vector3(0, 0, 90))
	for k in 2:
		_m(trot, B3Mats.box(Vector3(0.04, 1.1, 0.16)), _c(Color("3a3d44"), 0.5), Vector3(0.03, 0, 0), Vector3(k * 90.0, 0, 0))
		_m(trot, B3Mats.box(Vector3(0.05, 0.16, 0.17)), _c(VGOLD, 0.5), Vector3(0.03, 0.5, 0), Vector3(k * 90.0, 0, 0), Vector3.ONE, false)
		_m(trot, B3Mats.box(Vector3(0.05, 0.16, 0.17)), _c(VGOLD, 0.5), Vector3(0.03, -0.5, 0), Vector3(k * 90.0, 0, 0), Vector3.ONE, false)
	rotors.append([trot, 0, 5.0])
	_blur(tail, Vector3(0.18, 2.42, -4.5), 0.58, "x")
	# skids
	var skids := _k(_node("Skids", hull, Vector3.ZERO))
	for sx: float in [-1.0, 1.0]:
		_m(skids, B3Mats.cyl(0.06, 0.06, 2.6, 8), _c(GUN, 0.5), Vector3(0.85 * sx, 0.07, 0.0), Vector3(90, 0, 0))
		_seg(skids, Vector3(0.85 * sx, 0.07, 1.28), Vector3(0.85 * sx, 0.3, 1.62), 0.06, 0.06, _c(GUN, 0.5))
		_seg(skids, Vector3(0.85 * sx, 0.07, 0.75), Vector3(0.45 * sx, 0.78, 0.55), 0.045, 0.045, _c(GUN, 0.5))
		_seg(skids, Vector3(0.85 * sx, 0.07, -0.75), Vector3(0.45 * sx, 0.78, -0.75), 0.045, 0.045, _c(GUN, 0.5))
	# stub wings with rocket pods
	var wings := _k(_node("Wings", hull, Vector3.ZERO))
	_m(wings, B3Mats.box(Vector3(2.5, 0.09, 0.55)), _c(dark), Vector3(0, 1.22, -0.5))
	for sx: float in [-1.0, 1.0]:
		_m(wings, B3Mats.cyl(0.19, 0.19, 0.95, 12), _c(GUN, 0.5), Vector3(1.15 * sx, 1.06, -0.45), Vector3(90, 0, 0))
		_m(wings, B3Mats.cyl(0.2, 0.2, 0.04, 12), _c(Color("141518")), Vector3(1.15 * sx, 1.06, 0.03), Vector3(90, 0, 0), Vector3.ONE, false)
		for k in 3:
			var ra := TAU * k / 3.0
			_m(wings, B3Mats.cyl(0.0, 0.05, 0.12, 6), _c(Color("d94c3a")), Vector3(1.15 * sx + sin(ra) * 0.09, 1.06 + cos(ra) * 0.09, 0.08), Vector3(90, 0, 0), Vector3.ONE, false)
		rocket_muzzles.append(_marker(wings, Vector3(1.15 * sx, 1.06, 0.25)))
	# the chin gun swivels under the nose
	turret = _pivot("turret", hull, Vector3(0, 0.55, 1.35))
	_m(turret, B3Mats.sphere(0.2, 10), _c(GUN, 0.4), Vector3.ZERO)
	gun = _pivot("gun", turret, Vector3(0, -0.04, 0.1))
	_m(gun, B3Mats.cyl(0.045, 0.045, 0.7, 8), _c(GUN.lightened(0.1), 0.4), Vector3(0, 0, 0.35), Vector3(90, 0, 0))
	_m(gun, B3Mats.cyl(0.065, 0.065, 0.14, 8), _c(GUN, 0.4), Vector3(0, 0, 0.68), Vector3(90, 0, 0), Vector3.ONE, false)
	muzzle = _marker(gun, Vector3(0, 0, 0.78))
	eye = _marker(hull, Vector3(0, 1.72, 0.82))
	_piece(hull, Vector3(1.9, 1.7, 2.6), Vector3(0, 1.4, -0.2), 40.0, 4.0, true)
	_piece(tail, Vector3(0.6, 0.9, 3.2), Vector3(0, 2.0, -3.0), 12.0, 6.0)
	_piece(rotor, Vector3(3.0, 0.1, 0.4), Vector3.ZERO, 8.0, 10.0)
	_piece(skids, Vector3(1.8, 0.3, 2.6), Vector3(0, 0.2, 0), 6.0, 5.0)
	_shape_box(Vector3(1.8, 1.6, 2.3), Vector3(0, 1.45, -0.5))
	_shape_box(Vector3(1.3, 0.9, 1.3), Vector3(0, 1.15, 0.85))
	_shape_box(Vector3(0.6, 0.9, 3.0), Vector3(0, 2.0, -3.1))
	_shape_box(Vector3(1.9, 0.25, 2.6), Vector3(0, 0.13, 0.0))


# ------------------------------------------------------------ fighter plane
## A cartoony WWII-style propeller fighter: round cowling with a nose ring,
## a spinning three-blade propeller, low wings with roundels and guns, a
## bubble canopy with a goggled pilot, a bomb under the belly and landing
## gear that only shows when it's parked.
func _build_plane() -> void:
	var paint := _paint()
	var light := _light()
	var dark := paint.darkened(0.35)
	var ring := VGOLD if team != "yellow" else Color("ff6a3d")
	radius = 3.0
	height = 2.4
	top = 2.6
	reach_y = 1.25
	var hull := _pivot("hull", self, Vector3.ZERO)
	var body := _k(_node("Body", hull, Vector3.ZERO))
	# fuselage, cowling, nose ring, tail cone, turtle deck
	_m(body, B3Mats.capsule(0.56, 4.6), _c(paint, 0.4), Vector3(0, 1.25, -0.25), Vector3(90, 0, 0))
	_m(body, B3Mats.cyl(0.6, 0.6, 0.9, 20), _c(dark, 0.4), Vector3(0, 1.25, 1.75), Vector3(90, 0, 0))
	_m(body, B3Mats.cyl(0.63, 0.63, 0.22, 20), _c(ring, 0.4), Vector3(0, 1.25, 2.18), Vector3(90, 0, 0))
	_seg(body, Vector3(0, 1.3, -2.2), Vector3(0, 1.48, -4.0), 0.48, 0.17, _c(paint, 0.4))
	_seg(body, Vector3(0, 1.7, -0.7), Vector3(0, 1.58, -2.4), 0.28, 0.13, _c(paint, 0.4))
	_m(body, B3Mats.cyl(0.5, 0.5, 0.22, 18), _c(light, 0.4), Vector3(0, 1.3, -2.3), Vector3(90, 0, 0), Vector3.ONE, false)
	for sx: float in [-1.0, 1.0]:
		for i in 3:
			_m(body, B3Mats.box(Vector3(0.1, 0.08, 0.14)), _c(GUN), Vector3(0.58 * sx, 1.42, 1.3 + i * 0.2), Vector3.ZERO, Vector3.ONE, false)
	# propeller with its spinner
	var prop := _k(_node("Prop", hull, Vector3(0, 1.25, 2.38)))
	_m(prop, B3Mats.cyl(0.0, 0.27, 0.55, 14), _c(ring, 0.4), Vector3(0, 0, 0.22), Vector3(90, 0, 0))
	for k in 3:
		var a := TAU * k / 3.0
		_m(prop, B3Mats.box(Vector3(0.2, 1.45, 0.06)), _c(Color("2e2a27"), 0.6), Vector3(sin(a) * 0.75, cos(a) * 0.75, 0.05), Vector3(0, 0, -rad_to_deg(a)))
		_m(prop, B3Mats.box(Vector3(0.21, 0.22, 0.07)), _c(VGOLD, 0.5), Vector3(sin(a) * 1.38, cos(a) * 1.38, 0.05), Vector3(0, 0, -rad_to_deg(a)), Vector3.ONE, false)
	rotors.append([prop, 2, 3.4])
	_k(_blur(hull, Vector3(0, 1.25, 2.45), 1.5, "z"))
	# wings (a little dihedral), rounded tips, roundels and guns
	var wing_l := _k(_node("WingL", hull, Vector3.ZERO))
	var wing_r := _k(_node("WingR", hull, Vector3.ZERO))
	_m(body, B3Mats.box(Vector3(1.3, 0.3, 1.6)), _c(paint, 0.4), Vector3(0, 0.92, 0.3))
	for side in 2:
		var sx := 1.0 if side == 0 else -1.0
		var w: Node3D = wing_l if side == 0 else wing_r
		var dz := Vector3(0, 0, 6.0 * sx)
		_m(w, B3Mats.box(Vector3(3.2, 0.15, 1.45)), _c(paint, 0.4), Vector3(1.9 * sx, 0.95, 0.3), dz)
		_m(w, B3Mats.cyl(0.72, 0.72, 0.15, 18), _c(paint, 0.4), Vector3(3.45 * sx, 1.11, 0.3), dz, Vector3(0.42, 1.0, 1.0))
		_m(w, B3Mats.box(Vector3(0.5, 0.155, 1.46)), _c(light, 0.4), Vector3(3.05 * sx, 1.07, 0.3), dz, Vector3.ONE, false)
		_m(w, B3Mats.cyl(0.42, 0.42, 0.02, 20), _c(CREAM, 0.5), Vector3(2.3 * sx, 1.07, 0.3), dz, Vector3.ONE, false)
		_m(w, B3Mats.cyl(0.25, 0.25, 0.022, 18), _c(team_col if team != "wild" else OLIVE.darkened(0.3), 0.5), Vector3(2.3 * sx, 1.08, 0.3), dz, Vector3.ONE, false)
		for gx: float in [1.35, 1.75]:
			_m(w, B3Mats.cyl(0.04, 0.04, 0.55, 6), _c(GUN), Vector3(gx * sx, 0.95, 1.15), Vector3(90, 0, 0), Vector3.ONE, false)
		gun_muzzles.append(_marker(w, Vector3(1.55 * sx, 0.95, 1.5)))
	# tail: stabilisers and the fin
	var tail := _k(_node("Tail", hull, Vector3.ZERO))
	_m(tail, B3Mats.box(Vector3(2.5, 0.09, 0.75)), _c(paint, 0.4), Vector3(0, 1.45, -3.6))
	for sx: float in [-1.0, 1.0]:
		_m(tail, B3Mats.cyl(0.37, 0.37, 0.09, 14), _c(paint, 0.4), Vector3(1.22 * sx, 1.45, -3.6), Vector3.ZERO, Vector3(0.5, 1.0, 1.0))
	_m(tail, B3Mats.box(Vector3(0.09, 1.0, 0.9)), _c(paint, 0.4), Vector3(0, 1.95, -3.75), Vector3(-12, 0, 0))
	_m(tail, B3Mats.cyl(0.45, 0.45, 0.09, 14), _c(paint, 0.4), Vector3(0, 2.38, -3.88), Vector3(0, 0, 90), Vector3(1.0, 1.0, 0.95))
	_m(tail, B3Mats.box(Vector3(0.1, 0.85, 0.3)), _c(light, 0.4), Vector3(0, 1.98, -4.08), Vector3(-12, 0, 0), Vector3.ONE, false)
	# canopy: the goggled pilot under a glass bubble with frame hoops
	_person(hull, Vector3(0, 1.24, -0.15), true, "pilot")
	_m(hull, B3Mats.sphere(0.42, 14), B3Mats.flat(GLASS), Vector3(0, 1.86, -0.2), Vector3.ZERO, Vector3(0.88, 0.85, 1.65), false)
	for z: float in [0.42, -0.75]:
		_m(hull, B3Mats.torus(0.32, 0.37), _c(GUN, 0.5), Vector3(0, 1.82, z), Vector3(90, 0, 0), Vector3(1.0, 1.0, 1.05), false)
	_m(hull, B3Mats.box(Vector3(0.05, 0.05, 1.2)), _c(GUN, 0.5), Vector3(0, 2.21, -0.18), Vector3.ZERO, Vector3.ONE, false)
	eye = _marker(hull, Vector3(0, 2.1, -0.15))
	# a bomb under the belly
	bomb_node = _node("Bomb", hull, Vector3(0, 0.5, 0.25))
	_m(bomb_node, B3Mats.capsule(0.17, 0.95), _c(Color("3a3f45"), 0.5), Vector3.ZERO, Vector3(90, 0, 0))
	for a2: float in [0.0, 90.0]:
		_m(bomb_node, B3Mats.box(Vector3(0.38, 0.03, 0.22)), _c(Color("2a2e33")), Vector3(0, 0, -0.45), Vector3(0, 0, a2), Vector3.ONE, false)
	_m(bomb_node, B3Mats.cyl(0.175, 0.175, 0.08, 12), _c(Color("ffcf4a")), Vector3(0, 0, 0.18), Vector3(90, 0, 0), Vector3.ONE, false)
	# landing gear (hidden in the air)
	gear = _node("Gear", hull, Vector3.ZERO)
	for sx: float in [-1.0, 1.0]:
		_seg(gear, Vector3(1.1 * sx, 0.9, 0.5), Vector3(1.1 * sx, 0.32, 0.65), 0.06, 0.06, _c(GUN, 0.5))
		_m(gear, B3Mats.cyl(0.32, 0.32, 0.16, 14), _c(RUBBER, 0.9), Vector3(1.1 * sx, 0.32, 0.65), Vector3(0, 0, 90))
		_m(gear, B3Mats.cyl(0.15, 0.15, 0.18, 10), _c(METAL, 0.4), Vector3(1.1 * sx, 0.32, 0.65), Vector3(0, 0, 90), Vector3.ONE, false)
	_seg(gear, Vector3(0, 1.0, -3.4), Vector3(0, 0.14, -3.55), 0.04, 0.04, _c(GUN, 0.5))
	_m(gear, B3Mats.cyl(0.14, 0.14, 0.08, 10), _c(RUBBER, 0.9), Vector3(0, 0.14, -3.55), Vector3(0, 0, 90))
	gear.visible = false
	_piece(hull, Vector3(1.2, 1.2, 5.6), Vector3(0, 1.25, -0.6), 40.0, 4.0, true)
	_piece(wing_l, Vector3(3.3, 0.2, 1.5), Vector3(1.9, 0.95, 0.3), 8.0, 6.0)
	_piece(wing_r, Vector3(3.3, 0.2, 1.5), Vector3(-1.9, 0.95, 0.3), 8.0, 6.0)
	_piece(tail, Vector3(2.5, 1.2, 1.0), Vector3(0, 1.6, -3.7), 6.0, 7.0)
	_piece(prop, Vector3(0.6, 0.6, 0.6), Vector3.ZERO, 4.0, 8.0)
	_shape_box(Vector3(1.15, 1.15, 6.0), Vector3(0, 1.25, -0.8))
	_shape_box(Vector3(7.2, 0.3, 1.5), Vector3(0, 0.95, 0.3))
	_shape_box(Vector3(2.5, 1.2, 1.0), Vector3(0, 1.6, -3.7))


# ---------------------------------------------------------------- animation
func animate(dt: float, spd: float, act: String, k: float, aiming: bool, mood: String) -> void:
	super.animate(dt, spd, act, k, aiming, mood)
	_roll += drive_speed * dt / wheel_r
	for w in wheels:
		w.rotation.x = _roll
	if not cleats.is_empty():
		var off := fposmod(_roll * wheel_r * 0.5, 0.4)
		for c in cleats:
			var n: Node3D = c[0]
			var bz: float = c[1]
			var dir: float = c[2]
			n.position.z = -1.6 + fposmod(bz + 1.6 + off * dir, 3.6)
	if gun:
		var gb: Vector3 = _base_y.get("gun", gun.position)
		gun.position = gb - Vector3(0, 0, recoil * (0.35 if style == "tank" or style == "cannon" else 0.08))
	for i in rotors.size():
		var r: Array = rotors[i]
		var n2: Node3D = r[0]
		var ax: int = r[1]
		_spin[i] = fposmod(float(_spin[i]) + rotor_speed * float(r[2]) * TAU * dt, TAU)
		var rot := n2.rotation
		rot[ax] = float(_spin[i])
		n2.rotation = rot
	var fast := rotor_speed > 0.35
	for b in blurs:
		if b.visible != fast:
			b.visible = fast
	for i in crew.size():
		var c2: Node3D = crew[i]
		c2.rotation.z = sin(t * (2.0 + i) + i) * 0.04
		c2.position.y = _crew_y[i] + (sin(t * 12.0 + i) * 0.02 if mood == "cheer" else 0.0)


func flash() -> void:
	if not no_flash:
		super.flash()


## Steering angle for the front wheels (jeep, car), radians.
func steer_to(a: float) -> void:
	steer_angle = a
	for s in steer:
		s.rotation.y = a


## Turns into flying wrecked pieces (grey, scorched); frees this model.
## Returns the main hull piece (B3Vehicle sets it smoking).
func break_apart(battle, vel: Vector3, rng: RandomNumberGenerator) -> RigidBody3D:
	for b in blurs:
		b.visible = false
	blurs.clear()
	var main_body: RigidBody3D = null
	var is_piece := {}
	for wp in wreck:
		is_piece[wp.node] = true
	for wp in wreck:
		var n: Node3D = wp.node
		if not is_instance_valid(n):
			continue
		var xf := n.global_transform
		var sz: Vector3 = wp.size
		var off: Vector3 = wp.offset
		var rb: RigidBody3D = battle._chunk_body(Transform3D(xf.basis.orthonormalized(), xf.origin), sz, 1.0)
		rb.mass = float(wp.mass)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = sz
		cs.shape = bs
		cs.position = off
		rb.add_child(cs)
		for ch in n.get_children():
			if is_piece.has(ch) or not (ch is Node3D):
				continue
			(ch as Node3D).reparent(rb, true)
		_char(rb)
		var up := float(wp.up)
		rb.linear_velocity = vel + Vector3(rng.randf_range(-2.5, 2.5), up + rng.randf_range(0.0, 3.0), rng.randf_range(-2.5, 2.5))
		rb.angular_velocity = Vector3(rng.randf_range(-4, 4), rng.randf_range(-4, 4), rng.randf_range(-4, 4)) * (0.5 if float(wp.mass) > 40.0 else 1.0)
		if bool(wp.main):
			main_body = rb
	# the crew get X eyes, like knocked-out fighters
	for e in eyes:
		if not is_instance_valid(e):
			continue
		for c in e.get_children():
			(c as Node3D).visible = false
		for a in [45.0, -45.0]:
			var mi := MeshInstance3D.new()
			mi.mesh = B3Mats.box(Vector3(0.07, 0.02, 0.02))
			mi.material_override = B3Mats.mat(Color("1d1b2a"))
			mi.rotation_degrees = Vector3(0, 0, a)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			e.add_child(mi)
	battle._trim_chunks()
	queue_free()
	return main_body


func _char(n: Node) -> void:
	for c in n.get_children():
		if c is MeshInstance3D:
			var mi := c as MeshInstance3D
			mi.material_overlay = null
			var m := mi.material_override
			if m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_PER_PIXEL:
				var sm := m as StandardMaterial3D
				var g := sm.albedo_color.get_luminance()
				mi.material_override = B3Mats.mat(sm.albedo_color.lerp(Color(g, g, g), 0.6).darkened(0.35), sm.roughness, sm.metallic)
			elif m is StandardMaterial3D and (m as StandardMaterial3D).shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED and mi.mesh is SphereMesh:
				mi.visible = false     # headlights go out
		_char(c)
