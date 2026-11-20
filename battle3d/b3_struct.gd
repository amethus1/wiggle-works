class_name B3Struct
extends Node3D
## Buildings you can place: block, wall, ramp, tower, bunker, bridge,
## sandbags. Each is a few solid pieces (B3Piece); big blasts break pieces
## into flying physics chunks, and anything left floating falls down too.

const STONE := Color("c9c2b8")
const WOOD := Color("b07a45")
const DARKWOOD := Color("7d5230")
const CONCRETE := Color("a9afb6")
const SAND := Color("d4bb86")

var battle = null
var kind := "block"
var pieces: Array[B3Piece] = []
var length := 0.0
var _rng := RandomNumberGenerator.new()


func setup(b, k: String, len_hint: float, seed_: int) -> void:
	battle = b
	kind = k
	length = len_hint
	_rng.seed = seed_
	match kind:
		"block":
			_piece(Vector3(3.0, 1.2, 3.0), Vector3(0, 0.6, 0), STONE, 260.0)
		"wall":
			var L := clampf(len_hint if len_hint > 0.5 else 6.0, 2.0, 24.0)
			length = L
			var n := maxi(1, int(round(L / 2.0)))
			var w := L / n
			for i in n:
				var x := -L * 0.5 + w * (i + 0.5)
				for row in 2:
					var c := STONE.darkened(_rng.randf_range(0.0, 0.12))
					_piece(Vector3(w - 0.02, 1.2, 0.6), Vector3(x, 0.6 + row * 1.2, 0), c, 160.0)
			for i in n:
				var x2 := -L * 0.5 + w * (i + 0.5)
				_piece(Vector3(w * 0.45, 0.4, 0.66), Vector3(x2 - w * 0.22, 2.6, 0), STONE.darkened(0.05), 80.0)
		"ramp":
			_wedge(Vector3(2.6, 2.2, 6.0), Vector3.ZERO, 0.0, WOOD, 200.0)
		"tower":
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					_piece(Vector3(0.45, 4.2, 0.45), Vector3(1.6 * sx, 2.1, 1.6 * sz), DARKWOOD, 140.0)
			_piece(Vector3(4.0, 0.4, 4.0), Vector3(0, 4.4, 0), WOOD, 180.0)
			_piece(Vector3(4.0, 0.7, 0.25), Vector3(0, 4.95, 1.88), WOOD.darkened(0.08), 70.0)
			_piece(Vector3(4.0, 0.7, 0.25), Vector3(0, 4.95, -1.88), WOOD.darkened(0.08), 70.0)
			_piece(Vector3(0.25, 0.7, 3.5), Vector3(1.88, 4.95, 0), WOOD.darkened(0.08), 70.0)
			_piece(Vector3(0.25, 0.7, 3.5), Vector3(-1.88, 4.95, 0), WOOD.darkened(0.08), 70.0)
			# ladder + braces (decoration on the posts)
			var post: B3Piece = pieces[1]
			for i in 7:
				B3Mats.add(post, B3Mats.box(Vector3(0.08, 0.08, 0.7)), B3Mats.mat(DARKWOOD), Vector3(0.0, -1.7 + i * 0.6, -0.6), Vector3.ZERO, Vector3.ONE, false)
			B3Mats.add(post, B3Mats.box(Vector3(0.1, 4.2, 0.1)), B3Mats.mat(DARKWOOD), Vector3(0.0, 0, -0.95))
			for sx in [-1.0, 1.0]:
				var p: B3Piece = pieces[0 if sx < 0 else 2]
				B3Mats.add(p, B3Mats.box(Vector3(0.12, 4.4, 0.12)), B3Mats.mat(DARKWOOD), Vector3(0, 0, 1.6), Vector3(-45, 0, 0))
			_flag(pieces[4], Vector3(1.6, 1.25, 1.6))
		"bunker":
			var t := 0.5
			_piece(Vector3(1.8, 2.2, t), Vector3(-1.6, 1.1, -2.25), CONCRETE, 320.0)
			_piece(Vector3(1.8, 2.2, t), Vector3(1.6, 1.1, -2.25), CONCRETE, 320.0)
			_piece(Vector3(1.4, 0.6, t), Vector3(0, 1.9, -2.25), CONCRETE, 200.0)
			_piece(Vector3(t, 2.2, 4.0), Vector3(-2.25, 1.1, 0), CONCRETE.darkened(0.04), 320.0)
			_piece(Vector3(t, 2.2, 4.0), Vector3(2.25, 1.1, 0), CONCRETE.darkened(0.04), 320.0)
			_piece(Vector3(5.0, 1.2, t), Vector3(0, 0.6, 2.25), CONCRETE, 320.0)
			_piece(Vector3(5.0, 0.45, t), Vector3(0, 1.975, 2.25), CONCRETE, 220.0)
			_piece(Vector3(0.6, 0.5, t), Vector3(-1.7, 1.45, 2.25), CONCRETE, 160.0)
			_piece(Vector3(0.6, 0.5, t), Vector3(1.7, 1.45, 2.25), CONCRETE, 160.0)
			_piece(Vector3(0.6, 0.5, t), Vector3(0, 1.45, 2.25), CONCRETE, 160.0)
			_piece(Vector3(5.6, 0.45, 5.6), Vector3(0, 2.425, 0), CONCRETE.lightened(0.05), 360.0)
		"bridge":
			var deck := 8.0
			_piece(Vector3(3.0, 0.35, deck), Vector3(0, 2.4, 0), WOOD, 220.0)
			_piece(Vector3(0.15, 0.6, deck), Vector3(1.42, 2.88, 0), DARKWOOD, 60.0)
			_piece(Vector3(0.15, 0.6, deck), Vector3(-1.42, 2.88, 0), DARKWOOD, 60.0)
			for sz in [-1.0, 1.0]:
				for sx in [-1.0, 1.0]:
					_piece(Vector3(0.35, 2.3, 0.35), Vector3(1.2 * sx, 1.1, 3.5 * sz), DARKWOOD, 140.0)
			_wedge(Vector3(3.0, 2.55, 5.5), Vector3(0, 0, -deck * 0.5 - 2.75), 0.0, WOOD.lightened(0.05), 180.0)
			_wedge(Vector3(3.0, 2.55, 5.5), Vector3(0, 0, deck * 0.5 + 2.75), PI, WOOD.lightened(0.05), 180.0)
		"sandbags":
			for row in 2:
				var n2 := 5 - row
				for i in n2:
					var a := lerpf(-0.75, 0.75, (i + 0.5 * row) / 4.0)
					var r := 3.0
					var pos := Vector3(sin(a) * r, 0.21 + row * 0.42, cos(a) * r - r)
					var p2 := _piece(Vector3(0.95, 0.42, 0.5), pos, SAND.darkened(_rng.randf_range(0.0, 0.1)), 90.0)
					p2.rotation.y = a
					p2.whole = true


func _piece(s: Vector3, pos: Vector3, c: Color, hp: float) -> B3Piece:
	var p := B3Piece.new()
	p.structure = self
	p.set_meta("pi", pieces.size())     # its number, the same on every computer (multiplayer)
	p.size = s
	p.hp = hp
	p.col = c
	p.position = pos
	p.collision_layer = B3Defs.L_STRUCT
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = s
	cs.shape = bs
	p.add_child(cs)
	B3Mats.add(p, B3Mats.box(s), B3Mats.mat(c, 0.85))
	add_child(p)
	pieces.append(p)
	return p


## A ramp: rises toward local +Z (rotated by `yaw`).
func _wedge(s: Vector3, pos: Vector3, yaw: float, c: Color, hp: float) -> B3Piece:
	var p := B3Piece.new()
	p.structure = self
	p.set_meta("pi", pieces.size())     # its number, the same on every computer (multiplayer)
	p.size = s
	p.hp = hp
	p.col = c
	p.wedge = true
	p.whole = true
	p.position = pos
	p.rotation.y = yaw
	p.collision_layer = B3Defs.L_STRUCT
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var w := s.x * 0.5
	var l := s.z * 0.5
	shape.points = PackedVector3Array([
		Vector3(-w, 0, -l), Vector3(w, 0, -l), Vector3(-w, 0, l), Vector3(w, 0, l),
		Vector3(-w, s.y, l), Vector3(w, s.y, l)])
	cs.shape = shape
	p.add_child(cs)
	B3Mats.add(p, B3Mats.prism(Vector3(s.z, s.y, s.x), 1.0), B3Mats.mat(c, 0.85), Vector3(0, s.y * 0.5, 0), Vector3(0, -90, 0))
	# planks
	var slope := atan2(s.y, s.z)
	for i in 6:
		var z := lerpf(-l + 0.4, l - 0.4, i / 5.0)
		var y := (z + l) / s.z * s.y
		B3Mats.add(p, B3Mats.box(Vector3(s.x + 0.04, 0.06, 0.12)), B3Mats.mat(c.darkened(0.2)), Vector3(0, y + 0.03, z), Vector3(-rad_to_deg(slope), 0, 0), Vector3.ONE, false)
	add_child(p)
	pieces.append(p)
	return p


func _flag(on: Node3D, pos: Vector3) -> void:
	B3Mats.add(on, B3Mats.cyl(0.04, 0.04, 2.3, 6), B3Mats.mat(Color("eeeeee"), 0.4), pos)
	B3Mats.add(on, B3Mats.box(Vector3(0.04, 0.5, 0.8)), B3Mats.mat(Color("ffcf4a")), pos + Vector3(0, 0.85, -0.4))


## Gives every piece a number if it hasn't got one (History battles add their own pieces).
func number_pieces() -> void:
	var used := {}
	for pc in pieces:
		if pc.has_meta("pi"):
			used[int(pc.get_meta("pi"))] = true
	var n := 0
	for pc in pieces:
		if not pc.has_meta("pi"):
			while used.has(n):
				n += 1
			pc.set_meta("pi", n)
			used[n] = true


## Every piece as plain numbers, for saves and friends' screens: [number,
## size xyz, local transform (12), color rgb, hp, wedge, whole] each.
func piece_data() -> Array:
	number_pieces()
	var out: Array = []
	for pc in pieces:
		if not is_instance_valid(pc):
			continue
		var xf := pc.transform
		var c := pc.col
		out.append([int(pc.get_meta("pi")), pc.size.x, pc.size.y, pc.size.z,
			xf.basis.x.x, xf.basis.x.y, xf.basis.x.z, xf.basis.y.x, xf.basis.y.y, xf.basis.y.z,
			xf.basis.z.x, xf.basis.z.y, xf.basis.z.z, xf.origin.x, xf.origin.y, xf.origin.z,
			c.r, c.g, c.b, pc.hp, int(pc.wedge), int(pc.whole)])
	return out


## Builds the pieces back from piece_data().
func build_from(data: Array) -> void:
	for e in data:
		var a: Array = e
		if a.size() < 22:
			continue
		var size := Vector3(float(a[1]), float(a[2]), float(a[3]))
		var col := Color(float(a[16]), float(a[17]), float(a[18]))
		var p: B3Piece = _slope_piece(size, col, float(a[19])) if int(a[20]) != 0 else _piece(size, Vector3.ZERO, col, float(a[19]))
		p.transform = Transform3D(Basis(Vector3(float(a[4]), float(a[5]), float(a[6])), Vector3(float(a[7]), float(a[8]), float(a[9])),
			Vector3(float(a[10]), float(a[11]), float(a[12]))), Vector3(float(a[13]), float(a[14]), float(a[15])))
		p.whole = int(a[21]) != 0
		p.set_meta("pi", int(a[0]))


## A plain earth slope rising toward local +Z (no planks).
func _slope_piece(s: Vector3, c: Color, hp: float) -> B3Piece:
	var p := B3Piece.new()
	p.structure = self
	p.size = s
	p.hp = hp
	p.col = c
	p.wedge = true
	p.whole = true
	p.collision_layer = B3Defs.L_STRUCT
	p.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := ConvexPolygonShape3D.new()
	var w := s.x * 0.5
	var l := s.z * 0.5
	shape.points = PackedVector3Array([
		Vector3(-w, 0, -l), Vector3(w, 0, -l), Vector3(-w, 0, l), Vector3(w, 0, l),
		Vector3(-w, s.y, l), Vector3(w, s.y, l)])
	cs.shape = shape
	p.add_child(cs)
	B3Mats.add(p, B3Mats.prism(Vector3(s.z, s.y, s.x), 1.0), B3Mats.mat(c, 0.95), Vector3(0, s.y * 0.5, 0), Vector3(0, -90, 0))
	add_child(p)
	pieces.append(p)
	return p


func is_empty() -> bool:
	return pieces.is_empty()


## After pieces break: anything not connected to the ground falls.
func settle() -> void:
	if pieces.is_empty():
		return
	var n := pieces.size()
	var boxes: Array[AABB] = []
	for p in pieces:
		boxes.append(p.world_aabb())
	var supported := []
	supported.resize(n)
	var queue: Array[int] = []
	for i in n:
		var bx: AABB = boxes[i]
		var c := bx.get_center()
		var gh: float = battle.world.height_at(c.x, c.z)
		if bx.position.y < gh + 0.35:
			supported[i] = true
			queue.append(i)
		else:
			supported[i] = false
	while not queue.is_empty():
		var i: int = queue.pop_back()
		var a: AABB = boxes[i].grow(0.08)
		for j in n:
			if supported[j]:
				continue
			if a.intersects(boxes[j]):
				supported[j] = true
				queue.append(j)
	var falling: Array[B3Piece] = []
	for i in n:
		if not supported[i]:
			falling.append(pieces[i])
	for p in falling:
		battle.break_piece(p, Vector3.ZERO, true)
